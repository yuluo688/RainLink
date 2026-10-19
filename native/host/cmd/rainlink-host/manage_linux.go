//go:build linux && !android

package main

import (
	"context"
	"os"
	"os/signal"
	"syscall"

	"rainlink.local/host/internal/linuxmanage"
)

func manageTUNService(elevated bool, method string) error {
	if elevated {
		return linuxmanage.RunElevated(method, os.Stdin, os.Stdout)
	}
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer cancel()
	return linuxmanage.Serve(ctx, os.Stdin, os.Stdout)
}
