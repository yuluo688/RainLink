//go:build linux && !android

package session

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"syscall"
	"testing"
	"time"

	"rainlink.local/host/internal/linuxnet"
)

// This uses the actual pkcheck and polkitd with a VM-only, UID/action-scoped
// YES/NO rule. It verifies authority decisions, not an interactive desktop agent.
func TestRealSystemdTUNPermissionLogs(t *testing.T) {
	if os.Getenv("RAINLINK_TEST_REAL_SYSTEMD_LOGS") != "disposable-vm" {
		t.Skip("requires disposable systemd/polkit VM")
	}
	if data, err := os.ReadFile("/proc/1/comm"); err != nil || strings.TrimSpace(string(data)) != "systemd" || os.Geteuid() != 0 {
		t.Fatal("requires root in the disposable systemd VM", err)
	}
	ctx, cancel := context.WithTimeout(t.Context(), 3*time.Minute)
	defer cancel()
	host := filepath.Join(filepath.Dir(os.Args[0]), "rainlink-host")
	run := func(ctx context.Context, path string, arguments ...string) []byte {
		t.Helper()
		operation, stop := context.WithTimeout(ctx, 60*time.Second)
		defer stop()
		data, err := exec.CommandContext(operation, path, arguments...).CombinedOutput()
		if err != nil {
			t.Fatalf("VM command failed (%s): %v, %s", filepath.Base(path), err, data)
		}
		return data
	}
	const policy = "/etc/polkit-1/rules.d/40-rainlink-log-qa.rules"
	if _, err := os.Lstat(policy); !os.IsNotExist(err) {
		t.Fatal("VM-only rule path already exists", err)
	}
	if _, err := os.Lstat(installedTUNHost); !os.IsNotExist(err) {
		t.Fatal("VM already has a permission host", err)
	}
	run(ctx, host, "install-tun")
	t.Cleanup(func() {
		cleanup, stop := context.WithTimeout(context.Background(), 75*time.Second)
		defer stop()
		if data, err := exec.CommandContext(cleanup, host, "uninstall-tun").CombinedOutput(); err != nil {
			t.Errorf("VM uninstall failed: %v, %s", err, data)
		}
		if err := os.Remove(policy); err != nil && !os.IsNotExist(err) {
			t.Error("could not remove VM-only policy", err)
		}
		if data, err := exec.CommandContext(cleanup, "/usr/bin/systemctl", "restart", "polkit.service").CombinedOutput(); err != nil {
			t.Errorf("VM policy reload after cleanup failed: %v, %s", err, data)
		}
	})
	beforeStart := time.Now()
	before, err := linuxnet.Read(ctx)
	beforeEnd := time.Now()
	if err != nil {
		t.Fatal(err)
	}
	for _, scenario := range []string{"allow", "deny"} {
		t.Run(scenario, func(t *testing.T) {
			decision := "YES"
			if scenario == "deny" {
				decision = "NO"
			}
			rule := "polkit.addRule(function(action, subject) {\n" +
				"  if (action.id === 'org.rainlink.tun.manage' && subject.user === 'nobody') {\n" +
				"    return polkit.Result." + decision + ";\n  }\n});\n"
			if err := os.WriteFile(policy, []byte(rule), 0644); err != nil {
				t.Fatal(err)
			}
			run(ctx, "/usr/bin/systemctl", "restart", "polkit.service")
			client := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestRealSystemdTUNLogClientFixture$", "-test.timeout=90s")
			client.Env = []string{"PATH=/usr/bin:/bin", "LANG=C", "LC_ALL=C", "RAINLINK_TEST_SYSTEMD_LOG_CLIENT=" + scenario}
			client.SysProcAttr = &syscall.SysProcAttr{Credential: &syscall.Credential{Uid: 65534, Gid: 65534}}
			data, err := client.CombinedOutput()
			if directory := os.Getenv("RAINLINK_TEST_SYSTEMD_LOG_EVIDENCE"); directory != "" {
				if writeErr := os.WriteFile(filepath.Join(directory, "native-client-"+scenario+".log"), data, 0600); writeErr != nil {
					t.Fatal(writeErr)
				}
			}
			if err != nil {
				t.Fatalf("ordinary native client failed: %v, %s", err, data)
			}
			if err := ConfirmLinuxTUNServiceIdle(ctx); err != nil {
				t.Fatal("real service did not confirm restored state", err)
			}
			afterStart := time.Now()
			after, err := linuxnet.Read(ctx)
			afterEnd := time.Now()
			if directory := os.Getenv("RAINLINK_TEST_SYSTEMD_LOG_EVIDENCE"); directory != "" {
				data, encodeErr := json.MarshalIndent(map[string]any{"before": before, "after": after,
					"elapsedMinNs": afterStart.Sub(beforeEnd).Nanoseconds(), "elapsedMaxNs": afterEnd.Sub(beforeStart).Nanoseconds()}, "", "  ")
				if encodeErr != nil {
					t.Fatal(encodeErr)
				}
				if writeErr := os.WriteFile(filepath.Join(directory, "network-"+scenario+".json"), append(data, '\n'), 0600); writeErr != nil {
					t.Fatal(writeErr)
				}
			}
			if err != nil {
				t.Fatal(err)
			}
			expected := before
			expected.Routes, err = expectedSystemdRouteAging(before.Routes, after.Routes, afterStart.Sub(beforeEnd), afterEnd.Sub(beforeStart))
			if err != nil || !reflect.DeepEqual(expected, after) {
				t.Fatal("real service changed the VM network after cleanup", err)
			}
			t.Log("actual systemd socket and polkit decision delivered private logs and confirmed idle")
		})
	}
	journal := run(ctx, "/usr/bin/journalctl", "-b", "--no-pager", "-o", "cat", "-u", "rainlink-tun@*.service")
	for _, forbidden := range []string{"fixture-systemd-password", "fixture-systemd-user", "sing-box started", "inbound/tun", "apiSecret"} {
		if strings.Contains(string(journal), forbidden) {
			t.Fatal("core/private data reached system journal", forbidden)
		}
	}
	if directory := os.Getenv("RAINLINK_TEST_SYSTEMD_LOG_EVIDENCE"); directory != "" {
		data, err := json.MarshalIndent(map[string]any{"before": before}, "", "  ")
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(directory, "network-baseline.json"), append(data, '\n'), 0600); err != nil {
			t.Fatal(err)
		}
	}
}

