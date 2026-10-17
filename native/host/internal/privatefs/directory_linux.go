//go:build linux && !android

// Package privatefs owns user-private Linux state without following links.
package privatefs

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"golang.org/x/sys/unix"
)

// Directory anchors all operations to one checked directory descriptor.
type Directory struct{ fd int }

// UserStateRoot resolves XDG's persistent per-user state directory.
func UserStateRoot() (string, error) {
	root := os.Getenv("XDG_STATE_HOME")
	if root == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		root = filepath.Join(home, ".local", "state")
	}
	if !filepath.IsAbs(root) {
		return "", errors.New("XDG_STATE_HOME must be absolute")
	}
	return root, nil
}

// Open creates a private directory or rejects unsafe ownership and permissions.
func Open(path string) (*Directory, error) {
	if !filepath.IsAbs(path) {
		return nil, errors.New("private state directory must be absolute")
	}
	if err := os.MkdirAll(path, 0700); err != nil {
		return nil, fmt.Errorf("create private directory: %w", err)
	}
	fd, err := unix.Open(path, unix.O_RDONLY|unix.O_DIRECTORY|unix.O_CLOEXEC|unix.O_NOFOLLOW, 0)
	if err != nil {
		return nil, fmt.Errorf("open private directory: %w", err)
	}
	var stat unix.Stat_t
	if err = unix.Fstat(fd, &stat); err != nil || stat.Uid != uint32(os.Geteuid()) || stat.Mode&0077 != 0 {
		_ = unix.Close(fd)
		return nil, errors.New("state directory must be private and owned by the user")
	}
	return &Directory{fd}, nil
}

// Close releases the directory descriptor after all child operations finish.
func (d *Directory) Close() error { return unix.Close(d.fd) }

func validName(name string) bool {
	return name != "" && name != "." && name != ".." && len(name) <= 128 && !strings.ContainsAny(name, "/\x00")
}

func (d *Directory) openFile(name string, flags int) (*os.File, error) {
	if !validName(name) {
		return nil, errors.New("invalid private state filename")
	}
	fd, err := unix.Openat(d.fd, name, flags|unix.O_CLOEXEC|unix.O_NOFOLLOW|unix.O_NONBLOCK, 0600)
	if err != nil {
		return nil, err
	}
	var stat unix.Stat_t
	if err = unix.Fstat(fd, &stat); err != nil || stat.Uid != uint32(os.Geteuid()) || stat.Mode&0077 != 0 || stat.Mode&unix.S_IFMT != unix.S_IFREG || stat.Nlink != 1 {
		_ = unix.Close(fd)
		return nil, errors.New("state file must be a private regular file owned by the user")
	}
	return os.NewFile(uintptr(fd), name), nil
}

// Lock serializes processes. The caller keeps Directory open until release.
func (d *Directory) Lock(ctx context.Context, name string) (func() error, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	file, err := d.openFile(name, unix.O_CREAT|unix.O_RDWR)
	if err != nil {
		return nil, fmt.Errorf("open state lock: %w", err)
	}
	ticker := time.NewTicker(25 * time.Millisecond)
	defer ticker.Stop()
	for {
		err = unix.Flock(int(file.Fd()), unix.LOCK_EX|unix.LOCK_NB)
		if err == nil {
			return func() error { return errors.Join(unix.Flock(int(file.Fd()), unix.LOCK_UN), file.Close()) }, nil
		}
		if !errors.Is(err, unix.EWOULDBLOCK) && !errors.Is(err, unix.EAGAIN) {
			_ = file.Close()
			return nil, fmt.Errorf("lock state file: %w", err)
		}
		select {
		case <-ctx.Done():
			_ = file.Close()
			return nil, ctx.Err()
		case <-ticker.C:
		}
	}
}

// Read refuses links and limits actual bytes, even if the file grows meanwhile.
func (d *Directory) Read(name string, limit int64) ([]byte, error) {
	if limit <= 0 {
		return nil, errors.New("invalid private read limit")
	}
	file, err := d.openFile(name, unix.O_RDONLY)
	if err != nil {
		return nil, err
	}
	data, readErr := io.ReadAll(io.LimitReader(file, limit+1))
	err = errors.Join(readErr, file.Close())
	if int64(len(data)) > limit {
		clear(data)
		return nil, errors.New("private state exceeds limit")
	}
	if err != nil {
		clear(data)
		return nil, err
	}
	return data, nil
}

// Write durably installs a full file. Exclusive writes never replace a journal.
func (d *Directory) Write(name string, data []byte, exclusive bool) (result error) {
	if !validName(name) {
		return errors.New("invalid private state filename")
	}
	var suffix [12]byte
	if _, err := rand.Read(suffix[:]); err != nil {
		return err
	}
	temporary := ".state-" + hex.EncodeToString(suffix[:]) + ".tmp"
	file, err := d.openFile(temporary, unix.O_CREAT|unix.O_EXCL|unix.O_WRONLY)
	if err != nil {
		return err
	}
	defer func() {
		if err := unix.Unlinkat(d.fd, temporary, 0); err != nil && !errors.Is(err, unix.ENOENT) {
			result = errors.Join(result, err)
		}
	}()
	n, writeErr := file.Write(data)
	if writeErr == nil && n != len(data) {
		writeErr = io.ErrShortWrite
	}
	err = errors.Join(writeErr, file.Sync(), file.Close())
	if err != nil {
		return err
	}
	if exclusive {
		err = unix.Linkat(d.fd, temporary, d.fd, name, 0)
	} else {
		err = unix.Renameat(d.fd, temporary, d.fd, name)
	}
	if err != nil {
		return err
	}
	if exclusive {
		if err = unix.Unlinkat(d.fd, temporary, 0); err != nil {
			return err
		}
	}
	return unix.Fsync(d.fd)
}

// Remove durably retires a completed recovery record without following links.
func (d *Directory) Remove(name string) error {
	if !validName(name) {
		return errors.New("invalid private state filename")
	}
	if err := unix.Unlinkat(d.fd, name, 0); err != nil {
		return err
	}
	return unix.Fsync(d.fd)
}
