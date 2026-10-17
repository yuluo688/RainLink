//go:build !linux || android

package main

import "errors"

func runTUNWatcher([]string) error { return errors.New("Linux TUN watchdog is unavailable") }
