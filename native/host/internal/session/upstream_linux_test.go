//go:build linux && !android

package session

import (
	"os"
	"strings"
	"testing"

	"rainlink.local/host/internal/linuxtun"
)

func TestLinuxTUNPlanUsesRealKernelUpstream(t *testing.T) {
	if os.Getenv("RAINLINK_TEST_NETWORK_NAMESPACE") != "isolated" {
		t.Skip("requires the isolated Linux network fixture")
	}
	parent := os.Getenv("RAINLINK_TEST_PARENT_NETNS")
	current, err := os.Readlink("/proc/self/ns/net")
	if err != nil || parent == "" || current == parent || os.Geteuid() == 0 {
		t.Fatal("TUN planning fixture must be isolated and unprivileged", err)
	}
	plan, err := newTUNPlan(t.Context())
	if err != nil || plan.Upstream != "uplink0" || !strings.HasPrefix(plan.Name, "rl-") || len(plan.Name) > 15 {
		t.Fatal("TUN planning did not use the actual uplink and a Linux-sized name", plan, err)
	}
	if _, err = (linuxtun.Specification{Name: plan.Name, Table: 100002, Priority: 16016}).ExpectedRules(); err != nil {
		t.Fatal("generated TUN name is incompatible with the Linux resource lease", err)
	}
	if name, err := defaultUpstreamInterface(t.Context(), true); err != nil || name != "backup0" {
		t.Fatal("IPv6 upstream did not use the independent kernel route", name, err)
	}
}
