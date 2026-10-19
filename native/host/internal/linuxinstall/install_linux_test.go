//go:build linux && !android

package linuxinstall

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"reflect"
	"strings"
	"syscall"
	"testing"

	"rainlink.local/host/internal/rootfs"
)

// This driver models service state only; it is not a systemd/polkit acceptance.
type fakeServices struct {
	root            string
	enabled, active bool
	fail            string
	calls           []string
}

func (s *fakeServices) call(name string) error {
	s.calls = append(s.calls, name)
	if s.fail == name {
		s.fail = ""
		return errors.New("fixture service failure")
	}
	return nil
}
func (s *fakeServices) state(context.Context) (serviceState, error) {
	_, err := os.Stat(s.root + targets[2].path)
	return serviceState{Present: err == nil, Enabled: s.enabled, Active: s.active}, s.call("state")
}
func (s *fakeServices) quiesce(context.Context) error { s.active = false; return s.call("stop") }
func (s *fakeServices) enable(_ context.Context, value bool) error {
	s.enabled = value
	return s.call(fmt.Sprint("enable-", value))
}
func (s *fakeServices) reload(context.Context) error { return s.call("reload") }
func (s *fakeServices) start(context.Context) error  { s.active = true; return s.call("start") }
func (s *fakeServices) ready(context.Context) error  { return s.call("ready") }

type fakeCapture struct {
	fail  bool
	calls int
}

func (c *fakeCapture) Recover(context.Context) error {
	c.calls++
	if c.fail {
		return errors.New("fixture network recovery pending")
	}
	return nil
}
func (c *fakeCapture) ConfirmIdle(context.Context) error {
	c.calls++
	if c.fail {
		return errors.New("fixture capture still active")
	}
	return nil
}

func newFixture(t *testing.T) (string, *installer, *fakeServices, *fakeCapture) {
	t.Helper()
	if os.Geteuid() != 0 {
		t.Skip("requires disposable root fixture")
	}
	root, err := os.MkdirTemp("/run", "rainlink-install-test-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := os.RemoveAll(root); err != nil {
			t.Error(err)
		}
	})
	service := &fakeServices{root: root}
	capture := &fakeCapture{}
	i, err := openInstaller(root, service, capture)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := i.close(); err != nil {
			t.Error(err)
		}
	})
	return root, i, service, capture
}

func stageFixture(t *testing.T, i *installer, label string) *manifest {
	t.Helper()
	value := &manifest{Version: 1}
	for index := range targets {
		data := []byte(fmt.Sprintf("synthetic-release-%s-file-%d", label, index))
		if err := i.spool.Replace(t.Context(), stagedName(index, false), bytes.NewReader(data), targets[index].limit, 0600); err != nil {
			t.Fatal(err)
		}
		file, err := i.spool.OpenFile(stagedName(index, false))
		if err != nil {
			t.Fatal(err)
		}
		digest, err := rootfs.Inspect(t.Context(), file, targets[index].limit)
		_ = file.Close()
		if err != nil {
			t.Fatal(err)
		}
		digest.Mode = targets[index].mode
		value.Files[index] = digest
	}
	return value
}

func installFixture(t *testing.T, i *installer, label string) *manifest {
	t.Helper()
	after := stageFixture(t, i, label)
	if err := i.transact(t.Context(), nil, after, serviceState{}); err != nil {
		t.Fatal(err)
	}
	return after
}

func verifyFixture(t *testing.T, i *installer, want *manifest) {
	t.Helper()
	if err := i.verifyFiles(t.Context(), want); err != nil {
		t.Fatal(err)
	}
	actual, err := readManifest(i.state)
	if err != nil || !reflect.DeepEqual(actual, want) {
		t.Fatal("manifest mismatch", actual, err)
	}
	if record, err := i.readTransaction(); err != nil || record != nil {
		t.Fatal("transaction was not retired", err)
	}
	for index := range targets {
		for _, backup := range []bool{true, false} {
			if f, err := i.spool.OpenFile(stagedName(index, backup)); !errors.Is(err, os.ErrNotExist) {
				if f != nil {
					_ = f.Close()
				}
				t.Fatal("staging file was not retired", err)
			}
		}
	}
}

