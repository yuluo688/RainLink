//go:build !linux || android

package coreprocess

import "os/exec"

func startOwned(command *exec.Cmd) (func(), error) {
	if err := command.Start(); err != nil {
		return nil, err
	}
	cleanup, err := ownProcess(command)
	if err != nil {
		_ = command.Process.Kill()
		_ = command.Wait()
		return nil, err
	}
	return cleanup, nil
}
