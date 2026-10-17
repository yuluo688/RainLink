//go:build linux && !android

package session

import (
	"errors"

	"golang.org/x/sys/unix"
)

// The same kernel clock stamps root entries and ordinary-host clear barriers.
// Calling it at the mutation itself avoids an approximation near clear.
func logClockTick() (int64, error) {
	var value unix.Timespec
	if err := unix.ClockGettime(unix.CLOCK_MONOTONIC, &value); err != nil {
		return 0, errors.New("permission log clock unavailable")
	}
	return value.Nano(), nil
}
