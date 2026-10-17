//go:build !linux || android

package session

// These platforms collect logs directly, without a root-to-host forwarding
// queue. Their clear operation needs only the local cursor.
func logClockTick() (int64, error) { return 0, nil }
