//go:build linux && !android

// Package linuxproxy owns a single recoverable proxy lease across Linux desktops.
package linuxproxy

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"time"

	"rainlink.local/host/internal/linuxprocess"
	"rainlink.local/host/internal/privatefs"
	"rainlink.local/host/internal/securestore"
)

// Keep the original name and encryption scope so pre-KDE GNOME leases recover.
const journalName = "gnome-proxy-recovery.bin"
const operationTimeout = 20 * time.Second

// ErrUnavailable means the selected desktop backend is unavailable or locked.
var ErrUnavailable = errors.New("Linux system proxy unavailable")

// ErrOwned means another live RainLink host still owns the user proxy lease.
var ErrOwned = errors.New("another RainLink host owns the system proxy")

type owner = linuxprocess.Identity
type journal struct {
	Version   int    `json:"version"`
	Backend   string `json:"backend,omitempty"`
	Binding   string `json:"binding,omitempty"`
	Owner     owner  `json:"owner"`
	Before    values `json:"before"`
	Owned     values `json:"owned"`
	Applied   bool   `json:"applied"`
	Restoring values `json:"restoring,omitempty"`
}

// Controller coordinates a single durable, per-user desktop proxy lease.
type Controller struct {
	directory string
	backend   backend
	backends  map[string]backend
	store     securestore.Store
}

// New uses shared user state so separate app checkouts cannot both own capture.
func New() (*Controller, error) {
	root, err := privatefs.UserStateRoot()
	if err != nil {
		return nil, err
	}
	backends := map[string]backend{"gnome": gsettingsBackend{}, "kde": kdeBackend{}}
	var selected backend
	if IsKDE() {
		selected = backends["kde"]
	} else if IsGNOME() {
		selected = backends["gnome"]
	}
	return &Controller{directory: filepath.Join(root, "RainLink", "system-proxy"), backend: selected, backends: backends, store: securestore.NewLinuxStore()}, nil
}

// Available observes the selected desktop's writability without changing it.
func Available(ctx context.Context) bool {
	ctx, cancel := context.WithTimeout(ctx, time.Second)
	defer cancel()
	if IsKDE() {
		return (kdeBackend{}).Available(ctx)
	}
	return (gsettingsBackend{}).Available(ctx)
}

func (c *Controller) recoveryBackend(record *journal) backend {
	id := record.Backend
	if record.Version == 1 {
		id = "gnome"
	}
	if c.backend != nil && c.backend.ID() == id {
		return c.backend
	}
	return c.backends[id]
}

func (c *Controller) scope() string {
	digest := sha256.Sum256([]byte(filepath.Clean(c.directory)))
	return "gnome-proxy-recovery/" + hex.EncodeToString(digest[:])
}

func (c *Controller) withLock(ctx context.Context, work func(*privatefs.Directory) error) (result error) {
	ctx, cancel := context.WithTimeout(ctx, operationTimeout)
	defer cancel()
	dir, err := privatefs.Open(c.directory)
	if err != nil {
		return err
	}
	defer func() { result = errors.Join(result, dir.Close()) }()
	release, err := dir.Lock(ctx, "system-proxy.lock")
	if err != nil {
		return err
	}
	defer func() { result = errors.Join(result, release()) }()
	return work(dir)
}

func (c *Controller) read(ctx context.Context, dir *privatefs.Directory) (*journal, error) {
	data, err := dir.Read(journalName, 32<<10)
	if err != nil {
		return nil, err
	}
	plain, err := c.store.Unseal(ctx, string(data), c.scope())
	clear(data)
	if err != nil {
		return nil, err
	}
	defer clear(plain)
	decoder := json.NewDecoder(bytes.NewReader(plain))
	decoder.DisallowUnknownFields()
	var record journal
	if err = decoder.Decode(&record); err != nil {
		return nil, errors.New("invalid Linux proxy recovery journal")
	}
	var extra any
	if err = decoder.Decode(&extra); err != io.EOF {
		return nil, errors.New("trailing Linux proxy recovery data")
	}
	versionValid := record.Version == 1 && record.Backend == "" && record.Binding == "" || record.Version == 2 && len(record.Binding) == 64
	b := c.recoveryBackend(&record)
	if !versionValid || b == nil || record.Owner.PID < 2 || record.Owner.Start == 0 || len(record.Owner.Boot) != 36 || !validValues(b.Settings(), record.Before) || !validValues(b.Settings(), record.Owned) {
		return nil, errors.New("invalid Linux proxy recovery state")
	}
	if record.Restoring != nil && !validValues(b.Settings(), record.Restoring) {
		return nil, errors.New("invalid Linux proxy restoration state")
	}
	return &record, nil
}

func validValues(settings []setting, data values) bool {
	if len(data) != len(settings) {
		return false
	}
	for _, item := range settings {
		value, ok := data[item.id()]
		if !ok || len(value) > maxSettingBytes || strings.ContainsAny(value, "\r\n\x00") {
			return false
		}
	}
	return true
}

func recoveryFits(b backend, record *journal) bool {
	// Reserve room for a complete durable restoration, including a bypass edit
	// at the backend's size limit. Otherwise apply could succeed but a later
	// rollback would be too large for the encrypted-record format.
	probe := *record
	probe.Restoring = make(values, len(record.Before))
	for key, value := range record.Before {
		probe.Restoring[key] = value
	}
	for _, item := range b.Settings() {
		if !item.routing {
			probe.Restoring[item.id()] = strings.Repeat("\x01", maxSettingBytes)
		}
	}
	plain, err := json.Marshal(&probe)
	defer clear(plain)
	return err == nil && len(plain) <= securestore.MaxPlaintextBytes
}

