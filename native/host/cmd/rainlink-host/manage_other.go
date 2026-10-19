//go:build !linux || android

package main

import "errors"

func manageTUNService(bool, string) error {
	return errors.New("service management is available on Linux only")
}
