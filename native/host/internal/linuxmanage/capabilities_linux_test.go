//go:build linux && !android

package linuxmanage

import (
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"testing"
	"time"

	"golang.org/x/sys/unix"
)

func TestBrokerDropsInheritedCapabilities(t *testing.T) {
	if os.Geteuid() != 0 {
		t.Skip("requires an isolated root test process to grant an ambient capability")
	}
	ctx, cancel := context.WithTimeout(t.Context(), 15*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestBrokerCapabilityFixture$", "-test.v")
	command.Env = []string{"RAINLINK_TEST_BROKER_CAPABILITIES=1"}
	command.SysProcAttr = &syscall.SysProcAttr{
		Credential:  &syscall.Credential{Uid: 65534, Gid: 65534},
		AmbientCaps: []uintptr{unix.CAP_CHOWN},
	}
	if data, err := command.CombinedOutput(); err != nil {
		t.Fatalf("ordinary broker inherited-capability regression: %v\n%s", err, data)
	} else {
		t.Logf("%s", data)
	}
}

func TestBrokerCapabilityFixture(t *testing.T) {
	if os.Getenv("RAINLINK_TEST_BROKER_CAPABILITIES") != "1" {
		t.Skip("ordinary-user subprocess fixture")
	}
	if os.Geteuid() == 0 {
		t.Fatal("capability fixture must run as an ordinary user")
	}
	header := unix.CapUserHeader{Version: unix.LINUX_CAPABILITY_VERSION_3}
	data := [2]unix.CapUserData{}
	if err := unix.Capget(&header, &data[0]); err != nil || data[0].Permitted&1 == 0 {
		t.Fatal("fixture did not inherit CAP_CHOWN", data, err)
	}
	// Keep several OS threads alive while Serve clears the inherited privilege.
	const workers = 4
	ready, release := make(chan struct{}, workers), make(chan struct{})
	defer close(release)
	for range workers {
		go func() {
			runtime.LockOSThread()
			defer runtime.UnlockOSThread()
			ready <- struct{}{}
			<-release
		}()
	}
	for range workers {
		<-ready
	}
	if err := Serve(t.Context(), strings.NewReader(""), io.Discard); err != nil {
		t.Fatal("broker failed after dropping capabilities", err)
	}
	threads, err := filepath.Glob("/proc/self/task/*/status")
	if err != nil || len(threads) < workers {
		t.Fatal("cannot inspect broker threads", threads, err)
	}
	for _, path := range threads {
		status, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		for _, field := range []string{"CapInh", "CapPrm", "CapEff", "CapAmb"} {
			if !strings.Contains(string(status), field+":\t0000000000000000\n") {
				t.Fatal("broker retained capabilities", path, field)
			}
		}
	}
	fmt.Fprintf(os.Stdout, "ordinary broker cleared all capability sets on %d OS threads\n", len(threads))
}
