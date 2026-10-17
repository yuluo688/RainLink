package mobile

import (
	"errors"

	"golang.org/x/sys/unix"
)

// Read back the interface owned by the actual descriptor, rather than returning
// the compiler's requested name (Android assigns its own tun number).
func observedTunnelName(fd int32) (string, error) {
	request, err := unix.NewIfreq("")
	if err == nil {
		err = unix.IoctlIfreq(int(fd), unix.TUNGETIFF, request)
	}
	if err != nil || request.Name() == "" {
		return "", errors.New("无法确认系统隧道接口")
	}
	return request.Name(), nil
}
