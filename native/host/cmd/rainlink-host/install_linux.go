//go:build linux && !android

package main

import (
	"context"
	"os/signal"
	"syscall"

	"rainlink.local/host/internal/linuxinstall"
)

func manageTUNInstallation(action string) error {
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer cancel()
	return linuxinstall.Run(ctx, action)
}
