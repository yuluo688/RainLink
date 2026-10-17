//go:build !linux || android

package main

import "errors"

func runTUNService() error         { return errors.New("Linux TUN permission service is unavailable") }
func recoverTUNService(bool) error { return errors.New("Linux TUN recovery is unavailable") }
