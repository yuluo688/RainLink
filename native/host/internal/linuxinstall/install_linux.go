//go:build linux && !android

// Package linuxinstall owns fixed-path, recoverable Linux TUN service updates.
package linuxinstall

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"golang.org/x/sys/unix"
	"rainlink.local/host/internal/coreprocess"
	"rainlink.local/host/internal/linuxtun"
	"rainlink.local/host/internal/privatefs"
	"rainlink.local/host/internal/rootfs"
	assets "rainlink.local/host/packaging/linux"
)

const operationTimeout = 3 * time.Minute

type services interface {
	state(context.Context) (serviceState, error)
	quiesce(context.Context) error
	enable(context.Context, bool) error
	reload(context.Context) error
	start(context.Context) error
	ready(context.Context) error
}

type capture interface {
	Recover(context.Context) error
	ConfirmIdle(context.Context) error
}

type installer struct {
	state       *privatefs.Directory
	spool       *rootfs.Directory
	directories [len(targets)]*rootfs.Directory
	services    services
	capture     capture
	// Only tests install a checkpoint. Production has no fault-injection input.
	checkpoint func(string) error
}

// Run accepts only install-tun, uninstall-tun, and recover-tun-install. Install
// copies this running host and its sibling locked core, never a caller path.
func Run(parent context.Context, action string) (result error) {
	if os.Geteuid() != 0 {
		return errors.New("TUN service installation requires an administrator")
	}
	if action != "install-tun" && action != "uninstall-tun" && action != "recover-tun-install" {
		return errors.New("unsupported installation operation")
	}
	ctx, cancel := context.WithTimeout(parent, operationTimeout)
	defer cancel()
	controller, err := linuxtun.New()
	if err != nil {
		return err
	}
	service := systemServices{}
	if err = service.preflight(ctx, action == "install-tun"); err != nil {
		return err
	}
	i, err := openInstaller("", service, controller)
	if err != nil {
		return err
	}
	defer func() { result = errors.Join(result, i.close()) }()
	unlock, err := i.state.Lock(ctx, "install.lock")
	if err != nil {
		return err
	}
	defer func() { result = errors.Join(result, unlock()) }()
	if err = i.recover(ctx); err != nil {
		return fmt.Errorf("installation recovery pending: %w", err)
	}
	if action == "recover-tun-install" {
		return nil
	}
	var source *os.File
	if action == "install-tun" {
		source, err = os.Open("/proc/self/exe")
		if err != nil {
			return err
		}
		defer func() { result = errors.Join(result, source.Close()) }()
	}
	return i.change(ctx, action == "install-tun", source)
}

// root is private test injection. Public Run always uses the fixed system root.
func openInstaller(root string, service services, controller capture) (_ *installer, result error) {
	i := &installer{services: service, capture: controller}
	defer func() {
		if result != nil {
			result = errors.Join(result, i.close())
		}
	}()
	path := root + statePath
	spool, err := rootfs.Open(path, true, 0700)
	if err != nil {
		return nil, err
	}
	i.spool = spool
	i.state, err = privatefs.Open(path)
	if err != nil {
		return nil, err
	}
	for index, value := range targets {
		i.directories[index], err = rootfs.Open(root+filepath.Dir(value.path), true, 0755)
		if err != nil {
			return nil, err
		}
	}
	return i, nil
}

func (i *installer) close() error {
	var result error
	for _, directory := range i.directories {
		if directory != nil {
			result = errors.Join(result, directory.Close())
		}
	}
	if i.state != nil {
		result = errors.Join(result, i.state.Close())
	}
	if i.spool != nil {
		result = errors.Join(result, i.spool.Close())
	}
	return result
}

func (i *installer) point(name string) error {
	if i.checkpoint != nil {
		return i.checkpoint(name)
	}
	return nil
}

func (i *installer) prepare(ctx context.Context, source *os.File) (_ *manifest, result error) {
	if source == nil {
		return nil, errors.New("missing installer executable")
	}
	if err := i.copyStaged(ctx, 0, false, source); err != nil {
		return nil, err
	}
	executable, err := os.Executable()
	if err != nil {
		return nil, err
	}
	fd, err := unix.Open(filepath.Join(filepath.Dir(executable), "sing-box"), unix.O_RDONLY|unix.O_CLOEXEC|unix.O_NOFOLLOW|unix.O_NONBLOCK, 0)
	if err != nil {
		return nil, fmt.Errorf("open bundled core: %w", err)
	}
	core := os.NewFile(uintptr(fd), "bundled core")
	defer func() { result = errors.Join(result, core.Close()) }()
	if info, err := core.Stat(); err != nil || !info.Mode().IsRegular() || info.Size() < 1 || info.Size() > targets[1].limit {
		return nil, errors.Join(errors.New("bundled core is not a bounded regular file"), err)
	}
	if err = i.copyStaged(ctx, 1, false, core); err != nil {
		return nil, err
	}
	return i.finishCandidates(ctx)
}

