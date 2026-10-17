//go:build linux && !android

package linuxtun

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strconv"
	"testing"
	"time"

	"rainlink.local/host/internal/coreprocess"
	"rainlink.local/host/internal/linuxnet"
)

func requireRootFixture(t *testing.T) {
	t.Helper()
	if os.Getenv("RAINLINK_TEST_ROOT_TUN_NAMESPACE") != "isolated" {
		t.Skip("requires root inside disposable namespaces with private /run")
	}
	current, err := os.Readlink("/proc/self/ns/net")
	parent := os.Getenv("RAINLINK_TEST_PARENT_NETNS")
	if err != nil || parent == "" || current == parent || os.Geteuid() != 0 {
		t.Fatal("root TUN fixture is not isolated", err)
	}
	// The official fixture writes this marker after mounting a private /run.
	// Never invoke production New() merely because networking is isolated.
	marker, err := os.ReadFile("/run/rainlink-test-netns")
	if err != nil || string(marker) != current {
		t.Fatal("private runtime directory was not established", err)
	}
}

func TestLinuxTUNGuardianFixture(t *testing.T) {
	mode := os.Getenv("RAINLINK_TEST_TUN_GUARDIAN")
	if mode != "child" && mode != "contender" {
		t.Skip("fixture child only")
	}
	requireRootFixture(t)
	pid, err := strconv.Atoi(os.Getenv("RAINLINK_TEST_TUN_CORE_PID"))
	if err != nil {
		t.Fatal(err)
	}
	controller, err := New()
	if err != nil {
		t.Fatal(err)
	}
	lease, err := controller.Acquire(t.Context(), "rl-deadguard")
	if mode == "contender" {
		if !errors.Is(err, ErrOwned) {
			t.Fatal("competing process acquired an active lease", err)
		}
		os.Exit(0)
	}
	if err != nil {
		t.Fatal(err)
	}
	if err = lease.BindCore(t.Context(), pid); err != nil {
		t.Fatal(err)
	}
	if err = json.NewEncoder(os.Stdout).Encode(lease.Specification()); err != nil {
		t.Fatal(err)
	}
	// Simulate abrupt guardian exit without Restore/Close. The kernel releases
	// flock; the durable record must remain sufficient for another guardian.
	os.Exit(0)
}

