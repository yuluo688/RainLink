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
	"syscall"
	"testing"
	"time"

	"golang.org/x/sys/unix"
	"rainlink.local/host/internal/coreprocess"
	"rainlink.local/host/internal/linuxnet"
)

func managedCoreConfiguration(specification Specification) map[string]any {
	return map[string]any{
		"log": map[string]any{"disabled": true},
		"inbounds": []any{map[string]any{"type": "tun", "interface_name": specification.Name,
			"address": []string{"172.29.255.1/30", "fdfe:dcba:9876::1/126"}, "mtu": 1500, "stack": "system",
			"auto_route": true, "strict_route": true, "auto_redirect": false, "rainlink_managed": true,
			"iproute2_table_index": specification.Table, "iproute2_rule_index": specification.Priority}},
		"outbounds": []any{map[string]any{"type": "direct", "tag": "direct", "bind_interface": "uplink0"}},
		"route":     map[string]any{"default_interface": "uplink0", "final": "direct"},
	}
}

func TestIsolatedManagedCoreCollisionAndForeignOwner(t *testing.T) {
	requireRootFixture(t)
	core := os.Getenv("RAINLINK_TEST_CORE_PATH")
	if !coreprocess.Trusted(core) {
		t.Fatal("requires locked managed Linux core")
	}
	for _, scenario := range []string{"startup-policy-collision", "startup-route-collision-v6", "existing-interface", "graceful-later-owner"} {
		t.Run(scenario, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(t.Context(), 15*time.Second)
			defer cancel()
			read := func() linuxnet.State {
				t.Helper()
				state, err := linuxnet.Read(ctx)
				if err != nil {
					t.Fatal(err)
				}
				return state
			}
			mutate := func(arguments ...string) {
				t.Helper()
				if data, err := exec.CommandContext(ctx, "/sbin/ip", arguments...).CombinedOutput(); err != nil {
					t.Fatal("isolated fixture setup", err, string(data))
				}
			}
			before := read()
			controller, err := New()
			if err != nil {
				t.Fatal(err)
			}
			lease, err := controller.Acquire(ctx, "rl-foreign-test")
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() {
				if !lease.closed {
					_ = lease.Close()
				}
			})
			specification := lease.Specification()
			priority, table := strconv.Itoa(int(specification.Priority)), strconv.Itoa(int(specification.Table))
			if scenario == "startup-policy-collision" {
				mutate("-4", "rule", "add", "priority", priority, "table", table, "protocol", "99")
			}
			if scenario == "startup-route-collision-v6" {
				mutate("-6", "route", "add", "blackhole", "2001:db8:ffff::/64", "table", table, "protocol", "99")
			}
			if scenario == "existing-interface" {
				mutate("link", "add", specification.Name, "type", "dummy")
			}
			prepared := read()
			stub := t.TempDir()
			marker := filepath.Join(stub, "dns-helper-called")
			// This executable only writes a disposable marker. Its presence tests
			// the managed DNS skip without exposing a desktop's real resolvectl.
			if err = os.WriteFile(filepath.Join(stub, "resolvectl"), []byte("#!/bin/sh\nprintf called > \"$RAINLINK_TEST_DNS_MARKER\"\n"), 0700); err != nil {
				t.Fatal(err)
			}
			command := exec.CommandContext(ctx, core, "run", "-c", "stdin")
			command.Env = []string{"PATH=" + stub, "LANG=C", "RAINLINK_TEST_DNS_MARKER=" + marker}
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
			if err = lease.BindCore(ctx, command.Process.Pid); err != nil {
				t.Fatal(err)
			}
			if err = json.NewEncoder(input).Encode(managedCoreConfiguration(specification)); err != nil {
				t.Fatal(err)
			}
			if err = input.Close(); err != nil {
				t.Fatal(err)
			}
			if scenario == "graceful-later-owner" {
				expected, err := specification.ExpectedRules()
				if err != nil {
					t.Fatal(err)
				}
				deadline := time.Now().Add(4 * time.Second)
				for {
					state := read()
					matches := 0
					for _, wanted := range expected {
						for _, current := range state.Rules {
							same, err := linuxnet.SameRule(wanted, current)
							if err != nil {
								t.Fatal(err)
							}
							if same {
								matches++
							}
						}
					}
					if matches == 16 {
						break
					}
					select {
					case err := <-done:
						reaped = true
						t.Fatal("managed core exited before setup", err)
					default:
					}
					if time.Now().After(deadline) {
						t.Fatal("managed core did not install tagged rules")
					}
					time.Sleep(20 * time.Millisecond)
				}
				mutate("-4", "rule", "add", "priority", priority, "table", table, "protocol", "99")
				mutate("-6", "rule", "add", "priority", priority, "table", table, "protocol", "99")
				mutate("-4", "route", "add", "blackhole", "203.0.113.0/24", "table", table, "protocol", "99")
				if err = command.Process.Signal(syscall.SIGTERM); err != nil {
					t.Fatal(err)
				}
			}
			exitErr := <-done
			reaped = true
			if (exitErr == nil) != (scenario == "graceful-later-owner") {
				t.Fatal("unexpected managed core exit", exitErr)
			}
			afterCore := read()
			if scenario != "graceful-later-owner" && !reflect.DeepEqual(prepared, afterCore) {
				t.Fatal("startup collision changed existing network objects")
			}
			if _, err = os.Stat(marker); !errors.Is(err, os.ErrNotExist) {
				t.Fatal("managed core executed an external DNS helper", err)
			}
			if scenario == "existing-interface" {
				if err = lease.Restore(ctx); !errors.Is(err, ErrPending) {
					t.Fatal("same-name interface was not preserved", err)
				}
				mutate("link", "delete", specification.Name)
			}
			if err = lease.Restore(ctx); err != nil {
				t.Fatal(err)
			}
			afterRecovery := read()
			if scenario == "graceful-later-owner" {
				var foreignRules, foreignRoutes int
				for _, rule := range afterRecovery.Rules {
					if rule.Priority == specification.Priority && rule.Table == specification.Table {
						foreignRules++
						found := false
						for _, attribute := range rule.Attributes {
							if attribute.Type == unix.FRA_PROTOCOL && len(attribute.Value) == 1 && attribute.Value[0] == 99 {
								found = true
							}
						}
						if !found {
							t.Fatal("foreign policy protocol was replaced")
						}
					}
				}
				for _, route := range afterRecovery.Routes {
					if route.Table == specification.Table && route.Protocol == 99 {
						foreignRoutes++
					}
				}
				if foreignRules != 2 || foreignRoutes != 1 {
					t.Fatal("later rules or routes were removed", foreignRules, foreignRoutes)
				}
				mutate("-6", "rule", "delete", "priority", priority, "table", table, "protocol", "99")
				mutate("-4", "route", "delete", "blackhole", "203.0.113.0/24", "table", table, "protocol", "99")
			}
			if scenario == "startup-route-collision-v6" {
				mutate("-6", "route", "delete", "blackhole", "2001:db8:ffff::/64", "table", table, "protocol", "99")
			}
			if scenario == "startup-policy-collision" || scenario == "graceful-later-owner" {
				mutate("-4", "rule", "delete", "priority", priority, "table", table, "protocol", "99")
			}
			if err = lease.Close(); err != nil {
				t.Fatal(err)
			}
			final := read()
			if !reflect.DeepEqual(before, final) {
				t.Fatal("fixture did not restore exact initial network state")
			}
			if directory := os.Getenv("RAINLINK_TEST_NETWORK_EVIDENCE_DIR"); directory != "" {
				data, err := json.MarshalIndent(map[string]any{"scenario": scenario, "resources": specification, "before": before,
					"afterCore": afterCore, "afterRecovery": afterRecovery, "afterFixtureCleanup": final, "dnsHelperInvoked": false}, "", "  ")
				if err != nil {
					t.Fatal(err)
				}
				if err = os.WriteFile(filepath.Join(directory, "managed-"+scenario+".json"), append(data, '\n'), 0600); err != nil {
					t.Fatal(err)
				}
			}
		})
	}
}