func (i *installer) finishCandidates(ctx context.Context) (_ *manifest, result error) {
	core, err := i.spool.OpenFile(stagedName(1, false))
	if err != nil {
		return nil, err
	}
	trusted := coreprocess.TrustedFile(core)
	if err = core.Close(); err != nil {
		return nil, err
	}
	if !trusted {
		return nil, errors.New("bundled core does not match this host's locked release")
	}
	for index := 2; index < len(targets); index++ {
		data, err := assets.Files.ReadFile(filepath.Base(targets[index].path))
		if err != nil {
			return nil, err
		}
		if err = i.spool.Replace(ctx, stagedName(index, false), bytes.NewReader(data), targets[index].limit, 0600); err != nil {
			return nil, err
		}
	}
	value := &manifest{Version: 1}
	for index := range targets {
		file, err := i.spool.OpenFile(stagedName(index, false))
		if err != nil {
			return nil, err
		}
		digest, readErr := rootfs.Inspect(ctx, file, targets[index].limit)
		if err = errors.Join(readErr, file.Close()); err != nil {
			return nil, err
		}
		digest.Mode = targets[index].mode
		value.Files[index] = digest
	}
	return value, value.validate()
}

func (i *installer) backup(ctx context.Context, value *manifest) error {
	if value == nil {
		return nil
	}
	for index := range targets {
		file, err := i.directories[index].OpenFile(filepath.Base(targets[index].path))
		if err != nil {
			return err
		}
		err = errors.Join(i.copyStaged(ctx, index, true, file), file.Close())
		if err != nil {
			return err
		}
		if err = i.inspectStaged(ctx, index, true, value.Files[index]); err != nil {
			return err
		}
	}
	return nil
}

func (i *installer) quiesce(ctx context.Context) error {
	if err := i.services.quiesce(ctx); err != nil {
		return fmt.Errorf("stop permission sessions: %w", err)
	}
	// Never treat the service exit hook's skipped-active outcome as recovery.
	if err := i.capture.Recover(ctx); err != nil {
		return fmt.Errorf("restore network before file changes: %w", err)
	}
	if err := i.capture.ConfirmIdle(ctx); err != nil {
		return fmt.Errorf("confirm stopped capture: %w", err)
	}
	return nil
}

func (i *installer) change(ctx context.Context, install bool, source *os.File) (result error) {
	before, err := readManifest(i.state)
	if err != nil {
		return err
	}
	if err = i.verifyFiles(ctx, before); err != nil {
		return err
	}
	state, err := i.services.state(ctx)
	if err != nil {
		return err
	}
	if state.Present != (before != nil) {
		return errors.New("service ownership does not match the installation manifest")
	}
	if !install && before == nil {
		return nil
	}
	if err = i.clearStaged(); err != nil {
		return err
	}
	var after *manifest
	if install {
		after, err = i.prepare(ctx, source)
		if err != nil {
			return err
		}
	}
	return i.transact(ctx, before, after, state)
}

