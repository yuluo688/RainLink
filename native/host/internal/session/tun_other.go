//go:build !windows

package session

import (
	"context"
	"errors"
)

func waitTUN(context.Context, string, bool) error {
	return errors.New("TUN observation is unavailable")
}
func observeTUN(string) (bool, bool, error) {
	return false, false, errors.New("TUN observation is unavailable")
}