// RTA_CACHEINFO includes the kernel's remaining route lifetime in USER_HZ.
// Requiring those live countdown bytes to freeze rejects an unchanged network.
// Accept only the observed elapsed-time decrement; every other byte/field is
// still compared, and raw before/after evidence is retained without filtering.
func expectedSystemdRouteAging(before, after []linuxnet.Route, minimum, maximum time.Duration) ([]linuxnet.Route, error) {
	const (
		routeCacheInfo = 12
		cacheInfoSize  = 32
		expiryOffset   = 8
		userClockTick  = time.Second / 100 // Linux USER_HZ on this amd64 VM.
	)
	expected := append([]linuxnet.Route(nil), before...)
	if len(before) != len(after) {
		return expected, fmt.Errorf("route count changed: %d to %d", len(before), len(after))
	}
	minTicks := max(int64(0), int64(minimum/userClockTick)-2)
	maxTicks := int64(maximum/userClockTick) + 2
	for index, route := range before {
		expected[index].Attributes = append([]linuxnet.Attribute(nil), route.Attributes...)
		if len(route.Attributes) != len(after[index].Attributes) {
			continue // The full snapshot comparison rejects this configuration change.
		}
		for slot, attribute := range route.Attributes {
			other := after[index].Attributes[slot]
			if attribute.Type != routeCacheInfo || other.Type != routeCacheInfo || len(attribute.Value) != cacheInfoSize || len(other.Value) != cacheInfoSize {
				continue
			}
			left := int64(int32(binary.NativeEndian.Uint32(attribute.Value[expiryOffset:])))
			right := int64(int32(binary.NativeEndian.Uint32(other.Value[expiryOffset:])))
			if left == 0 && right == 0 {
				continue
			}
			if left <= 0 || right <= 0 || left-right < minTicks || left-right > maxTicks {
				return nil, fmt.Errorf("route %d lifetime did not age by the measured interval", index)
			}
			value := append([]byte(nil), attribute.Value...)
			binary.NativeEndian.PutUint32(value[expiryOffset:], uint32(right))
			expected[index].Attributes[slot].Value = value
		}
	}
	return expected, nil
}

