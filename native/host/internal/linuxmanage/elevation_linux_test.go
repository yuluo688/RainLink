//go:build linux && !android

package linuxmanage

import (
	"context"
	"errors"
	"io"
	"os"
	"os/exec"
	"syscall"
	"testing"
	"time"
)

func TestCancellationStopsAuthorizationWithoutAStdinReader(t *testing.T) {
	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()
	input, control, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer input.Close()
	defer control.Close()
	command := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestPendingAuthorizationFixture$")
	command.Env = []string{"RAINLINK_TEST_PENDING_AUTHORIZATION=1"}
	command.Stdin = input
	ready, err := command.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	command.Cancel = func() error { return cancelElevation(control, command.Process) }
	command.WaitDelay = 2 * time.Second
	if err = command.Start(); err != nil {
		t.Fatal(err)
	}
	var marker [1]byte
	if _, err = io.ReadFull(ready, marker[:]); err != nil || marker[0] != 'R' {
		cancel()
		_ = command.Wait()
		t.Fatal("authorization fixture did not start", err)
	}
	cancel()
	var exit *exec.ExitError
	if err = command.Wait(); !errors.As(err, &exit) || exit.Success() {
		t.Fatal("pending authorization survived cancellation", err)
	}
	if status, ok := exit.Sys().(syscall.WaitStatus); !ok || !status.Signaled() || status.Signal() != syscall.SIGTERM {
		t.Fatal("authorization required forced termination instead of prompt cancellation", exit.Sys())
	}
	if err = cancelElevation(control, command.Process); err != nil {
		t.Fatal("repeated cancellation after exit should be harmless", err)
	}
}

func TestPendingAuthorizationFixture(t *testing.T) {
	if os.Getenv("RAINLINK_TEST_PENDING_AUTHORIZATION") != "1" {
		t.Skip("subprocess fixture")
	}
	if _, err := os.Stdout.Write([]byte{'R'}); err != nil {
		t.Fatal(err)
	}
	// Model an authentication process that never reads the revocation pipe.
	// An EOF-only cancellation would leave it alive for this full duration.
	timer := time.NewTimer(30 * time.Second)
	defer timer.Stop()
	<-timer.C
	t.Fatal("pending authorization was not stopped")
}
