//go:build linux && !android

package session

import (
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"reflect"
	"strings"
	"testing"
	"time"

	"rainlink.local/host/internal/linuxipc"
	"rainlink.local/host/internal/linuxnet"
	"rainlink.local/host/internal/linuxtun"
	"rainlink.local/host/internal/tunconfig"
)

func linuxTUNRequest(t *testing.T) (MobileRequest, []byte) {
	t.Helper()
	node := mobileNode("entry", "http")
	settings := defaultRuntimeSettings()
	settings.DNSMode = "encrypted"
	request := MobileRequest{Node: &node, Mode: "rule", TUN: true, RuntimeSettings: &settings,
		Secrets: map[string]MobileCredentials{node.Credential: {Username: "fixture-user", Password: "fixture-secret"}}}
	raw, err := json.Marshal(request)
	if err != nil {
		t.Fatal(err)
	}
	return request, raw
}

func TestLinuxTUNCompilerRejectsUntrustedBoundary(t *testing.T) {
	_, valid := linuxTUNRequest(t)
	resources := linuxtun.Specification{Name: "rl-compiler", Table: 100002, Priority: 16016}
	cases := map[string][]byte{
		"null": []byte(`null`), "array": []byte(`[]`),
		"duplicate":        []byte(`{"tun":false,"tun":true}`),
		"case-alias":       []byte(`{"tun":true,"TUN":false}`),
		"unbounded":        []byte(strings.Repeat(" ", linuxipc.MaxMessageBytes+1)),
		"raw-core":         []byte(`{"inbounds":[],"outbounds":[]}`),
		"caller-resources": append(append([]byte{}, valid[:len(valid)-1]...), []byte(`,"resources":{"name":"eth0","table":254,"priority":1}}`)...),
		"tail":             append(append([]byte{}, valid...), []byte(` {}`)...),
		"missing-secret":   []byte(strings.Replace(string(valid), `"secrets":{`, `"secrets-missing":{`, 1)),
	}
	for name, raw := range cases {
		t.Run(name, func(t *testing.T) {
			result, err := CompileLinuxTUN(t.Context(), raw, resources)
			if err == nil || result.Configuration != "" {
				t.Fatal("untrusted request compiled")
			}
			if strings.Contains(err.Error(), "fixture-secret") {
				t.Fatal("invalid request exposed credentials")
			}
		})
	}
	for _, invalid := range []linuxtun.Specification{{}, {Name: "eth0", Table: 254, Priority: 1}, {Name: "rl-test", Table: 100002, Priority: 32756}} {
		if _, err := CompileLinuxTUN(t.Context(), valid, invalid); err == nil {
			t.Fatal("invalid helper lease compiled")
		}
	}
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	_, err := CompileLinuxTUN(ctx, valid, resources)
	failure, ok := err.(*Failure)
	if !ok || failure.Code != "cancelled" {
		t.Fatal("cancelled request reached network planning", err)
	}
}

func TestLinuxTUNCompilerUsesHeldResourcesAndPreservesKernelState(t *testing.T) {
	if os.Getenv("RAINLINK_TEST_NETWORK_NAMESPACE") != "isolated" {
		t.Skip("requires disposable network namespace")
	}
	parent := os.Getenv("RAINLINK_TEST_PARENT_NETNS")
	current, err := os.Readlink("/proc/self/ns/net")
	if err != nil || parent == "" || parent == current || os.Geteuid() == 0 {
		t.Fatal("compiler fixture must be isolated and ordinary-user", err)
	}
	before, err := linuxnet.Read(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	request, raw := linuxTUNRequest(t)
	resources := linuxtun.Specification{Name: "rl-compiler", Table: 100002, Priority: 16016}
	compiled, err := CompileLinuxTUN(t.Context(), raw, resources)
	if err != nil {
		t.Fatal(err)
	}
	var config map[string]any
	if err = json.Unmarshal([]byte(compiled.Configuration), &config); err != nil {
		t.Fatal(err)
	}
	inbounds := config["inbounds"].([]any)
	inbound := inbounds[len(inbounds)-1].(map[string]any)
	if inbound["rainlink_managed"] != true || inbound["interface_name"] != resources.Name ||
		inbound["iproute2_table_index"] != float64(resources.Table) || inbound["iproute2_rule_index"] != float64(resources.Priority) ||
		!reflect.DeepEqual(inbound["address"], []any{tunconfig.IPv4Address, tunconfig.IPv6Address}) {
		t.Fatal("compiled capture escaped the held resource specification")
	}
	if compiled.Snapshot.Phase != "connecting" || compiled.Snapshot.TUNInterface != resources.Name || !compiled.Snapshot.TUN ||
		compiled.Snapshot.SystemProxy || compiled.APIPort < 1024 || compiled.Snapshot.ProxyPort < 1024 {
		t.Fatal("compilation claimed observed connection or privileged port")
	}
	route := config["route"].(map[string]any)
	if route["default_interface"] != "uplink0" || route["rules"].([]any)[0].(map[string]any)["action"] != "hijack-dns" {
		t.Fatal("upstream or DNS interception lost")
	}
	for _, value := range config["outbounds"].([]any) {
		outbound := value.(map[string]any)
		if _, detoured := outbound["detour"]; !detoured && outbound["bind_interface"] != "uplink0" {
			t.Fatal("outbound can loop through capture")
		}
	}
	for _, value := range config["dns"].(map[string]any)["servers"].([]any) {
		server := value.(map[string]any)
		if server["type"] != "local" && server["bind_interface"] != "uplink0" {
			t.Fatal("resolver can loop through capture")
		}
	}
	public, err := json.Marshal(compiled.Snapshot)
	if err != nil {
		t.Fatal(err)
	}
	for _, secret := range []string{"fixture-secret", "fixture-user", request.Node.Server, request.Node.Credential, compiled.APISecret} {
		if strings.Contains(string(public), secret) {
			t.Fatal("public connection state exposed a private value")
		}
	}
	ctx, cancel := context.WithTimeout(t.Context(), 3*time.Second)
	check := exec.CommandContext(ctx, testCore(t), "check", "-c", "stdin")
	check.Stdin = strings.NewReader(compiled.Configuration)
	err = check.Run()
	cancel()
	if err != nil {
		t.Fatal("locked core rejected controlled Linux capture configuration", err)
	}
	request.RuntimeSettings.ProxyPort = 80
	raw, err = json.Marshal(request)
	if err != nil {
		t.Fatal(err)
	}
	if result, err := CompileLinuxTUN(t.Context(), raw, resources); err == nil || result.Configuration != "" {
		t.Fatal("root listener accepted privileged caller-supplied port")
	}
	after, err := linuxnet.Read(t.Context())
	if err != nil || !reflect.DeepEqual(before, after) {
		t.Fatal("compiler or core check changed kernel network state", err)
	}
}