func TestLinuxTUNRouteAgingRetainsAllConfigurationFields(t *testing.T) {
	cache := make([]byte, 32)
	binary.NativeEndian.PutUint32(cache[8:], 10000)
	before := []linuxnet.Route{{Priority: 100, Attributes: []linuxnet.Attribute{{Type: 12, Value: cache}}}}
	for _, scenario := range []string{"natural-aging", "expired-too-fast", "lifetime-reset", "other-cache-field", "priority", "additional-route"} {
		t.Run(scenario, func(t *testing.T) {
			value := append([]byte(nil), cache...)
			binary.NativeEndian.PutUint32(value[8:], 9500)
			after := []linuxnet.Route{{Priority: 100, Attributes: []linuxnet.Attribute{{Type: 12, Value: value}}}}
			switch scenario {
			case "expired-too-fast":
				binary.NativeEndian.PutUint32(value[8:], 9000)
			case "lifetime-reset":
				binary.NativeEndian.PutUint32(value[8:], 11000)
			case "other-cache-field":
				value[0] = 1
			case "priority":
				after[0].Priority = 101
			case "additional-route":
				after = append(after, after[0])
			}
			expected, err := expectedSystemdRouteAging(before, after, 4990*time.Millisecond, 5010*time.Millisecond)
			accepted := err == nil && reflect.DeepEqual(expected, after)
			if accepted != (scenario == "natural-aging") {
				t.Fatal("network comparison accepted a change or rejected measured natural aging", err)
			}
			if binary.NativeEndian.Uint32(cache[8:]) != 10000 {
				t.Fatal("comparison modified the original baseline")
			}
		})
	}
}

func TestRealSystemdTUNLogClientFixture(t *testing.T) {
	scenario := os.Getenv("RAINLINK_TEST_SYSTEMD_LOG_CLIENT")
	if scenario == "" {
		t.Skip("ordinary client inside disposable systemd VM only")
	}
	if os.Geteuid() != 65534 {
		t.Fatal("VM client requires an ordinary UID")
	}
	ctx, cancel := context.WithTimeout(t.Context(), 70*time.Second)
	defer cancel()
	node := mobileNode("systemd-logs", "http")
	node.Server, node.Port = "192.0.2.1", 9
	settings := defaultRuntimeSettings()
	settings.LogLevel = "debug"
	request := MobileRequest{Node: &node, Mode: "global", TUN: true, RuntimeSettings: &settings,
		Secrets: map[string]MobileCredentials{node.Credential: {Username: "fixture-systemd-user", Password: "fixture-systemd-password"}}}
	logs := newLogBuffer()
	client, err := dialLinuxTUNClientWithLogs(ctx, installedTUNSocket, request, logs)
	if scenario == "deny" {
		requireTUNFailure(t, err, "tun_permission_denied")
		if !strings.Contains(strings.Join(collectPermissionLogMessages(logs), " "), "系统授权已取消") {
			t.Fatal("actual polkit refusal did not deliver private failure diagnostics")
		}
	} else {
		if err != nil {
			t.Fatal(err)
		}
		defer client.close()
		for deadline := time.Now().Add(5 * time.Second); ; {
			messages := strings.Join(collectPermissionLogMessages(logs), " ")
			if strings.Contains(messages, "sing-box started") && strings.Contains(messages, "inbound/tun") {
				break
			}
			if time.Now().After(deadline) {
				t.Fatal("actual core output did not cross the root private channel")
			}
			time.Sleep(20 * time.Millisecond)
		}
		if err := client.stop(ctx); err != nil {
			t.Fatal(err)
		}
		if !strings.Contains(strings.Join(collectPermissionLogMessages(logs), " "), "网络资源已恢复") {
			t.Fatal("stop receipt preceded final cleanup logs")
		}
	}
	messages := collectPermissionLogMessages(logs)
	data, err := json.Marshal(map[string]any{"scenario": scenario, "messages": messages})
	if err != nil || strings.Contains(string(data), "fixture-systemd-password") || strings.Contains(string(data), "fixture-systemd-user") {
		t.Fatal("private data crossed public log boundary", err)
	}
	fmt.Println(string(data))
}
