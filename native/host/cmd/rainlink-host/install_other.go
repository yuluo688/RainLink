//go:build !linux || android

package main

import "errors"

func manageTUNInstallation(string) error {
	return errors.New("TUN service installation is only available on Linux")
}
