//go:build !windows

package coreprocess

import (
	"context"
	"errors"
	"io"
	"os/exec"
)

func hideWindow(command *exec.Cmd)                 {}
func ownProcess(command *exec.Cmd) (func(), error) { return func() {}, nil }
func startElevated(context.Context, string, []byte, io.Writer, io.Writer) (Process, error) {
	return nil, errors.New("TUN is unavailable on this platform")
}

// RunElevated is available only on Windows.
func RunElevated(string, int) error { return errors.New("Windows elevation is unavailable") }