func TestInstallationUpgradeUninstallPreserveUnmanagedData(t *testing.T) {
	root, i, service, _ := newFixture(t)
	sentinel := root + "/usr/libexec/rainlink/administrator-file"
	if err := os.WriteFile(sentinel, []byte("retain"), 0644); err != nil {
		t.Fatal(err)
	}
	old := installFixture(t, i, "old")
	verifyFixture(t, i, old)
	after := stageFixture(t, i, "new")
	if err := i.transact(t.Context(), old, after, serviceState{Present: true, Enabled: true, Active: true}); err != nil {
		t.Fatal(err)
	}
	verifyFixture(t, i, after)
	if err := i.change(t.Context(), false, nil); err != nil {
		t.Fatal(err)
	}
	verifyFixture(t, i, nil)
	if service.active || service.enabled {
		t.Fatal("uninstalled service remained enabled")
	}
	data, err := os.ReadFile(sentinel)
	if err != nil || string(data) != "retain" {
		t.Fatal("unmanaged data changed", err)
	}
}

func TestEveryTransactionFailureRollsBack(t *testing.T) {
	points := []string{"journal", "stopped", "file-0", "file-1", "file-2", "file-3", "file-4", "started", "manifest", "committed"}
	for _, action := range []string{"install", "upgrade", "uninstall"} {
		for _, point := range points {
			t.Run(action+"/"+point, func(t *testing.T) {
				_, i, service, _ := newFixture(t)
				var before, after *manifest
				state := serviceState{}
				if action != "install" {
					before = installFixture(t, i, "old")
					state = serviceState{Present: true, Enabled: true, Active: true}
				}
				if action != "uninstall" {
					after = stageFixture(t, i, "new")
				}
				i.checkpoint = func(name string) error {
					if name == point {
						return errors.New("fixture checkpoint failure")
					}
					return nil
				}
				if err := i.transact(t.Context(), before, after, state); err == nil {
					t.Fatal("failure was reported as success")
				}
				want := before
				if point == "committed" {
					want = after
				}
				verifyFixture(t, i, want)
				wantActive, wantEnabled := state.Active, state.Enabled
				if point == "committed" {
					wantActive = after != nil
					wantEnabled = after != nil
				}
				if service.active != wantActive || service.enabled != wantEnabled {
					t.Fatal("service state not restored", service)
				}
			})
		}
	}
}

func TestCancellationAtEachTransactionBoundary(t *testing.T) {
	points := []string{"journal", "stopped", "file-0", "file-1", "file-2", "file-3", "file-4", "started", "manifest", "committed"}
	for _, action := range []string{"install", "upgrade-enabled", "upgrade-disabled", "uninstall-enabled", "uninstall-disabled"} {
		for _, point := range points {
			t.Run(action+"/"+point, func(t *testing.T) {
				_, i, service, _ := newFixture(t)
				var before, after *manifest
				state := serviceState{}
				if action != "install" {
					before = installFixture(t, i, "old")
					state.Present = true
					state.Enabled = strings.HasSuffix(action, "-enabled")
					state.Active = state.Enabled
					service.enabled, service.active = state.Enabled, state.Active
				}
				if !strings.HasPrefix(action, "uninstall-") {
					after = stageFixture(t, i, "new")
				}
				ctx, cancel := context.WithCancel(t.Context())
				defer cancel()
				reached := false
				i.checkpoint = func(name string) error {
					if name == point {
						reached = true
						cancel()
					}
					return nil
				}
				if err := i.transact(ctx, before, after, state); !errors.Is(err, context.Canceled) {
					t.Fatal("cancellation did not retain its original error", err)
				}
				if !reached {
					t.Fatal("cancellation checkpoint was not reached")
				}
				want, wantEnabled, wantActive := before, state.Enabled, state.Active
				if point == "committed" {
					// The durable commit decides ownership even if cancellation
					// arrives before cleanup; no rollback of committed files.
					want = after
					if after == nil {
						wantEnabled, wantActive = false, false
					} else if before == nil {
						wantEnabled, wantActive = true, true
					}
				}
				verifyFixture(t, i, want)
				if service.enabled != wantEnabled || service.active != wantActive {
					t.Fatal("cancellation changed the confirmed service state", service, wantEnabled, wantActive)
				}
			})
		}
	}
}

