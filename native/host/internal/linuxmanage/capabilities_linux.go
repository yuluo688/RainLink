//go:build linux && !android

package linuxmanage

import (
	"fmt"
	"os"
	"runtime"
	"syscall"
	"unsafe"

	"golang.org/x/sys/unix"
)

// Desktop sessions can supply ambient capabilities such as CAP_WAKE_ALARM.
// pkexec drops them before resolving /proc/<broker>/exe, so commoncap otherwise
// denies access to that pinned inode. The ordinary broker needs no capabilities;
// apply the drop to every Go thread, including threads created after this call.
func dropBrokerCapabilities() error {
	if os.Geteuid() == 0 {
		return nil
	}
	_, _, errno := syscall.AllThreadsSyscall6(unix.SYS_PRCTL,
		unix.PR_CAP_AMBIENT, unix.PR_CAP_AMBIENT_CLEAR_ALL, 0, 0, 0, 0)
	if errno != 0 {
		return fmt.Errorf("clear service broker ambient capabilities: %w", errno)
	}
	header := unix.CapUserHeader{Version: unix.LINUX_CAPABILITY_VERSION_3}
	data := [2]unix.CapUserData{}
	_, _, errno = syscall.AllThreadsSyscall(unix.SYS_CAPSET,
		uintptr(unsafe.Pointer(&header)), uintptr(unsafe.Pointer(&data[0])), 0)
	runtime.KeepAlive(&header)
	runtime.KeepAlive(&data)
	if errno != 0 {
		return fmt.Errorf("drop service broker capabilities: %w", errno)
	}
	return nil
}
