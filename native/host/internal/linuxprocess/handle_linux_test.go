//go:build linux && !android

package linuxprocess

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"testing"
	"time"

	"golang.org/x/sys/unix"
)

func TestPinnedProcessMonitorCancellationSignalsAndExit(t *testing.T) {
	var empty Handle
	if err := empty.Wait(t.Context()); !errors.Is(err, os.ErrClosed) {
		t.Fatal("zero-value monitor accepted a descriptor", err)
	}
	if err := empty.Close(); err != nil {
		t.Fatal("zero-value close failed", err)
	}
	child := exec.Command("/bin/sleep", "30")
	if err := child.Start(); err != nil {
		t.Fatal(err)
	}
	reaped := false
	t.Cleanup(func() {
		if !reaped {
			_ = child.Process.Kill()
			_ = child.Wait()
		}
	})
	identity, alive, err := ReadIdentity(child.Process.Pid)
	if err != nil || !alive {
		t.Fatal("fixture identity unavailable", err)
	}
	reused := identity
	reused.Start++
	if _, err = Open(reused); !errors.Is(err, ErrNotAlive) {
		t.Fatal("monitor accepted a different process lifetime", err)
	}
	handle, err := Open(identity)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = handle.Close() })
	cancelled, cancel := context.WithCancel(t.Context())
	cancel()
	if err = handle.Wait(cancelled); !errors.Is(err, context.Canceled) {
		t.Fatal("monitor ignored cancellation", err)
	}
	deadline, deadlineCancel := context.WithTimeout(t.Context(), 20*time.Millisecond)
	err = handle.Wait(deadline)
	deadlineCancel()
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal("monitor did not bound a live-process wait", err)
	}
	if err = handle.Signal(unix.SIGSTOP); err == nil {
		t.Fatal("monitor allowed a signal outside shutdown")
	}
	if alive, err = Alive(identity); err != nil || !alive {
		t.Fatal("cancelled or rejected operation harmed the child", err)
	}
	if err = handle.Signal(unix.SIGTERM); err != nil {
		t.Fatal(err)
	}
	ctx, finish := context.WithTimeout(t.Context(), time.Second)
	defer finish()
	if err = handle.Wait(ctx); err != nil {
		t.Fatal("pidfd did not observe child exit", err)
	}
	_ = child.Wait()
	reaped = true
	if _, err = Open(identity); !errors.Is(err, ErrNotAlive) {
		t.Fatal("exited identity opened a live monitor", err)
	}
	if err = handle.Signal(unix.SIGKILL); !errors.Is(err, ErrNotAlive) {
		t.Fatal("signal after exit did not report the pinned lifetime's exit", err)
	}
	if err = handle.Close(); err != nil {
		t.Fatal(err)
	}
	if err = handle.Close(); err != nil {
		t.Fatal("repeated close failed", err)
	}
	if err = handle.Wait(t.Context()); !errors.Is(err, os.ErrClosed) {
		t.Fatal("wait accepted a closed descriptor", err)
	}
	if err = handle.Signal(unix.SIGTERM); !errors.Is(err, os.ErrClosed) {
		t.Fatal("signal accepted a closed descriptor", err)
	}
	if _, err = Open(Identity{}); err == nil {
		t.Fatal("invalid persisted identity opened a monitor")
	}
}
