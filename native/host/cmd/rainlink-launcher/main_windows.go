//go:build windows

// RainLink's entry point has no Flutter/CRT dependency. It remains available
// while the managed runtime is being replaced and recovers before loading it.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"time"

	"rainlink.local/host/internal/update"
)

func run(arguments []string) (runErr error) {
	repair := len(arguments) == 1 && arguments[0] == "--repair"
	if !repair {
		for _, argument := range arguments {
			if argument != "--autostart" {
				return errors.New("unsupported launcher argument")
			}
		}
	}
	executable, err := os.Executable()
	if err != nil {
		return err
	}
	target := filepath.Dir(executable)
	// Rollback starts this launcher just before its helper exits. Wait for the
	// lease rather than racing that exit or treating it as a failed launch.
	deadline := time.Now().Add(10 * time.Second)
	var lease io.Closer
	for {
		lease, err = update.AcquireLock(target)
		if !errors.Is(err, update.ErrInstallationBusy) || time.Now().After(deadline) {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}
	if err != nil {
		return err
	}
	defer func() { runErr = errors.Join(runErr, lease.Close()) }()
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	waitDuration := 10 * time.Second
	if repair {
		waitDuration = time.Second
	}
	waitCtx, cancelWait := context.WithTimeout(ctx, waitDuration)
	defer cancelWait()
	if err := update.WaitForRuntimeExit(waitCtx, target); err != nil {
		return err
	}
	result, recovered, err := update.Recover(ctx, target)
	if err != nil {
		return err
	}
	if repair {
		return json.NewEncoder(os.Stdout).Encode(map[string]any{"recovered": recovered, "outcome": result})
	}
	command := exec.Command(filepath.Join(target, "rainlink-ui.exe"), arguments...)
	command.Dir = target
	command.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x200}
	if err := command.Start(); err != nil {
		return fmt.Errorf("launch desktop: %w", err)
	}
	return command.Process.Release()
}

func main() {
	repair := len(os.Args) == 2 && os.Args[1] == "--repair"
	if !repair && update.ShowExistingWindow() {
		return
	}
	if err := run(os.Args[1:]); err != nil {
		if repair {
			code := "recovery-incomplete"
			if errors.Is(err, update.ErrInstallationBusy) || errors.Is(err, context.DeadlineExceeded) {
				code = "busy"
			}
			json.NewEncoder(os.Stdout).Encode(map[string]any{"recovered": false, "error": code})
		} else if !update.ShowExistingWindow() {
			update.ShowLaunchFailure(false)
		}
		os.Exit(1)
	}
}
