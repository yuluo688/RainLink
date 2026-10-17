//go:build linux && !android

package linuxnet_test

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"testing"
	"time"

	"rainlink.local/host/internal/coreprocess"
	"rainlink.local/host/internal/linuxnet"
	"rainlink.local/host/internal/linuxtun"
)

func TestLockedLinuxCoreTUNGracefulAndKilledPolicyState(t *testing.T) {
	if os.Getenv("RAINLINK_TEST_ROOT_TUN_NAMESPACE") != "isolated" {
		t.Skip("requires root in a disposable, isolated network namespace")
	}
	current, err := os.Readlink("/proc/self/ns/net")
	parent := os.Getenv("RAINLINK_TEST_PARENT_NETNS")
	if err != nil || parent == "" || current == parent || os.Geteuid() != 0 {
		t.Fatal("root TUN fixture is not isolated", err)
	}
	core := os.Getenv("RAINLINK_TEST_CORE_PATH")
	if !coreprocess.Trusted(core) {
		t.Fatal("TUN fixture requires the locked Linux core")
	}
	const name, table, priority = "rl-kernel-test", 100003, 31000
	expected, err := (linuxtun.Specification{Name: name, Table: table, Priority: priority}).ExpectedRules()
	if err != nil || len(expected) != 16 {
		t.Fatal("invalid precomputed recovery rules", err)
	}
	before, err := linuxnet.Read(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	for _, link := range before.Links {
		if link.Name == name {
			t.Fatal("TUN fixture name is already in use")
		}
	}
	for _, route := range before.Routes {
		if route.Table == table {
			t.Fatal("TUN fixture table is already in use")
		}
	}
	for _, rule := range before.Rules {
		if rule.Table == table || rule.Priority >= priority && rule.Priority <= priority+10 {
			t.Fatal("TUN fixture policy range or table is already in use")
		}
	}
	for _, signal := range []syscall.Signal{syscall.SIGTERM, syscall.SIGKILL} {
		t.Run(signal.String(), func(t *testing.T) {
			ctx, cancel := context.WithTimeout(t.Context(), 15*time.Second)
			defer cancel()
			configuration := map[string]any{
				"log": map[string]any{"disabled": true},
				"inbounds": []any{map[string]any{
					"type": "tun", "tag": "tun", "interface_name": name,
					"address": []string{"172.29.255.1/30", "fdfe:dcba:9876::1/126"},
					"mtu":     1500, "stack": "system", "auto_route": true, "strict_route": true,
					"auto_redirect": false, "iproute2_table_index": table, "iproute2_rule_index": priority,
					"rainlink_managed": true,
				}},
				"outbounds": []any{map[string]any{"type": "direct", "tag": "direct", "bind_interface": "uplink0"}},
				"route":     map[string]any{"default_interface": "uplink0", "final": "direct"},
			}
			data, err := json.Marshal(configuration)
			if err != nil {
				t.Fatal(err)
			}
			command := exec.CommandContext(ctx, core, "run", "-c", "stdin")
			// sing-tun otherwise discovers resolvectl through PATH. Network
			// namespaces do not isolate a desktop's system D-Bus, so this fixture
			// must not execute external DNS-manager helpers on the QA host.
			command.Env = []string{"PATH=", "LANG=C"}
			command.Stdin = bytes.NewReader(data)
			if err = command.Start(); err != nil {
				t.Fatal(err)
			}
			done := make(chan error, 1)
			go func() { done <- command.Wait() }()
			var reaped bool
			t.Cleanup(func() {
				if !reaped {
					_ = command.Process.Kill()
					<-done
				}
			})
			read := func() (linuxnet.State, int, int, bool) {
				t.Helper()
				state, err := linuxnet.Read(ctx)
				if err != nil {
					t.Fatal(err)
				}
				var exists bool
				for _, link := range state.Links {
					exists = exists || link.Name == name
				}
				var routes, rules int
				for _, route := range state.Routes {
					if route.Table == table {
						routes++
					}
				}
				for _, rule := range state.Rules {
					if rule.Priority >= priority && rule.Priority <= priority+10 {
						rules++
					}
				}
				return state, routes, rules, exists
			}
			var ready linuxnet.State
			deadline := time.Now().Add(4 * time.Second)
			for {
				state, routes, rules, exists := read()
				// The locked dual-stack configuration installs 8 policy rules per
				// family. Do not signal a partly initialized core after its first rule.
				if exists && routes == 2 && rules == 16 {
					ready = state
					break
				}
				select {
				case err := <-done:
					reaped = true
					t.Fatal("locked core exited before creating TUN policy", err)
				default:
				}
				if time.Now().After(deadline) {
					t.Fatal("locked core did not create dual-stack TUN policy")
				}
				time.Sleep(20 * time.Millisecond)
			}
			for _, owned := range expected {
				matches := 0
				for _, observed := range ready.Rules {
					same, err := linuxnet.SameRule(owned, observed)
					if err != nil {
						t.Fatal(err)
					}
					if same {
						matches++
					}
				}
				if matches != 1 {
					t.Fatalf("precomputed rule does not uniquely match locked core: %+v (matches=%d)", owned, matches)
				}
			}
			if err = command.Process.Signal(signal); err != nil {
				t.Fatal(err)
			}
			exitErr := <-done
			reaped = true
			if signal == syscall.SIGTERM && exitErr != nil {
				t.Fatal("graceful core shutdown failed", exitErr)
			}
			after, routes, rules, exists := read()
			if exists || routes != 0 {
				t.Fatal("TUN link or interface-bound routes survived process exit")
			}
			if rules != len(expected) {
				t.Fatal("managed core must defer every policy deletion to its guardian", signal, rules)
			}
			for _, owned := range expected {
				if _, err := linuxnet.DeleteExactRule(ctx, owned); err != nil {
					t.Fatal("exact recovery failed", err)
				}
			}
			recovered, routes, rules, exists := read()
			if exists || routes != 0 || rules != 0 {
				t.Fatal("owned TUN resources survived exact recovery")
			}
			if directory := os.Getenv("RAINLINK_TEST_NETWORK_EVIDENCE_DIR"); directory != "" {
				data, err := json.MarshalIndent(map[string]any{"signal": signal.String(), "ready": ready, "after": after, "recovered": recovered}, "", "  ")
				if err != nil {
					t.Fatal(err)
				}
				filename := "core-graceful.json"
				if signal == syscall.SIGKILL {
					filename = "core-killed.json"
				}
				if err = os.WriteFile(filepath.Join(directory, filename), append(data, '\n'), 0600); err != nil {
					t.Fatal(err)
				}
			}
		})
	}
}
