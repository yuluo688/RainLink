//go:build linux && !android

package linuxinstall

import (
	"bytes"
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"rainlink.local/host/internal/privatefs"
	"rainlink.local/host/internal/rootfs"
)

const (
	statePath     = "/var/lib/rainlink/tun-install"
	manifestName  = "manifest.json"
	journalName   = "transaction.json"
	metadataLimit = 16 << 10
)

type target struct {
	path  string
	mode  uint32
	limit int64
}

// Paths and modes are compiled in. Neither IPC nor an on-disk journal can
// select a destination or command. Array positions are the stable file IDs.
var targets = [...]target{
	{"/usr/libexec/rainlink/rainlink-host", 0755, 64 << 20},
	{"/usr/libexec/rainlink/sing-box", 0755, 128 << 20},
	{"/usr/lib/systemd/system/rainlink-tun.socket", 0644, 64 << 10},
	{"/usr/lib/systemd/system/rainlink-tun@.service", 0644, 64 << 10},
	{"/usr/share/polkit-1/actions/org.rainlink.tun.policy", 0644, 64 << 10},
}

type manifest struct {
	Version int                         `json:"version"`
	Files   [len(targets)]rootfs.Digest `json:"files"`
}

type serviceState struct {
	Present bool `json:"present"`
	Enabled bool `json:"enabled"`
	Active  bool `json:"active"`
}

type transaction struct {
	Version   int          `json:"version"`
	Committed bool         `json:"committed"`
	Before    *manifest    `json:"before"`
	After     *manifest    `json:"after"`
	Service   serviceState `json:"service"`
}

func (m *manifest) validate() error {
	if m == nil {
		return nil
	}
	if m.Version != 1 {
		return errors.New("unsupported installation manifest")
	}
	for index, file := range m.Files {
		digest, err := hex.DecodeString(file.SHA256)
		if err != nil || len(digest) != 32 || hex.EncodeToString(digest) != file.SHA256 || file.Size < 1 || file.Size > targets[index].limit || file.Mode != targets[index].mode {
			return errors.New("invalid installation manifest entry")
		}
	}
	return nil
}

func readJSON(directory *privatefs.Directory, name string, value any) error {
	data, err := directory.Read(name, metadataLimit)
	if err != nil {
		return err
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err = decoder.Decode(value); err != nil {
		return fmt.Errorf("invalid installation metadata: %w", err)
	}
	if err = decoder.Decode(new(any)); !errors.Is(err, io.EOF) {
		return errors.New("trailing installation metadata")
	}
	canonical, err := json.Marshal(value)
	if err != nil || !bytes.Equal(data, canonical) {
		return errors.New("noncanonical installation metadata")
	}
	return nil
}

func writeJSON(directory *privatefs.Directory, name string, value any, exclusive bool) error {
	data, err := json.Marshal(value)
	if err != nil {
		return err
	}
	return directory.Write(name, data, exclusive)
}

func readManifest(directory *privatefs.Directory) (*manifest, error) {
	var value manifest
	err := readJSON(directory, manifestName, &value)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &value, value.validate()
}

func (i *installer) readTransaction() (*transaction, error) {
	var value transaction
	err := readJSON(i.state, journalName, &value)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if value.Version != 1 || (!value.Committed && value.Before == nil && value.After == nil) || (!value.Service.Present && (value.Service.Active || value.Service.Enabled)) || value.Service.Present != (value.Before != nil) {
		return nil, errors.New("invalid installation transaction")
	}
	return &value, errors.Join(value.Before.validate(), value.After.validate())
}

func (i *installer) inspect(ctx context.Context, index int) (*rootfs.Digest, error) {
	if i.directories[index] == nil {
		return nil, nil
	}
	file, err := i.directories[index].OpenFile(filepath.Base(targets[index].path))
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	digest, readErr := rootfs.Inspect(ctx, file, targets[index].limit)
	if err = errors.Join(readErr, file.Close()); err != nil {
		return nil, err
	}
	return &digest, nil
}

func entry(value *manifest, index int) *rootfs.Digest {
	if value == nil {
		return nil
	}
	return &value.Files[index]
}

func equal(left, right *rootfs.Digest) bool {
	return (left == nil && right == nil) || (left != nil && right != nil && *left == *right)
}

func (i *installer) verifyFiles(ctx context.Context, value *manifest) error {
	for index := range targets {
		actual, err := i.inspect(ctx, index)
		if err != nil {
			return fmt.Errorf("inspect managed file %d: %w", index, err)
		}
		if !equal(actual, entry(value, index)) {
			return fmt.Errorf("managed file %d was changed or is unmanaged; refusing replacement", index)
		}
	}
	return nil
}

func (i *installer) saveManifest(value *manifest) error {
	if value != nil {
		return writeJSON(i.state, manifestName, value, false)
	}
	err := i.state.Remove(manifestName)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	return err
}

func stagedName(index int, backup bool) string {
	if backup {
		return fmt.Sprintf("backup-%d", index)
	}
	return fmt.Sprintf("candidate-%d", index)
}

func (i *installer) inspectStaged(ctx context.Context, index int, backup bool, expected rootfs.Digest) (result error) {
	file, err := i.spool.OpenFile(stagedName(index, backup))
	if err != nil {
		return err
	}
	defer func() { result = errors.Join(result, file.Close()) }()
	digest, err := rootfs.Inspect(ctx, file, targets[index].limit)
	if err != nil {
		return err
	}
	digest.Mode = expected.Mode // Spool files remain private 0600, including executables.
	if digest != expected {
		return errors.New("installation backup/candidate integrity mismatch")
	}
	return nil
}

func (i *installer) copyStaged(ctx context.Context, index int, backup bool, source *os.File) error {
	if _, err := source.Seek(0, io.SeekStart); err != nil {
		return err
	}
	return i.spool.Replace(ctx, stagedName(index, backup), source, targets[index].limit, 0600)
}

func (i *installer) applyFile(ctx context.Context, index int, backup bool, expected *rootfs.Digest) (result error) {
	directory := i.directories[index]
	if expected == nil {
		if directory == nil {
			return nil
		}
		return directory.Remove(filepath.Base(targets[index].path))
	}
	if directory == nil {
		return errors.New("installation directory disappeared")
	}
	if err := i.inspectStaged(ctx, index, backup, *expected); err != nil {
		return err
	}
	file, err := i.spool.OpenFile(stagedName(index, backup))
	if err != nil {
		return err
	}
	defer func() { result = errors.Join(result, file.Close()) }()
	return directory.Replace(ctx, filepath.Base(targets[index].path), file, targets[index].limit, targets[index].mode)
}

// No recursive deletion: unknown files and all user data remain untouched.
func (i *installer) clearStaged() error {
	for index := range targets {
		for _, backup := range []bool{false, true} {
			if err := i.spool.Remove(stagedName(index, backup)); err != nil {
				return err
			}
		}
	}
	return nil
}