func (c *Controller) write(ctx context.Context, dir *privatefs.Directory, record *journal, exclusive bool) error {
	plain, err := json.Marshal(record)
	if err != nil {
		return err
	}
	defer clear(plain)
	sealed, err := c.store.Seal(ctx, plain, c.scope())
	if err != nil {
		return err
	}
	return dir.Write(journalName, []byte(sealed), exclusive)
}

func processOwner(pid int) (owner, bool, error) {
	return linuxprocess.ReadIdentity(pid)
}

func (c *Controller) restoreLocked(ctx context.Context, dir *privatefs.Directory) error {
	record, err := c.read(ctx, dir)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("read proxy recovery: %w", err)
	}
	currentOwner, alive, err := processOwner(record.Owner.PID)
	if err != nil {
		return err
	}
	if alive && currentOwner == record.Owner && record.Owner.PID != os.Getpid() {
		return ErrOwned
	}
	b := c.recoveryBackend(record)
	if record.Version == 2 {
		binding, err := b.Binding()
		if err != nil || binding != record.Binding {
			return errors.Join(errors.New("proxy recovery configuration directory changed"), err)
		}
	}
	current, err := b.Snapshot(ctx)
	if err != nil {
		return err
	}
	if !validValues(b.Settings(), current) {
		return errors.New("incomplete Linux proxy readback")
	}
	// A later routing owner wins. A bypass-only edit keeps its value while we
	// restore endpoints that still point at our dead local listener.
	routingChanged := false
	for _, item := range b.Settings() {
		if !item.routing {
			continue
		}
		value := current[item.id()]
		allowed := value == record.Owned[item.id()]
		if record.Restoring != nil {
			allowed = allowed || value == record.Restoring[item.id()]
		} else if !record.Applied {
			allowed = allowed || value == record.Before[item.id()]
		}
		if !allowed {
			routingChanged = true
		}
	}
	if !routingChanged {
		restore := make(values, len(current))
		for key, value := range current {
			restore[key] = value
			if record.Restoring != nil {
				restore[key] = record.Restoring[key]
			}
			if record.Restoring == nil && value == record.Owned[key] {
				restore[key] = record.Before[key]
			}
		}
		for _, item := range b.Settings() {
			if !item.routing && current[item.id()] != record.Owned[item.id()] {
				restore[item.id()] = current[item.id()]
			}
		}
		if !reflect.DeepEqual(current, restore) {
			record.Restoring = restore
			if err = c.write(ctx, dir, record, false); err != nil {
				return err
			}
			if err = b.Write(ctx, restore); err != nil {
				return err
			}
			actual, err := b.Snapshot(ctx)
			if err != nil {
				return err
			}
			if !reflect.DeepEqual(actual, restore) {
				return errors.New("Linux proxy recovery readback mismatch")
			}
		}
	}
	return dir.Remove(journalName)
}

// Restore follows the recorded backend, including after a desktop change.
func (c *Controller) Restore(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, operationTimeout)
	defer cancel()
	return c.withLock(ctx, func(dir *privatefs.Directory) error { return c.restoreLocked(ctx, dir) })
}

// Apply commits a recovery journal before any settings change, then verifies it.
func (c *Controller) Apply(ctx context.Context, port int) error {
	if port < 1 || port > 65535 {
		return errors.New("invalid proxy port")
	}
	ctx, cancel := context.WithTimeout(ctx, operationTimeout)
	defer cancel()
	if c.backend == nil || !c.backend.Available(ctx) {
		if err := ctx.Err(); err != nil {
			return err
		}
		return ErrUnavailable
	}
	return c.withLock(ctx, func(dir *privatefs.Directory) error {
		if err := c.restoreLocked(ctx, dir); err != nil {
			return err
		}
		before, err := c.backend.Snapshot(ctx)
		if err != nil {
			return err
		}
		if !validValues(c.backend.Settings(), before) {
			return errors.New("incomplete Linux proxy snapshot")
		}
		identity, alive, err := processOwner(os.Getpid())
		if err != nil || !alive {
			return errors.Join(errors.New("proxy owner identity unavailable"), err)
		}
		binding, err := c.backend.Binding()
		if err != nil {
			return err
		}
		record := &journal{Version: 2, Backend: c.backend.ID(), Binding: binding, Owner: identity, Before: before, Owned: c.backend.Owned(port)}
		if !recoveryFits(c.backend, record) {
			return errors.New("proxy settings exceed encrypted recovery capacity")
		}
		if err = c.write(ctx, dir, record, true); err != nil {
			return err
		}
		applyErr := c.backend.Write(ctx, record.Owned)
		if applyErr == nil {
			actual, readErr := c.backend.Snapshot(ctx)
			if readErr != nil {
				applyErr = readErr
			} else if !reflect.DeepEqual(actual, record.Owned) {
				var mismatched []string
				for _, item := range c.backend.Settings() {
					if actual[item.id()] != record.Owned[item.id()] {
						mismatched = append(mismatched, item.id())
					}
				}
				// Identify fields without disclosing proxy credentials or PAC URLs.
				applyErr = fmt.Errorf("Linux proxy apply readback mismatch: %s", strings.Join(mismatched, ", "))
			}
		}
		if applyErr == nil {
			applyErr = ctx.Err()
		}
		if applyErr == nil {
			record.Applied = true
			applyErr = c.write(ctx, dir, record, false)
		}
		if applyErr == nil {
			return nil
		}
		// Cancellation must not cancel rollback. Keep the journal on any failure.
		cleanup, cancel := context.WithTimeout(context.Background(), operationTimeout)
		defer cancel()
		rollbackErr := c.restoreLocked(cleanup, dir)
		return errors.Join(applyErr, rollbackErr)
	})
}
