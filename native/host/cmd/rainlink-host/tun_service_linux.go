//go:build linux && !android

package main

import (
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"os/signal"
	"syscall"

	"rainlink.local/host/internal/linuxtun"
	"rainlink.local/host/internal/session"
)

func runTUNService() error {
	connection, err := net.FileConn(os.Stdin)
	if err != nil {
		return err
	}
	stream, ok := connection.(*net.UnixConn)
	if !ok {
		_ = connection.Close()
		return errors.New("permission service requires a Unix socket")
	}
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer cancel()
	return session.ServeLinuxTUN(ctx, stream)
}

func recoverTUNService(afterExit bool) error {
	controller, err := linuxtun.New()
	if err != nil {
		return err
	}
	if afterExit {
		skipped, err := controller.RecoverAfterServiceExit(context.Background())
		if skipped && err == nil {
			fmt.Fprintln(os.Stderr, "TUN exit cleanup skipped: another session remains active")
		}
		return err
	}
	return controller.Recover(context.Background())
}
