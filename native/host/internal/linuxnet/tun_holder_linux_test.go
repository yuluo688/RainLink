//go:build linux && !android

package linuxnet

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"testing"

	"golang.org/x/sys/unix"
)

// A persistent TUN with no attached FD eventually reports NO-CARRIER. Keep a
// real queue attached for ordinary-user readiness observations instead of
// relying on the short UNKNOWN transition after `ip link set up`.
func TestIsolatedTUNFixtureHolder(t *testing.T) {
	if os.Geteuid() != 0 || os.Getenv("RAINLINK_TEST_TUN_HOLDER") != "isolated" {
		t.Skip("fixture holder subprocess only")
	}
	requireNetworkFixture(t)
	fd, err := unix.Open("/dev/net/tun", unix.O_RDWR|unix.O_CLOEXEC, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer unix.Close(fd)
	request, err := unix.NewIfreq("rl-fixture")
	if err != nil {
		t.Fatal(err)
	}
	request.SetUint16(unix.IFF_TUN | unix.IFF_NO_PI)
	if err = unix.IoctlIfreq(fd, unix.TUNSETIFF, request); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := signal.NotifyContext(t.Context(), syscall.SIGTERM)
	defer cancel()
	fmt.Println("TUN fixture attached")
	<-ctx.Done()
}
