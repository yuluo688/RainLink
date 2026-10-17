//go:build linux && !android

package linuxnet

import (
	"context"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	"golang.org/x/sys/unix"
)

func TestReadKernelNetworkStateWithoutPrivileges(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("run as an ordinary user to verify read-only netlink access")
	}
	ctx, cancel := context.WithTimeout(t.Context(), time.Second)
	defer cancel()
	state, err := Read(ctx)
	if err != nil {
		t.Fatal("ordinary user could not read kernel network state", err)
	}
	devices, err := net.Interfaces()
	if err != nil {
		t.Fatal(err)
	}
	if len(state.Links) != len(devices) || len(state.Links) == 0 {
		t.Fatal("link dump incomplete")
	}
	for _, device := range devices {
		found := false
		for _, link := range state.Links {
			found = found || link.Index == uint32(device.Index) && link.Name == device.Name
		}
		if !found {
			t.Fatal("link identity differs from the standard library")
		}
	}
	var local4, local6 bool
	for _, rule := range state.Rules {
		if rule.Priority == 0 && rule.Table == unix.RT_TABLE_LOCAL && rule.Action == unix.FR_ACT_TO_TBL {
			local4 = local4 || rule.Family == unix.AF_INET
			local6 = local6 || rule.Family == unix.AF_INET6
		}
	}
	if !local4 || !local6 {
		t.Fatal("dual-stack priority-zero rules missing")
	}
}

func requireNetworkFixture(t *testing.T) string {
	t.Helper()
	if os.Getenv("RAINLINK_TEST_NETWORK_NAMESPACE") != "isolated" {
		t.Skip("requires an explicitly isolated network namespace")
	}
	parent := os.Getenv("RAINLINK_TEST_PARENT_NETNS")
	current, err := os.Readlink("/proc/self/ns/net")
	if err != nil || parent == "" || current == parent {
		t.Fatal("network test is not isolated from its parent", err)
	}
	return os.Getenv("RAINLINK_TEST_NETWORK_STAGE")
}

func TestIsolatedKernelRoutesRulesAndInterfaceRemoval(t *testing.T) {
	stage := requireNetworkFixture(t)
	if os.Geteuid() == 0 {
		t.Fatal("network observation fixture must run as an ordinary user")
	}
	state, err := Read(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	if name, err := SelectUpstream(state.Links, state.Routes, false); err != nil || name != "uplink0" {
		t.Fatal("real IPv4 route selected the lower-metric tunnel instead of the uplink", name, err)
	}
	if name, err := SelectUpstream(state.Links, state.Routes, true); err != nil || name != "backup0" {
		t.Fatal("IPv6 did not use its separate default route", name, err)
	}
	var tunExists bool
	for _, link := range state.Links {
		if link.Name == "rl-fixture" {
			if link.Kind != "tun" || !link.Up() {
				t.Fatal("TUN was not identified by kernel kind/readiness")
			}
			tunExists = true
		}
	}
	var route4, route6, rule4, rule6 bool
	for _, route := range state.Routes {
		if route.Table == 100001 && route.Destination.Bits() == 0 {
			route4 = route4 || route.Family == unix.AF_INET
			route6 = route6 || route.Family == unix.AF_INET6
		}
	}
	for _, rule := range state.Rules {
		if rule.Priority == 30000 && rule.Table == 100001 {
			rule4 = rule4 || rule.Family == unix.AF_INET
			rule6 = rule6 || rule.Family == unix.AF_INET6
		}
	}
	if !rule4 || !rule6 {
		t.Fatal("extended-table policy rules not read for both families")
	}
	switch stage {
	case "attached":
		if !tunExists || !route4 || !route6 {
			t.Fatal("real TUN routes missing from the extended table")
		}
	case "removed":
		if tunExists || route4 || route6 {
			t.Fatal("deleted TUN or its interface-bound routes remained")
		}
		// These rules survive interface removal. An observer that only checks
		// whether the adapter disappeared would falsely report full recovery.
	default:
		t.Fatal("unknown network fixture stage")
	}
	if directory := os.Getenv("RAINLINK_TEST_NETWORK_EVIDENCE_DIR"); directory != "" {
		data, err := json.MarshalIndent(state, "", "  ")
		if err != nil {
			t.Fatal(err)
		}
		if err = os.WriteFile(filepath.Join(directory, "kernel-"+stage+".json"), append(data, '\n'), 0600); err != nil {
			t.Fatal(err)
		}
	}
}
