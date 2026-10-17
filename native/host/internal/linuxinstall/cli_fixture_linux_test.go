//go:build linux && !android

package linuxinstall

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"rainlink.local/host/internal/privatefs"
)

const fixtureMarker = "/run/rainlink-install-e2e-enabled"
const fixtureStatePath = "/run/rainlink-install-e2e-state.json"

type fixtureServiceState struct {
	Enabled bool
	Active  bool
	PID     int
}

func readFixtureService() fixtureServiceState {
	var state fixtureServiceState
	if data, err := os.ReadFile(fixtureStatePath); err == nil {
		_ = json.Unmarshal(data, &state)
	}
	return state
}

func fixtureEnabled() bool { _, err := os.Stat(fixtureMarker); return err == nil }

// Invoked only by the root-owned systemctl script in a disposable chroot.
// This fixture exercises the real installer CLI and Unix protocol, not systemd.
func TestSystemctlFixtureCommand(t *testing.T) {
	if !fixtureEnabled() {
		return
	}
	var args []string
	for index, arg := range os.Args {
		if arg == "--" {
			args = os.Args[index+1:]
			break
		}
	}
	if len(args) == 0 {
		return
	}
	state := readFixtureService()
	exit := func(err error) {
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		os.Exit(0)
	}
	save := func() {
		data, err := json.Marshal(state)
		if err == nil {
			err = os.WriteFile(fixtureStatePath, data, 0600)
		}
		exit(err)
	}
	switch args[0] {
	case "show":
		if len(args) > 1 && args[1] == "--property=Version" {
			fmt.Println("Version=fixture-only")
			exit(nil)
		}
		if len(args) < 2 {
			exit(errors.New("missing fixture unit"))
		}
		unit := args[1]
		if unit != socketUnit && unit != templateUnit && unit != templateProbeUnit {
			exit(errors.New("unexpected fixture unit"))
		}
		fragmentUnit := unit
		if validInstance(unit) {
			fragmentUnit = templateUnit
		}
		_, err := os.Stat("/usr/lib/systemd/system/" + fragmentUnit)
		load, fragment, enable, active := "not-found", "", "", "inactive"
		if err == nil {
			load = "loaded"
			fragment = "/usr/lib/systemd/system/" + fragmentUnit
			enable = "disabled"
			if state.Enabled {
				enable = "enabled"
			}
			if fragmentUnit == templateUnit {
				enable = "static"
			}
		}
		if unit == socketUnit && state.Active {
			active = "active"
		}
		fmt.Printf("LoadState=%s\nActiveState=%s\nUnitFileState=%s\nFragmentPath=%s\nDropInPaths=\n", load, active, enable, fragment)
		exit(nil)
	case "daemon-reload", "list-units":
		exit(nil)
	case "enable":
		state.Enabled = true
		save()
	case "disable":
		state.Enabled = false
		save()
	case "start":
		if !state.Active {
			log, err := os.OpenFile("/run/rainlink-activation-fixture.log", os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
			if err != nil {
				exit(err)
			}
			child := exec.Command("/qa/linuxinstall.test", "-test.run=^TestSocketActivationFixture$")
			child.Stdout, child.Stderr = log, log
			child.Env = []string{"PATH=/usr/bin:/bin", "RAINLINK_TEST_ACTIVATOR=1"}
			if err = child.Start(); err != nil {
				_ = log.Close()
				exit(err)
			}
			state.PID = child.Process.Pid
			_ = child.Process.Release()
			_ = log.Close()
			deadline := time.Now().Add(3 * time.Second)
			for time.Now().Before(deadline) {
				if _, err = os.Stat("/run/rainlink/tun.sock"); err == nil {
					state.Active = true
					break
				}
				time.Sleep(10 * time.Millisecond)
			}
			if !state.Active {
				_ = syscall.Kill(state.PID, syscall.SIGKILL)
				exit(errors.New("fixture socket not ready"))
			}
		}
		save()
	case "stop":
		if state.Active && state.PID > 1 {
			if err := syscall.Kill(state.PID, syscall.SIGTERM); err != nil && !errors.Is(err, syscall.ESRCH) {
				exit(err)
			}
			deadline := time.Now().Add(4 * time.Second)
			stopped := false
			for time.Now().Before(deadline) {
				data, err := os.ReadFile(fmt.Sprintf("/proc/%d/stat", state.PID))
				if errors.Is(err, os.ErrNotExist) || strings.Contains(string(data), ") Z ") {
					stopped = true
					break
				}
				time.Sleep(10 * time.Millisecond)
			}
			if !stopped {
				exit(errors.New("fixture activator did not stop"))
			}
		}
		state.Active = false
		state.PID = 0
		save()
	default:
		exit(errors.New("unsupported fixture systemctl operation"))
	}
}

func TestSocketActivationFixture(t *testing.T) {
	if !fixtureEnabled() || os.Getenv("RAINLINK_TEST_ACTIVATOR") != "1" {
		return
	}
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer cancel()
	if err := os.MkdirAll("/run/rainlink", 0755); err != nil {
		t.Fatal(err)
	}
	listener, err := net.ListenUnix("unix", &net.UnixAddr{Name: "/run/rainlink/tun.sock", Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	if err = os.Chmod("/run/rainlink/tun.sock", 0666); err != nil {
		_ = listener.Close()
		t.Fatal(err)
	}
	stop := context.AfterFunc(ctx, func() { _ = listener.Close() })
	defer stop()
	var children sync.WaitGroup
	defer children.Wait()
	for {
		connection, err := listener.AcceptUnix()
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			t.Fatal(err)
		}
		file, err := connection.File()
		_ = connection.Close()
		if err != nil {
			t.Fatal(err)
		}
		command := exec.CommandContext(ctx, "/usr/libexec/rainlink/rainlink-host", "serve-tun")
		command.Stdin = file
		command.Stdout = io.Discard
		command.Stderr = os.Stderr
		command.Env = []string{"PATH=/usr/bin:/bin"}
		if err = command.Start(); err != nil {
			_ = file.Close()
			t.Fatal(err)
		}
		_ = file.Close()
		children.Add(1)
		go func() {
			defer children.Done()
			if err := command.Wait(); err != nil && ctx.Err() == nil {
				fmt.Fprintln(os.Stderr, "fixture guardian failed:", err)
			}
			post := exec.Command("/usr/libexec/rainlink/rainlink-host", "recover-tun-service")
			if err := post.Run(); err != nil {
				fmt.Fprintln(os.Stderr, "fixture exit hook failed:", err)
			}
		}()
	}
}

func TestInstalledCLIWithLockedCoreAndLiveIdleProtocol(t *testing.T) {
	if !fixtureEnabled() {
		t.Skip("requires disposable chroot with explicit fixture systemctl")
	}
	run := func(action string, wantOK bool) {
		t.Helper()
		ctx, cancel := context.WithTimeout(t.Context(), 20*time.Second)
		defer cancel()
		command := exec.CommandContext(ctx, "/qa/rainlink-host", action)
		data, err := command.CombinedOutput()
		if (err == nil) != wantOK {
			t.Fatalf("%s success=%v: %s", action, err == nil, data)
		}
	}
	defer func() { _, _ = systemctl(context.Background(), "stop", socketUnit) }()
	run("install-tun", true)
	state, err := (systemServices{}).state(t.Context())
	if err != nil || state != (serviceState{Present: true, Enabled: true, Active: true}) {
		t.Fatal(state, err)
	}
	directory, err := privatefs.Open(statePath)
	if err != nil {
		t.Fatal(err)
	}
	defer directory.Close()
	before, err := readManifest(directory)
	if err != nil || before == nil {
		t.Fatal(err)
	}
	for index, value := range targets {
		info, err := os.Lstat(value.path)
		if err != nil || uint32(info.Mode().Perm()) != value.mode || info.Sys().(*syscall.Stat_t).Uid != 0 {
			t.Fatal("bad installed metadata", index, err)
		}
	}
	sentinel := "/usr/libexec/rainlink/administrator-file"
	if err = os.WriteFile(sentinel, []byte("retain"), 0644); err != nil {
		t.Fatal(err)
	}
	// Repeat install validates source pinning, backups, stop/readiness and commit.
	run("install-tun", true)
	if _, err = systemctl(t.Context(), "stop", socketUnit); err != nil {
		t.Fatal(err)
	}
	if _, err = systemctl(t.Context(), "disable", socketUnit); err != nil {
		t.Fatal(err)
	}
	run("install-tun", true)
	state, err = (systemServices{}).state(t.Context())
	if err != nil || state != (serviceState{Present: true}) {
		t.Fatal("upgrade changed disabled state", state, err)
	}
	core, err := os.ReadFile("/qa/sing-box")
	if err != nil {
		t.Fatal(err)
	}
	badCore := append([]byte(nil), core...)
	badCore[len(badCore)/2] ^= 1
	if err = os.WriteFile("/qa/sing-box", badCore, 0755); err != nil {
		t.Fatal(err)
	}
	run("install-tun", false)
	if err = os.WriteFile("/qa/sing-box", core, 0755); err != nil {
		t.Fatal(err)
	}
	after, err := readManifest(directory)
	if err != nil || *after != *before {
		t.Fatal("bad source changed installed manifest", err)
	}
	command := exec.Command("/qa/rainlink-host", "install-tun")
	command.SysProcAttr = &syscall.SysProcAttr{Credential: &syscall.Credential{Uid: 65534, Gid: 65534}}
	if data, err := command.CombinedOutput(); err == nil || !strings.Contains(string(data), "requires an administrator") {
		t.Fatal("ordinary user could install", err, string(data))
	}
	run("uninstall-tun", true)
	for _, value := range targets {
		if _, err = os.Stat(value.path); !errors.Is(err, os.ErrNotExist) {
			t.Fatal("managed file retained", value.path, err)
		}
	}
	if _, err = readManifest(directory); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(sentinel)
	if err != nil || string(data) != "retain" {
		t.Fatal("unmanaged data changed", err)
	}
	run("recover-tun-install", true)
	run("uninstall-tun", true)
	entries, err := os.ReadDir(statePath)
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range entries {
		if entry.Name() != "install.lock" {
			t.Fatal("unfinished installer file", entry.Name())
		}
	}
	if log, err := os.ReadFile("/run/rainlink-activation-fixture.log"); err != nil || strings.Contains(string(log), "failed") {
		t.Fatal("fixture activation/exit error", string(log), err)
	}
	if filepath.Dir(os.Args[0]) != "/qa" {
		t.Fatal("fixture ran outside explicit chroot")
	}
}