func TestServiceFailureAndCancellationRollBack(t *testing.T) {
	for _, operation := range []string{"stop", "enable-false", "reload", "enable-true", "start", "ready", "cancel"} {
		t.Run(operation, func(t *testing.T) {
			_, i, service, _ := newFixture(t)
			before := installFixture(t, i, "old")
			after := stageFixture(t, i, "new")
			ctx, cancel := context.WithCancel(t.Context())
			defer cancel()
			if operation == "cancel" {
				i.checkpoint = func(name string) error {
					if name == "file-0" {
						cancel()
					}
					return nil
				}
			} else {
				service.fail = operation
			}
			if err := i.transact(ctx, before, after, serviceState{Present: true, Enabled: true, Active: true}); err == nil {
				t.Fatal("failure accepted")
			}
			verifyFixture(t, i, before)
			if !service.active || !service.enabled {
				t.Fatal("old service not restored")
			}
		})
	}
}

func TestUnconfirmedNetworkRecoveryKeepsJournalAndFiles(t *testing.T) {
	_, i, _, capture := newFixture(t)
	before := installFixture(t, i, "old")
	after := stageFixture(t, i, "new")
	capture.fail = true
	if err := i.transact(t.Context(), before, after, serviceState{Present: true, Enabled: true, Active: true}); err == nil || !strings.Contains(err.Error(), "rollback pending") {
		t.Fatal(err)
	}
	if err := i.verifyFiles(t.Context(), before); err != nil {
		t.Fatal("changed files before confirmed network recovery", err)
	}
	if record, err := i.readTransaction(); err != nil || record == nil || record.Committed {
		t.Fatal("lost recovery journal", err)
	}
	capture.fail = false
	if err := i.recover(t.Context()); err != nil {
		t.Fatal(err)
	}
	verifyFixture(t, i, before)
}

func TestUpgradeAndFailedUpgradePreserveDisabledSocket(t *testing.T) {
	for _, failure := range []bool{false, true} {
		t.Run(fmt.Sprint(failure), func(t *testing.T) {
			_, i, service, _ := newFixture(t)
			before := installFixture(t, i, "old")
			service.active = false
			service.enabled = false
			after := stageFixture(t, i, "new")
			if failure {
				i.checkpoint = func(name string) error {
					if name == "file-2" {
						return errors.New("fixture failure")
					}
					return nil
				}
			}
			err := i.transact(t.Context(), before, after, serviceState{Present: true})
			if (err != nil) != failure {
				t.Fatal(err)
			}
			want := after
			if failure {
				want = before
			}
			verifyFixture(t, i, want)
			if service.active || service.enabled {
				t.Fatal("upgrade re-enabled administrator-disabled socket")
			}
		})
	}
}

func TestUnmanagedModifiedOrCorruptInputsArePreserved(t *testing.T) {
	for _, kind := range []string{"unmanaged", "modified", "corrupt-manifest", "symlink"} {
		t.Run(kind, func(t *testing.T) {
			root, i, service, _ := newFixture(t)
			if kind != "unmanaged" {
				installFixture(t, i, "old")
			}
			path := root + targets[0].path
			switch kind {
			case "unmanaged", "modified":
				if err := os.WriteFile(path, []byte("administrator-data"), 0755); err != nil {
					t.Fatal(err)
				}
			case "corrupt-manifest":
				if err := i.state.Write(manifestName, []byte("invalid"), false); err != nil {
					t.Fatal(err)
				}
			case "symlink":
				if err := os.Remove(path); err != nil {
					t.Fatal(err)
				}
				if err := os.Symlink("/no-such-target", path); err != nil {
					t.Fatal(err)
				}
			}
			calls := len(service.calls)
			if err := i.change(t.Context(), false, nil); err == nil {
				t.Fatal("unknown data accepted")
			}
			if len(service.calls) != calls {
				t.Fatal("service changed before ownership validation")
			}
			if kind == "unmanaged" || kind == "modified" {
				data, err := os.ReadFile(path)
				if err != nil || string(data) != "administrator-data" {
					t.Fatal(err)
				}
			}
		})
	}
}

