package session

import (
	"context"
	"errors"
	"net"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

func observeTUN(name string) (exists, ready bool, err error) {
	interfaces, err := net.Interfaces()
	if err != nil {
		return false, false, err
	}
	var index int
	for _, device := range interfaces {
		if device.Name == name {
			exists, index = true, device.Index
			if device.Flags&net.FlagUp == 0 {
				return exists, false, nil
			}
			break
		}
	}
	if !exists {
		return false, false, nil
	}
	var table *windows.MibIpForwardTable2
	if err = windows.GetIpForwardTable2(windows.AF_UNSPEC, &table); err != nil {
		return exists, false, err
	}
	defer windows.FreeMibTable(unsafe.Pointer(table))
	var ipv4, ipv6 bool
	for _, row := range table.Rows() {
		if int(row.InterfaceIndex) != index || row.ValidLifetime == 0 {
			continue
		}
		// A route broad enough to capture public traffic must actually exist,
		// rather than only an adapter and its local subnet.
		if row.DestinationPrefix.PrefixLength <= 1 {
			ipv4 = ipv4 || row.DestinationPrefix.Prefix.Family == windows.AF_INET
			ipv6 = ipv6 || row.DestinationPrefix.Prefix.Family == windows.AF_INET6
		}
	}
	return exists, ipv4 && ipv6, nil
}

func waitTUN(ctx context.Context, name string, enabled bool) error {
	deadline := time.NewTimer(4 * time.Second)
	defer deadline.Stop()
	ticker := time.NewTicker(75 * time.Millisecond)
	defer ticker.Stop()
	for {
		exists, ready, err := observeTUN(name)
		if err != nil {
			return err
		}
		if enabled && ready || !enabled && !exists {
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-deadline.C:
			return errors.New("TUN observation timed out")
		case <-ticker.C:
		}
	}
}
