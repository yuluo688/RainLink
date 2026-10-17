package session

import (
	"bytes"
	"context"
	"encoding/json"
	"os/exec"
	"runtime"
	"strings"
	"testing"
)

func TestTUNCompilerProtectsUpstreamAndInterceptsDNSBeforeUserModes(t *testing.T) {
	primary := preparedOutbound{RoutingOutbound: RoutingOutbound{Node: Node{
		ID: "tun-check", Name: "配置校验", Revision: 1, Protocol: "http", Server: "127.0.0.1", Port: 9,
	}}}
	settings := defaultRuntimeSettings()
	settings.DNSMode = "encrypted"
	raw, err := targetConfiguration(primary, "global", 17890, 17891, "fixture", nil, nil, settings)
	if err != nil {
		t.Fatal(err)
	}
	raw, err = configureTUN(raw, tunPlan{Name: newTUNInterfaceName(), Upstream: "fixture-physical"})
	if err != nil {
		t.Fatal(err)
	}
	var config map[string]any
	if err = json.Unmarshal(raw, &config); err != nil {
		t.Fatal(err)
	}
	inbounds := config["inbounds"].([]any)
	if len(inbounds) != 2 || inbounds[0].(map[string]any)["type"] != "mixed" {
		t.Fatal("mixed proxy was replaced")
	}
	tun := inbounds[1].(map[string]any)
	if tun["auto_route"] != true || tun["strict_route"] != true || len(tun["address"].([]any)) != 2 {
		t.Fatal("TUN must capture both address families")
	}
	route := config["route"].(map[string]any)
	if route["default_interface"] != "fixture-physical" {
		t.Fatal("default egress can loop into TUN")
	}
	rules := route["rules"].([]any)
	if rules[0].(map[string]any)["action"] != "hijack-dns" || rules[1].(map[string]any)["clash_mode"] != "direct" {
		t.Fatal("DNS capture follows user mode rules")
	}
	for _, rawOutbound := range config["outbounds"].([]any) {
		if rawOutbound.(map[string]any)["bind_interface"] != "fixture-physical" {
			t.Fatal("unprotected root outbound")
		}
	}
	for _, rawDNS := range config["dns"].(map[string]any)["servers"].([]any) {
		dns := rawDNS.(map[string]any)
		if dns["type"] != "local" && dns["bind_interface"] != "fixture-physical" {
			t.Fatal("unprotected DNS socket")
		}
	}
	path := testCore(t)
	check := exec.Command(path, "check", "-c", "stdin")
	hideWindow(check)
	check.Stdin = bytes.NewReader(raw)
	if err = check.Run(); err != nil {
		t.Fatal("real core rejected TUN configuration:", err)
	}
}

func TestTUNInterfaceNameFitsPlatformAndDoesNotRepeat(t *testing.T) {
	seen := make(map[string]bool)
	prefix := tunInterfacePrefix
	if runtime.GOOS == "linux" {
		prefix = "rl-"
	}
	for range 100 {
		name := newTUNInterfaceName()
		if !strings.HasPrefix(name, prefix) || len(name) != len(prefix)+8 || seen[name] {
			t.Fatal("invalid or repeated TUN interface name")
		}
		if runtime.GOOS == "linux" && len(name) > 15 {
			t.Fatal("TUN interface name exceeds IFNAMSIZ")
		}
		if runtime.GOOS == "linux" && strings.ToLower(name) != name {
			t.Fatal("TUN interface name cannot be reserved by the Linux lease allocator")
		}
		seen[name] = true
	}
}

func TestCancelledTUNPlanDoesNotInspectNetwork(t *testing.T) {
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	_, err := newTUNPlan(ctx)
	public, ok := err.(*Failure)
	if !ok || public.Code != "cancelled" {
		t.Fatal("cancelled TUN plan inspected network or returned an unrelated error", err)
	}
}

func TestIsolatedDiagnosticsCannotStartTUNCapture(t *testing.T) {
	manager := New("not-used", t.TempDir())
	manager.isolated = true
	_, err := manager.connectTargetCapture(context.Background(), Node{
		ID: "test", Name: "test", Revision: 1, Protocol: "http", Server: "127.0.0.1", Port: 9,
	}, nil, "global", false, true, nil, false)
	public, ok := err.(*Failure)
	if !ok || public.Code != "isolated_probe" || manager.active != nil {
		t.Fatal("isolated diagnostic obtained TUN capture", err)
	}
}
