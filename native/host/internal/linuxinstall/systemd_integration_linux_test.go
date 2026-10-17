//go:build linux && !android

package linuxinstall

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"

	"rainlink.local/host/internal/linuxipc"
	"rainlink.local/host/internal/linuxtun"
	"rainlink.local/host/internal/privatefs"
)

// Must run in a disposable VM: this test installs into fixed system paths.
func TestRealSystemdInstallation(t *testing.T) {
	if os.Getenv("RAINLINK_TEST_REAL_SYSTEMD") != "disposable-vm" {
		t.Skip("requires disposable systemd VM")
	}
	if os.Geteuid() != 0 || fixtureEnabled() {
		t.Fatal("requires real systemd without fixture tools")
	}
	if data, err := os.ReadFile("/proc/1/comm"); err != nil || strings.TrimSpace(string(data)) != "systemd" {
		t.Fatal("PID 1 is not systemd", err)
	}
	service := systemServices{}
	if err := service.preflight(t.Context(), true); err != nil {
		t.Fatal(err)
	}
	host := filepath.Join(filepath.Dir(os.Args[0]), "rainlink-host")
	run := func(action string, wantOK bool) {
		t.Helper()
		ctx, cancel := context.WithTimeout(t.Context(), operationTimeout+10*time.Second)
		defer cancel()
		data, err := exec.CommandContext(ctx, host, action).CombinedOutput()
		if (err == nil) != wantOK {
			t.Fatalf("%s success=%v: %s", action, err == nil, data)
		}
		t.Logf("%s success=%v", action, err == nil)
	}
	if state, err := service.state(t.Context()); err != nil || state.Present {
		data, queryErr := systemctl(t.Context(), "show", socketUnit, "--all", "--no-pager", "--property=LoadState,ActiveState,UnitFileState,FragmentPath,DropInPaths")
		t.Logf("raw fixed socket state=%q error=%v", data, queryErr)
		t.Fatal("VM already has service", state, err)
	}
	run("install-tun", true)
	if err := service.ready(t.Context()); err != nil {
		t.Fatal(err)
	}
	t.Log("real systemd accepted installed socket/template, served authenticated idle protocol, no polkit request")
	controller, err := linuxtun.New()
	if err != nil {
		t.Fatal(err)
	}
	lease, err := controller.Acquire(t.Context(), "rl-install-qa")
	if err != nil {
		t.Fatal(err)
	}
	defer lease.Close()
	// A different active lease must leave probe service exits successful and its
	// journal intact. This acquires no TUN and makes no network modifications.
	if err := service.ready(t.Context()); err == nil {
		t.Fatal("active lease was reported idle")
	}
	time.Sleep(700 * time.Millisecond)
	failed, err := systemctl(t.Context(), "list-units", "--state=failed", "--no-legend", "--plain", "--no-pager", "rainlink-tun@*.service")
	if err != nil || len(strings.TrimSpace(string(failed))) != 0 {
		t.Fatal("idle probe/exit hook became failed while another lease is active", string(failed), err)
	}
	if err := controller.ConfirmIdle(t.Context()); !errors.Is(err, linuxtun.ErrOwned) {
		t.Fatal("probe disturbed active lease", err)
	}
	if err := lease.Restore(t.Context()); err != nil {
		t.Fatal(err)
	}
	if err := lease.Close(); err != nil {
		t.Fatal(err)
	}
	if err := service.ready(t.Context()); err != nil {
		t.Fatal(err)
	}
	t.Log("real systemd exit hook preserved another live lease without falsely confirming idle")
	run("install-tun", true)
	if err := service.quiesce(t.Context()); err != nil {
		t.Fatal(err)
	}
	if err := service.enable(t.Context(), false); err != nil {
		t.Fatal(err)
	}
	run("install-tun", true)
	if state, err := service.state(t.Context()); err != nil || state != (serviceState{Present: true}) {
		t.Fatal("disabled state lost", state, err)
	}
	t.Log("real systemd repeated upgrade preserved disabled socket")
	// Administrator drop-ins are refused before stopping or replacing files.
	dropDir := "/etc/systemd/system/rainlink-tun.socket.d"
	if err := os.MkdirAll(dropDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dropDir, "qa.conf"), []byte("[Socket]\nMaxConnections=3\n"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := service.reload(t.Context()); err != nil {
		t.Fatal(err)
	}
	run("install-tun", false)
	if err := os.Remove(filepath.Join(dropDir, "qa.conf")); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(dropDir); err != nil {
		t.Fatal(err)
	}
	if err := service.reload(t.Context()); err != nil {
		t.Fatal(err)
	}
	command := exec.Command(host, "install-tun")
	command.SysProcAttr = &syscall.SysProcAttr{Credential: &syscall.Credential{Uid: 65534, Gid: 65534}}
	if data, err := command.CombinedOutput(); err == nil || !strings.Contains(string(data), "requires an administrator") {
		t.Fatal("ordinary user could install", err, string(data))
	}
	t.Log("administrator overrides and ordinary-user installation correctly refused")
	if err := service.enable(t.Context(), true); err != nil {
		t.Fatal(err)
	}
	if err := service.start(t.Context()); err != nil {
		t.Fatal(err)
	}
	if err := service.ready(t.Context()); err != nil {
		t.Fatal(err)
	}
	// Stall this actual root executable with a private test-only file lock by
	// holding a real live capture lease. The installer must not replace files.
	lease, err = controller.Acquire(t.Context(), "rl-install-qa")
	if err != nil {
		t.Fatal(err)
	}
	stateDirectory, err := privatefs.Open(statePath)
	if err != nil {
		t.Fatal(err)
	}
	defer stateDirectory.Close()
	manifestBefore, err := readManifest(stateDirectory)
	if err != nil {
		t.Fatal(err)
	}
	run("install-tun", false)
	manifestAfter, err := readManifest(stateDirectory)
	if err != nil || *manifestBefore != *manifestAfter {
		t.Fatal("unconfirmed capture changed installation", err)
	}
	if err := lease.Restore(t.Context()); err != nil {
		t.Fatal(err)
	}
	if err := lease.Close(); err != nil {
		t.Fatal(err)
	}
	run("recover-tun-install", true)
	if err := service.ready(t.Context()); err != nil {
		t.Fatal(err)
	}
	t.Log("active capture refused replacement; explicit recovery restored original service")
	// Real transport root checks are exercised separately from polkit prompts.
	if executable, err := linuxipc.OpenRootExecutable("/usr/bin/pkcheck"); err != nil {
		t.Fatal(err)
	} else if err = executable.Close(); err != nil {
		t.Fatal(err)
	}
	run("uninstall-tun", true)
	if state, err := service.state(t.Context()); err != nil || state.Present || state.Active || state.Enabled {
		t.Fatal("service remained installed", state, err)
	}
	run("recover-tun-install", true)
	if data, err := systemctl(t.Context(), "list-units", "--state=active,activating,deactivating", "--no-legend", "--plain", "--no-pager", "rainlink-tun@*.service"); err != nil || len(strings.TrimSpace(string(data))) != 0 {
		t.Fatal("permission sessions remained", string(data), err)
	}
	t.Log("real systemd uninstall and recovery completed; no capture/session remains")
}
