//go:build linux && !android

package linuxtun

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"time"

	"golang.org/x/sys/unix"
	"rainlink.local/host/internal/linuxprocess"
	"rainlink.local/host/internal/privatefs"
)

const (
	coreStopTimeout = 4 * time.Second
	coreStopGrace   = 500 * time.Millisecond
	watcherReadyTTL = 2 * time.Second
)

func stopOrphanCore(ctx context.Context, identity linuxprocess.Identity, namespace string) (result error) {
	process, err := linuxprocess.Open(identity)
	if errors.Is(err, linuxprocess.ErrNotAlive) {
		return nil
	}
	if err != nil {
		return err
	}
	defer func() { result = errors.Join(result, process.Close()) }()
	ctx, cancel := context.WithTimeout(ctx, coreStopTimeout)
	defer cancel()
	actual, err := linuxprocess.NetworkNamespace(identity.PID)
	if errors.Is(err, os.ErrNotExist) || errors.Is(err, unix.ESRCH) {
		return process.Wait(ctx)
	}
	if err != nil || actual != namespace {
		return errors.Join(ErrNamespace, err)
	}
	if err = ctx.Err(); err != nil {
		return err
	}
	if err = process.Signal(unix.SIGTERM); err != nil && !errors.Is(err, linuxprocess.ErrNotAlive) {
		return fmt.Errorf("stop orphan TUN core: %w", err)
	}
	grace, graceCancel := context.WithTimeout(ctx, coreStopGrace)
	err = process.Wait(grace)
	graceCancel()
	if err == nil || ctx.Err() != nil || !errors.Is(err, context.DeadlineExceeded) {
		return err
	}
	if err = process.Signal(unix.SIGKILL); err != nil && !errors.Is(err, linuxprocess.ErrNotAlive) {
		return fmt.Errorf("terminate orphan TUN core: %w", err)
	}
	return process.Wait(ctx)
}

// RecoverOrphan is reserved for the root watchdog. Unlike Recover, it can stop
// a bound core, but only after the recorded guardian has died. The expected
// owner prevents a delayed watchdog from touching a newer session's journal.
func (c *Controller) RecoverOrphan(ctx context.Context, owner linuxprocess.Identity) (result error) {
	if os.Geteuid() != 0 || !owner.Valid() || owner.PID == os.Getpid() {
		return errors.New("invalid TUN watchdog recovery owner")
	}
	ctx, cancel := context.WithTimeout(ctx, operationTimeout)
	defer cancel()
	directory, unlock, err := c.lock(ctx)
	if err != nil {
		return err
	}
	defer func() { result = errors.Join(result, release(directory, unlock)) }()
	return c.recoverOrphanLocked(ctx, directory, owner)
}

func (c *Controller) recoverOrphanLocked(ctx context.Context, directory *privatefs.Directory, owner linuxprocess.Identity) error {
	record, err := readJournal(directory)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if record.Owner != owner {
		return ErrOwned
	}
	alive, err := linuxprocess.Alive(owner)
	if err != nil {
		return err
	}
	if alive {
		return ErrOwned
	}
	current, alive, err := linuxprocess.ReadIdentity(os.Getpid())
	if err != nil || !alive || current.Boot != owner.Boot {
		return errors.Join(errors.New("TUN watchdog boot identity changed"), err)
	}
	namespace, err := linuxprocess.NetworkNamespace(os.Getpid())
	if err != nil || namespace != record.Namespace {
		return errors.Join(ErrNamespace, err)
	}
	if record.Core != nil {
		if err = stopOrphanCore(ctx, *record.Core, namespace); err != nil {
			return err
		}
	}
	return c.restoreRecord(ctx, directory, record)
}

// WatchOwner monitors its root parent, acknowledges the inherited ready pipe,
// then recovers only that parent's orphaned journal. A permission helper must
// wait for readiness before acquiring resources or releasing core input, and
// monitor watchdog exit throughout the session. This API does not elevate.
func (c *Controller) WatchOwner(ctx context.Context, owner linuxprocess.Identity, ready *os.File) (result error) {
	if ready == nil {
		return errors.New("TUN watchdog readiness pipe missing")
	}
	readyClosed := false
	defer func() {
		if !readyClosed {
			result = errors.Join(result, ready.Close())
		}
	}()
	if os.Geteuid() != 0 || !owner.Valid() || owner.PID != os.Getppid() {
		return errors.New("TUN watchdog requires its live root parent")
	}
	process, err := linuxprocess.Open(owner)
	if err != nil {
		return err
	}
	defer func() { result = errors.Join(result, process.Close()) }()
	if err = linuxprocess.VerifyUID(owner, 0); err != nil {
		return err
	}
	parentNamespace, err := linuxprocess.NetworkNamespace(owner.PID)
	if err != nil {
		return err
	}
	namespace, err := linuxprocess.NetworkNamespace(os.Getpid())
	if err != nil || parentNamespace != namespace {
		return errors.Join(ErrNamespace, err)
	}
	info, err := ready.Stat()
	if err != nil || info.Mode()&os.ModeNamedPipe == 0 {
		return errors.Join(errors.New("invalid TUN watchdog readiness pipe"), err)
	}
	if err = ctx.Err(); err != nil {
		return err
	}
	if err = ready.SetWriteDeadline(time.Now().Add(watcherReadyTTL)); err != nil {
		return err
	}
	count, err := ready.Write([]byte{1})
	if err != nil {
		return err
	}
	if count != 1 {
		return io.ErrShortWrite
	}
	err = ready.Close()
	readyClosed = true
	if err != nil {
		return err
	}
	if err = process.Wait(ctx); err != nil {
		return err
	}
	// A cancelled operation must not cancel cleanup after the owner has died.
	recovery, cancel := context.WithTimeout(context.Background(), operationTimeout)
	defer cancel()
	return c.RecoverOrphan(recovery, owner)
}
