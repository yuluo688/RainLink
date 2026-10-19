//go:build linux && !android

package linuxinstall

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"rainlink.local/host/internal/linuxtun"
	"rainlink.local/host/internal/rootfs"
)

type cancellationObservation struct {
	Scenario     string                       `json:"scenario"`
	Checkpoint   string                       `json:"checkpoint"`
	Committed    bool                         `json:"committedBeforeCancel"`
	Before       *manifest                    `json:"before"`
	AtCancel     [len(targets)]*rootfs.Digest `json:"filesAtCancel"`
	After        *manifest                    `json:"after"`
	ServiceAfter serviceState                 `json:"serviceAfter"`
	Cancelled    bool                         `json:"returnedCancellation"`
}

// The private checkpoint cancels a real installer after an observed durable
// write. It is not an externally controlled hook in a production executable.
func TestRealSystemdCancellationAtDurableBoundaries(t *testing.T) {
	if os.Getenv("RAINLINK_TEST_REAL_SYSTEMD") != "disposable-vm" {
		t.Skip("requires disposable systemd VM")
	}
	if os.Geteuid() != 0 || fixtureEnabled() {
		t.Fatal("requires real systemd without fixture tools")
	}
	if data, err := os.ReadFile("/proc/1/comm"); err != nil || strings.TrimSpace(string(data)) != "systemd" {
		t.Fatal("PID 1 is not systemd", err)
	}
	host := filepath.Join(filepath.Dir(os.Args[0]), "rainlink-host")
	run := func(test *testing.T, parent context.Context, program string, args ...string) {
		test.Helper()
		ctx, cancel := context.WithTimeout(parent, operationTimeout+15*time.Second)
		defer cancel()
		if data, err := exec.CommandContext(ctx, program, args...).CombinedOutput(); err != nil {
			test.Fatalf("real VM command %s: %v %s", filepath.Base(program), err, data)
		}
	}
	service := systemServices{}
	if state, err := service.state(t.Context()); err != nil || state.Present {
		t.Fatal("VM requires absent service", state, err)
	}
	t.Cleanup(func() { run(t, context.Background(), host, "uninstall-tun") })
	for _, scenario := range []struct {
		action, checkpoint string
	}{
		{"install", "file-0"},
		{"install", "manifest"},
		{"upgrade-disabled", "file-1"},
		{"uninstall-enabled", "file-2"},
		{"upgrade-disabled", "committed"},
	} {
		t.Run(scenario.action+"/"+scenario.checkpoint, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(t.Context(), operationTimeout+15*time.Second)
			defer cancel()
			if scenario.action != "install" {
				previous := filepath.Join(filepath.Dir(host), "previous", "rainlink-host")
				run(t, ctx, previous, "install-tun")
				if scenario.action == "upgrade-disabled" {
					run(t, ctx, "/usr/bin/systemctl", "disable", "--now", socketUnit)
				}
			}
			controller, err := linuxtun.New()
			if err != nil {
				t.Fatal(err)
			}
			i, err := openInstaller("", service, controller)
			if err != nil {
				t.Fatal(err)
			}
			defer func() {
				if err := i.close(); err != nil {
					t.Error(err)
				}
			}()
			unlock, err := i.state.Lock(ctx, "install.lock")
			if err != nil {
				t.Fatal(err)
			}
			locked := true
			defer func() {
				if locked {
					if err := unlock(); err != nil {
						t.Error(err)
					}
				}
			}()
			before, err := readManifest(i.state)
			if err != nil {
				t.Fatal(err)
			}
			beforeState, err := service.state(ctx)
			if err != nil {
				t.Fatal(err)
			}
			observation := cancellationObservation{Scenario: scenario.action, Checkpoint: scenario.checkpoint, Before: before}
			var expected *manifest
			reached := false
			i.checkpoint = func(point string) error {
				if point != scenario.checkpoint {
					return nil
				}
				reached = true
				record, err := i.readTransaction()
				if err != nil || record == nil || record.Committed != (point == "committed") {
					t.Fatal("durable journal did not match cancellation point", record, err)
				}
				observation.Committed = record.Committed
				for index := range targets {
					observation.AtCancel[index], err = i.inspect(ctx, index)
					if err != nil {
						t.Fatal(err)
					}
				}
				if scenario.action == "install" && observation.AtCancel[0] == nil ||
					scenario.action == "upgrade-disabled" && equal(observation.AtCancel[0], entry(before, 0)) ||
					scenario.action == "uninstall-enabled" && (observation.AtCancel[0] != nil || observation.AtCancel[1] != nil || observation.AtCancel[2] != nil) {
					t.Fatal("cancellation was not reached after an actual installation change")
				}
				expected = record.Before
				if record.Committed {
					expected = record.After
				}
				cancel()
				return nil
			}
			source, err := os.Open(host)
			if err != nil {
				t.Fatal(err)
			}
			defer func() {
				if err := source.Close(); err != nil {
					t.Error(err)
				}
			}()
			err = i.change(ctx, scenario.action != "uninstall-enabled", source)
			if !reached || !errors.Is(err, context.Canceled) {
				t.Fatal("real installation did not cancel at the intended boundary", reached, err)
			}
			observation.Cancelled = true
			verifyFixture(t, i, expected)
			actual, err := readManifest(i.state)
			if err != nil || !reflect.DeepEqual(actual, expected) {
				t.Fatal("real installation manifest was not recovered", err)
			}
			state, err := service.state(t.Context())
			if err != nil || state != beforeState {
				t.Fatal("real socket state was not retained", state, beforeState, err)
			}
			if state.Active {
				if err := service.ready(t.Context()); err != nil {
					t.Fatal("recovered socket was not usable", err)
				}
			}
			observation.After, observation.ServiceAfter = actual, state
			if directory := os.Getenv("RAINLINK_TEST_INSTALL_CANCELLATION_EVIDENCE"); directory != "" {
				data, err := json.MarshalIndent(observation, "", "  ")
				if err != nil {
					t.Fatal(err)
				}
				name := "installation-cancel-" + scenario.action + "-" + scenario.checkpoint + ".json"
				if err = os.WriteFile(filepath.Join(directory, name), append(data, '\n'), 0600); err != nil {
					t.Fatal(err)
				}
			}
			t.Logf("actual files changed before %s cancellation; original error, manifest and real socket state confirmed", scenario.checkpoint)
			// Release the real install lock before the separate CLI cleanup.
			err = unlock()
			locked = false
			if err != nil {
				t.Fatal(err)
			}
			run(t, t.Context(), host, "uninstall-tun")
		})
	}
}
