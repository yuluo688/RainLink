//go:build !windows && (!linux || android)

package session

import (
	"context"
	"errors"
)

// SystemProxyAvailable reports whether this host can verify and restore capture.
func SystemProxyAvailable(context.Context) bool { return false }

func applyProxy(context.Context, string, int) error {
	return errors.New("system proxy is not implemented on this platform")
}
func restoreProxy(string) error { return nil }
func startRecoveryWatcher(context.Context, string) error {
	return errors.New("recovery is not implemented on this platform")
}

// WatchProxy is unavailable on platforms without a system proxy backend.
func WatchProxy(string, int) error {
	return errors.New("recovery is not implemented on this platform")
}
