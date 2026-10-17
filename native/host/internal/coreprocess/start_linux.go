//go:build linux && !android

package coreprocess

import (
	"os/exec"
	"runtime"
	"sync"
	"syscall"
)

func startOwned(command *exec.Cmd) (func(), error) {
	started := make(chan error, 1)
	finished := make(chan struct{})
	go func() {
		// Linux ties Pdeathsig to the creating thread. Keep that thread alive until
		// Wait has reaped the core; a recycled Go worker must not kill a live core.
		runtime.LockOSThread()
		defer runtime.UnlockOSThread()
		command.SysProcAttr = &syscall.SysProcAttr{Pdeathsig: syscall.SIGKILL}
		err := command.Start()
		started <- err
		if err == nil {
			<-finished
		}
	}()
	if err := <-started; err != nil {
		return nil, err
	}
	var once sync.Once
	return func() { once.Do(func() { close(finished) }) }, nil
}