func TestRecoveryRefusesMissingBackupsAndForeignChanges(t *testing.T) {
	for _, kind := range []string{"backup", "destination", "manifest"} {
		t.Run(kind, func(t *testing.T) {
			root, i, service, _ := newFixture(t)
			before := installFixture(t, i, "old")
			after := stageFixture(t, i, "new")
			if err := i.backup(t.Context(), before); err != nil {
				t.Fatal(err)
			}
			record := &transaction{Version: 1, Before: before, After: after, Service: serviceState{Present: true, Enabled: true, Active: true}}
			if err := writeJSON(i.state, journalName, record, true); err != nil {
				t.Fatal(err)
			}
			if err := i.applyFile(t.Context(), 0, false, entry(after, 0)); err != nil {
				t.Fatal(err)
			}
			switch kind {
			case "backup":
				if err := i.spool.Remove(stagedName(1, true)); err != nil {
					t.Fatal(err)
				}
			case "destination":
				if err := os.WriteFile(root+targets[1].path, []byte("foreign-data"), 0755); err != nil {
					t.Fatal(err)
				}
			case "manifest":
				if err := i.state.Write(manifestName, []byte("invalid"), false); err != nil {
					t.Fatal(err)
				}
			}
			calls := len(service.calls)
			if err := i.recover(t.Context()); err == nil {
				t.Fatal("unsafe rollback accepted")
			}
			if len(service.calls) != calls {
				t.Fatal("unsafe rollback modified services")
			}
			if data, err := i.state.Read(journalName, metadataLimit); err != nil || len(data) == 0 {
				t.Fatal("lost pending transaction", err)
			}
		})
	}
}

func TestInstallerCrashWorker(t *testing.T) {
	root := os.Getenv("RAINLINK_TEST_INSTALL_ROOT")
	if root == "" {
		return
	}
	i, err := openInstaller(root, &fakeServices{root: root, enabled: true, active: true}, &fakeCapture{})
	if err != nil {
		t.Fatal(err)
	}
	before, err := readManifest(i.state)
	if err != nil {
		t.Fatal(err)
	}
	var after *manifest
	if os.Getenv("RAINLINK_TEST_INSTALL_ACTION") != "uninstall" {
		after = stageFixture(t, i, "crash-new")
	}
	point := os.Getenv("RAINLINK_TEST_INSTALL_CRASH")
	i.checkpoint = func(name string) error {
		if name == point {
			_ = syscall.Kill(os.Getpid(), syscall.SIGKILL)
		}
		return nil
	}
	state := serviceState{}
	if before != nil {
		state = serviceState{Present: true, Enabled: true, Active: true}
	}
	if err = i.transact(t.Context(), before, after, state); err != nil {
		t.Fatal(err)
	}
	t.Fatal("crash checkpoint was not reached")
}

func TestActualProcessKillIsRecoverableAtEveryCheckpoint(t *testing.T) {
	for _, action := range []string{"install", "upgrade", "uninstall"} {
		for _, point := range []string{"journal", "stopped", "file-0", "file-1", "file-2", "file-3", "file-4", "started", "manifest", "committed"} {
			t.Run(action+"/"+point, func(t *testing.T) {
				root, i, _, _ := newFixture(t)
				var before *manifest
				if action != "install" {
					before = installFixture(t, i, "old")
				}
				command := exec.Command(os.Args[0], "-test.run=^TestInstallerCrashWorker$")
				command.Env = append(os.Environ(), "RAINLINK_TEST_INSTALL_ROOT="+root, "RAINLINK_TEST_INSTALL_ACTION="+action, "RAINLINK_TEST_INSTALL_CRASH="+point)
				if data, err := command.CombinedOutput(); err == nil {
					t.Fatal("child was not killed", string(data))
				} else {
					var exit *exec.ExitError
					if !errors.As(err, &exit) || !exit.ProcessState.Sys().(syscall.WaitStatus).Signaled() || exit.ProcessState.Sys().(syscall.WaitStatus).Signal() != syscall.SIGKILL {
						t.Fatal("child failed before intended SIGKILL", err, string(data))
					}
				}
				if err := i.recover(t.Context()); err != nil {
					t.Fatal(err)
				}
				want := before
				if point == "committed" {
					var err error
					want, err = readManifest(i.state)
					if err != nil {
						t.Fatal(err)
					}
					if action == "uninstall" && want != nil {
						t.Fatal("uninstall commit was lost")
					}
					if action != "uninstall" && (want == nil || reflect.DeepEqual(want, before)) {
						t.Fatal("installation commit was lost")
					}
				}
				verifyFixture(t, i, want)
			})
		}
	}
}
