//go:build linux && !android

package linuxprocess

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"testing"

	"golang.org/x/sys/unix"
)

func statFixture(state, start string) []byte {
	fields := []string{state}
	for range 18 {
		fields = append(fields, "0")
	}
	fields = append(fields, start, "4096", "2")
	return []byte("123 (a name with ) and ) spaces) " + strings.Join(fields, " "))
}

func TestProcessDisappearingDuringProcReadRetainsUncertainErrors(t *testing.T) {
	for _, errno := range []error{unix.ENOENT, unix.ESRCH, unix.EACCES, unix.EIO} {
		t.Run("stat/"+errno.Error(), func(t *testing.T) {
			failure := &os.PathError{Op: "read", Path: "/proc/123/stat", Err: errno}
			identity, alive, err := readIdentity(123, func(path string) ([]byte, error) {
				if path != "/proc/123/stat" {
					t.Fatal("failed stat read unexpectedly continued to boot identity", path)
				}
				return nil, failure
			})
			if alive || identity != (Identity{}) {
				t.Fatal("failed process read produced a live identity")
			}
			if errno == unix.ENOENT || errno == unix.ESRCH {
				if err != nil {
					t.Fatal("a kernel-reported vanished process blocked recovery", err)
				}
			} else if !errors.Is(err, errno) {
				t.Fatal("an uncertain process read authorized recovery", err)
			}
		})
		t.Run("boot/"+errno.Error(), func(t *testing.T) {
			_, alive, err := readIdentity(123, func(path string) ([]byte, error) {
				if path == "/proc/123/stat" {
					return statFixture("S", "12345"), nil
				}
				if path != "/proc/sys/kernel/random/boot_id" {
					t.Fatal("unexpected identity path", path)
				}
				return nil, &os.PathError{Op: "read", Path: path, Err: errno}
			})
			if alive || !errors.Is(err, errno) {
				t.Fatal("boot identity failure was treated as process exit", err)
			}
		})
	}
}

func TestProcessStatIdentityAndExitedStates(t *testing.T) {
	start, alive, err := parseStart(statFixture("S", "987654"))
	if err != nil || !alive || start != 987654 {
		t.Fatal("comm changed the start-time field", start, alive, err)
	}
	for _, state := range []string{"Z", "X"} {
		if _, alive, err = parseStart(statFixture(state, "987654")); err != nil || alive {
			t.Fatal("an exited process was treated as alive", state, err)
		}
	}
	for _, data := range [][]byte{nil, []byte("123 (missing) S"), statFixture("S", "0"), statFixture("S", "-1"), statFixture("S", "oops")} {
		if _, _, err = parseStart(data); err == nil {
			t.Fatal("invalid stat was treated as a dead process", string(data))
		}
	}
}

func TestProcessIdentitySeparatesLiveChildExitAndPIDReuse(t *testing.T) {
	self, alive, err := ReadIdentity(os.Getpid())
	if err != nil || !alive || !self.Valid() {
		t.Fatal("self identity unavailable", err)
	}
	if alive, err = Alive(self); err != nil || !alive {
		t.Fatal("live identity rejected", err)
	}
	reused := self
	reused.Start++
	if alive, err = Alive(reused); err != nil || alive {
		t.Fatal("PID reuse matched a different start time", err)
	}
	otherBoot := self
	otherBoot.Boot = "00000000-0000-0000-0000-000000000001"
	if alive, err = Alive(otherBoot); err != nil || alive {
		t.Fatal("identity from another boot matched", err)
	}
	child := exec.Command("/bin/sleep", "30")
	if err = child.Start(); err != nil {
		t.Fatal(err)
	}
	reaped := false
	t.Cleanup(func() {
		if !reaped {
			_ = child.Process.Kill()
			_ = child.Wait()
		}
	})
	identity, alive, err := ReadIdentity(child.Process.Pid)
	if err != nil || !alive {
		t.Fatal("child identity unavailable", err)
	}
	if err = child.Process.Kill(); err != nil {
		t.Fatal(err)
	}
	_ = child.Wait()
	reaped = true
	if alive, err = Alive(identity); err != nil || alive {
		t.Fatal("exited child retained a live identity", err)
	}
	if _, _, err = ReadIdentity(0); err == nil {
		t.Fatal("invalid PID accepted")
	}
	if _, err = Alive(Identity{}); err == nil {
		t.Fatal("malformed persisted identity authorized recovery")
	}
}

func TestProcessNamespaceAndPersistedIdentityValidation(t *testing.T) {
	namespace, err := NetworkNamespace(os.Getpid())
	if err != nil || !ValidNamespace(namespace) {
		t.Fatal("self namespace unavailable", err)
	}
	value, err := os.Readlink("/proc/" + strconv.Itoa(os.Getpid()) + "/ns/net")
	if err != nil || value != namespace {
		t.Fatal("namespace differs from the kernel", err)
	}
	for _, invalid := range []string{"", "net:[0]", "net:[-1]", "net:[x]", "mnt:[123]", "net:[123]junk"} {
		if ValidNamespace(invalid) {
			t.Fatal("invalid namespace accepted", invalid)
		}
	}
	valid := Identity{PID: 1, Start: 1, Boot: "01234567-89ab-cdef-0123-456789abcdef"}
	if !valid.Valid() {
		t.Fatal("valid identity rejected")
	}
	for _, invalid := range []Identity{{}, {PID: 1, Start: 0, Boot: valid.Boot}, {PID: 1, Start: 1, Boot: strings.ToUpper(valid.Boot)}, {PID: 1, Start: 1, Boot: fmt.Sprint(1)}} {
		if invalid.Valid() {
			t.Fatal("invalid identity accepted")
		}
	}
}
