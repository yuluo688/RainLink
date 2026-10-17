//go:build linux && !android

package coreprocess

import (
	"context"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestLinuxCoreCannotOutliveKilledHost(t *testing.T) {
	if path := os.Getenv("RAINLINK_CORE_LIFETIME_HELPER"); path != "" {
		process, err := Start(t.Context(), path, []byte("{}"), io.Discard, io.Discard, false)
		if err != nil {
			t.Fatal(err)
		}
		defer process.Close()
		time.Sleep(30 * time.Second)
		_ = process.Kill()
		_ = process.Wait()
		return
	}
	dir := t.TempDir()
	pidFile := filepath.Join(dir, "core.pid")
	fixture := filepath.Join(dir, "core")
	if err := os.WriteFile(fixture, []byte("#!/bin/sh\ncat >/dev/null\necho $$ > \"$RAINLINK_CORE_PID_FILE\"\nexec sleep 30\n"), 0700); err != nil {
		t.Fatal(err)
	}
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, executable, "-test.run=^TestLinuxCoreCannotOutliveKilledHost$", "-test.timeout=10s")
	command.Env = append(os.Environ(), "RAINLINK_CORE_LIFETIME_HELPER="+fixture, "RAINLINK_CORE_PID_FILE="+pidFile)
	if err := command.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { _ = command.Process.Kill() }()
	var pid int
	for ctx.Err() == nil {
		data, err := os.ReadFile(pidFile)
		if err == nil {
			pid, err = strconv.Atoi(strings.TrimSpace(string(data)))
			if err == nil && pid > 1 {
				break
			}
		}
		time.Sleep(10 * time.Millisecond)
	}
	if pid < 2 {
		_ = command.Wait()
		t.Fatal("fixture core never started")
	}
	defer syscall.Kill(pid, syscall.SIGKILL)
	if err := command.Process.Kill(); err != nil {
		t.Fatal(err)
	}
	_ = command.Wait()
	for ctx.Err() == nil {
		if errors.Is(syscall.Kill(pid, 0), syscall.ESRCH) {
			return
		}
		// PID 1 may briefly keep a reparented zombie; it cannot serve traffic.
		if data, err := os.ReadFile("/proc/" + strconv.Itoa(pid) + "/stat"); err == nil {
			if _, state, ok := strings.Cut(string(data), ") "); ok && strings.HasPrefix(state, "Z ") {
				return
			}
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("network core remained alive after its host was killed")
}