func (i *installer) transact(ctx context.Context, before, after *manifest, state serviceState) (result error) {
	if err := i.backup(ctx, before); err != nil {
		return err
	}
	record := &transaction{Version: 1, Before: before, After: after, Service: state}
	if err := writeJSON(i.state, journalName, record, true); err != nil {
		return err
	}
	// Any uncertain error keeps the durable journal. Rollback uses a new bounded
	// context, including when the original request was cancelled.
	defer func() {
		if result != nil {
			recovery, cancel := context.WithTimeout(context.Background(), operationTimeout)
			defer cancel()
			if err := i.recover(recovery); err != nil {
				result = errors.Join(result, fmt.Errorf("rollback pending: %w", err))
			}
		}
	}()
	if err := i.point("journal"); err != nil {
		return err
	}
	if err := i.quiesce(ctx); err != nil {
		return err
	}
	if err := i.services.enable(ctx, false); err != nil {
		return err
	}
	if err := i.point("stopped"); err != nil {
		return err
	}
	// Recheck after stopping: administrator edits are preserved, even if they
	// arrived between preparing the backup and stopping socket activation.
	if err := i.verifyFiles(ctx, before); err != nil {
		return err
	}
	for index := range targets {
		if err := i.applyFile(ctx, index, false, entry(after, index)); err != nil {
			return err
		}
		if err := i.point(fmt.Sprintf("file-%d", index)); err != nil {
			return err
		}
	}
	if err := i.services.reload(ctx); err != nil {
		return err
	}
	if after != nil {
		desired := state
		if before == nil {
			desired = serviceState{Present: true, Enabled: true, Active: true}
		}
		if err := i.services.enable(ctx, desired.Enabled); err != nil {
			return err
		}
		if desired.Active {
			if err := i.services.start(ctx); err != nil {
				return err
			}
			if err := i.services.ready(ctx); err != nil {
				return err
			}
		}
		if err := i.verifyService(ctx, desired); err != nil {
			return err
		}
	} else if err := i.verifyService(ctx, serviceState{}); err != nil {
		return err
	}
	if err := i.point("started"); err != nil {
		return err
	}
	if err := i.verifyFiles(ctx, after); err != nil {
		return err
	}
	if err := i.saveManifest(after); err != nil {
		return err
	}
	if err := i.point("manifest"); err != nil {
		return err
	}
	record.Committed = true
	if err := writeJSON(i.state, journalName, record, false); err != nil {
		return err
	}
	if err := i.point("committed"); err != nil {
		return err
	}
	return i.finish()
}

func (i *installer) recover(ctx context.Context) error {
	record, err := i.readTransaction()
	if err != nil {
		return err
	}
	if record == nil {
		if _, err := readManifest(i.state); err != nil {
			return err
		}
		return i.clearStaged()
	}
	currentManifest, err := readManifest(i.state)
	if err != nil {
		return err
	}
	// Metadata is root-private, but corruption must still stop recovery.
	sameManifest := func(a, b *manifest) bool { return (a == nil && b == nil) || (a != nil && b != nil && *a == *b) }
	if record.Committed {
		if !sameManifest(currentManifest, record.After) {
			return errors.New("committed installation manifest changed")
		}
		if err = i.verifyFiles(ctx, record.After); err != nil {
			return err
		}
		return i.finish()
	}
	if !sameManifest(currentManifest, record.Before) && !sameManifest(currentManifest, record.After) {
		return errors.New("installation manifest changed outside the transaction")
	}
	// Validate ALL backups and ALL destinations before stopping or replacing
	// anything. Partial recovery can be retried without overwriting unknown data.
	for index := range targets {
		actual, err := i.inspect(ctx, index)
		if err != nil {
			return err
		}
		if !equal(actual, entry(record.Before, index)) && !equal(actual, entry(record.After, index)) {
			return fmt.Errorf("file %d changed outside the transaction", index)
		}
		if record.Before != nil {
			if err = i.inspectStaged(ctx, index, true, record.Before.Files[index]); err != nil {
				return err
			}
		}
	}
	if err = i.quiesce(ctx); err != nil {
		return err
	}
	if record.Before == nil {
		if err = i.services.enable(ctx, false); err != nil {
			return err
		}
	}
	for index := range targets {
		if err = i.applyFile(ctx, index, true, entry(record.Before, index)); err != nil {
			return err
		}
	}
	if err = i.saveManifest(record.Before); err != nil {
		return err
	}
	if err = i.services.reload(ctx); err != nil {
		return err
	}
	if record.Service.Present {
		if err = i.services.enable(ctx, record.Service.Enabled); err != nil {
			return err
		}
		if record.Service.Active {
			if err = i.services.start(ctx); err != nil {
				return err
			}
			if err = i.services.ready(ctx); err != nil {
				return err
			}
		}
	}
	if err = i.verifyFiles(ctx, record.Before); err != nil {
		return err
	}
	if err = i.verifyService(ctx, record.Service); err != nil {
		return err
	}
	// Commit the rollback before retiring backups, so interrupted cleanup never
	// tries to restore from already deleted backups.
	record.After = record.Before
	record.Committed = true
	if err = writeJSON(i.state, journalName, record, false); err != nil {
		return err
	}
	return i.finish()
}

func (i *installer) finish() error {
	if err := i.clearStaged(); err != nil {
		return err
	}
	return i.state.Remove(journalName)
}

func (i *installer) verifyService(ctx context.Context, expected serviceState) error {
	actual, err := i.services.state(ctx)
	if err != nil {
		return err
	}
	if actual != expected {
		return errors.New("permission service state did not match the requested state")
	}
	return nil
}
