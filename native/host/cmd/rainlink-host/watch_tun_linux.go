//go:build linux && !android

package main

import (
	"context"
	"os"
	"strconv"

	"golang.org/x/sys/unix"
	"rainlink.local/host/internal/linuxprocess"
	"rainlink.local/host/internal/linuxtun"
)

func runTUNWatcher(arguments []string) error {
	pid, err := strconv.Atoi(arguments[0])
	if err != nil {
		return err
	}
	start, err := strconv.ParseUint(arguments[1], 10, 64)
	if err != nil {
		return err
	}
	controller, err := linuxtun.New()
	if err != nil {
		return err
	}
	// ExtraFiles arrive in blocking mode. Register the inherited pipe with Go's
	// poller so the readiness write has a real deadline rather than hanging.
	if err = unix.SetNonblock(3, true); err != nil {
		return err
	}
	return controller.WatchOwner(context.Background(), linuxprocess.Identity{PID: pid, Start: start, Boot: arguments[2]},
		os.NewFile(3, "tun-watchdog-ready"))
}