func TestIsolatedTUNLeaseAndDeadGuardianRecovery(t *testing.T) {
	requireRootFixture(t)
	core := os.Getenv("RAINLINK_TEST_CORE_PATH")
	if !coreprocess.Trusted(core) {
		t.Fatal("requires the locked Linux core")
	}
	for _, scenario := range []string{"held-lease", "dead-guardian"} {
		t.Run(scenario, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(t.Context(), 15*time.Second)
			defer cancel()
			before, err := linuxnet.Read(ctx)
			if err != nil {
				t.Fatal(err)
			}
			controller, err := New()
			if err != nil {
				t.Fatal(err)
			}
			command := exec.CommandContext(ctx, core, "run", "-c", "stdin")
			command.Env = []string{"PATH=", "LANG=C"}
			input, err := command.StdinPipe()
			if err != nil {
				t.Fatal(err)
			}
			if err = command.Start(); err != nil {
				_ = input.Close()
				t.Fatal(err)
			}
			done := make(chan error, 1)
			go func() { done <- command.Wait() }()
			reaped := false
			t.Cleanup(func() {
				_ = input.Close()
				if !reaped {
					_ = command.Process.Kill()
					<-done
				}
			})
			var lease *Lease
			var specification Specification
			if scenario == "held-lease" {
				lease, err = controller.Acquire(ctx, "rl-lease-test")
				if err != nil {
					t.Fatal(err)
				}
				t.Cleanup(func() {
					if !lease.closed {
						_ = lease.Close()
					}
				})
				specification = lease.Specification()
				if err = lease.BindCore(ctx, command.Process.Pid); err != nil {
					t.Fatal(err)
				}
				if err = lease.Restore(ctx); !errors.Is(err, ErrCoreAlive) {
					t.Fatal("blocked live core allowed cleanup", err)
				}
				if _, err = controller.Acquire(ctx, "rl-second"); !errors.Is(err, ErrOwned) {
					t.Fatal("lease did not exclude another capture", err)
				}
				executable, err := os.Executable()
				if err != nil {
					t.Fatal(err)
				}
				contender := exec.CommandContext(ctx, executable, "-test.run=^TestLinuxTUNGuardianFixture$")
				contender.Env = append(os.Environ(), "RAINLINK_TEST_TUN_GUARDIAN=contender", "RAINLINK_TEST_TUN_CORE_PID="+strconv.Itoa(command.Process.Pid))
				if data, err := contender.CombinedOutput(); err != nil {
					t.Fatal("cross-process lease exclusion", err, string(data))
				}
			} else {
				executable, err := os.Executable()
				if err != nil {
					t.Fatal(err)
				}
				guardian := exec.CommandContext(ctx, executable, "-test.run=^TestLinuxTUNGuardianFixture$")
				guardian.Env = append(os.Environ(), "RAINLINK_TEST_TUN_GUARDIAN=child", "RAINLINK_TEST_TUN_CORE_PID="+strconv.Itoa(command.Process.Pid))
				data, err := guardian.Output()
				if err != nil {
					t.Fatal("guardian fixture", err)
				}
				if err = json.Unmarshal(data, &specification); err != nil {
					t.Fatal("guardian resource reply", err)
				}
				if err = controller.Recover(ctx); !errors.Is(err, ErrCoreAlive) {
					t.Fatal("dead guardian allowed live core cleanup", err)
				}
			}
			configuration := managedCoreConfiguration(specification)
			// Persisting the binding precedes even the first config byte.
			if err = json.NewEncoder(input).Encode(configuration); err != nil {
				t.Fatal(err)
			}
			if err = input.Close(); err != nil {
				t.Fatal(err)
			}
			var ready linuxnet.State
			expected, err := specification.ExpectedRules()
			if err != nil {
				t.Fatal(err)
			}
			deadline := time.Now().Add(4 * time.Second)
			for {
				ready, err = linuxnet.Read(ctx)
				if err != nil {
					t.Fatal(err)
				}
				matches := 0
				for _, owned := range expected {
					for _, observed := range ready.Rules {
						same, err := linuxnet.SameRule(owned, observed)
						if err != nil {
							t.Fatal(err)
						}
						if same {
							matches++
						}
					}
				}
				if matches == len(expected) {
					break
				}
				select {
				case err := <-done:
					reaped = true
					t.Fatal("core exited before TUN setup", err)
				default:
				}
				if time.Now().After(deadline) {
					t.Fatal("core did not create every precomputed rule", matches)
				}
				time.Sleep(20 * time.Millisecond)
			}
			if err = command.Process.Kill(); err != nil {
				t.Fatal(err)
			}
			<-done
			reaped = true
			killed, err := linuxnet.Read(ctx)
			if err != nil || len(killed.Rules) != len(before.Rules)+16 {
				t.Fatal("abrupt-exit fixture did not leave 16 rules", err)
			}
			if lease != nil {
				if err = lease.Restore(ctx); err != nil {
					t.Fatal("lease recovery", err)
				}
				if err = lease.Close(); err != nil {
					t.Fatal(err)
				}
			} else if err = controller.Recover(ctx); err != nil {
				t.Fatal("dead guardian recovery", err)
			}
			after, err := linuxnet.Read(ctx)
			if err != nil || !reflect.DeepEqual(before, after) {
				t.Fatal("recovery did not restore exact initial network state", err)
			}
			if _, err = os.Stat(filepath.Join(runtimeDirectory, journalName)); !errors.Is(err, os.ErrNotExist) {
				t.Fatal("successful recovery retained journal", err)
			}
			if err = controller.Recover(ctx); err != nil {
				t.Fatal("empty recovery is not idempotent", err)
			}
			if directory := os.Getenv("RAINLINK_TEST_NETWORK_EVIDENCE_DIR"); directory != "" {
				data, err := json.MarshalIndent(map[string]any{"scenario": scenario, "resources": specification, "before": before, "ready": ready, "killed": killed, "recovered": after}, "", "  ")
				if err != nil {
					t.Fatal(err)
				}
				if err = os.WriteFile(filepath.Join(directory, "lease-"+scenario+".json"), append(data, '\n'), 0600); err != nil {
					t.Fatal(err)
				}
			}
		})
	}
}
