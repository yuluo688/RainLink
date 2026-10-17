package session

import (
	"encoding/json"
	"os/exec"
	"strings"
	"testing"
)

func TestHysteria2Configuration(t *testing.T) {
	node := Node{ID: "hy2-test", Name: "Hysteria2", Revision: 1, Protocol: "hysteria2", Server: "example.test", Port: 443, TLS: true,
		Options: NodeOptions{Transport: "quic", Obfs: "salamander", UpMbps: 100, DownMbps: 250, ServerPorts: []string{"20000:30000", "443"}, HopIntervalSeconds: 30, ServerName: "edge.example.test", ALPN: []string{"h3"}}}
	if err := node.validate(); err != nil {
		t.Fatal(err)
	}
	data, err := configuration(node, credentials{Password: "fixture-auth", ObfsPassword: "fixture-obfs"}, "global", 19080, 19090, "fixture-api", upstreamNetwork{})
	if err != nil {
		t.Fatal(err)
	}
	var config struct {
		Outbounds []map[string]any `json:"outbounds"`
	}
	if err := json.Unmarshal(data, &config); err != nil {
		t.Fatal(err)
	}
	out := config.Outbounds[0]
	if out["type"] != "hysteria2" || out["password"] != "fixture-auth" || out["up_mbps"] != float64(100) || out["down_mbps"] != float64(250) || out["hop_interval"] != "30s" || out["obfs"].(map[string]any)["password"] != "fixture-obfs" {
		t.Fatal("Hysteria2 configuration lost authentication or QUIC parameters")
	}
	for _, change := range []func(*Node){
		func(n *Node) { n.TLS = false },
		func(n *Node) { n.Options.Transport = "ws" },
		func(n *Node) { n.Options.Obfs = "unknown" },
		func(n *Node) { n.Options.Fingerprint = "chrome" },
		func(n *Node) { n.Options.CertificateSHA256 = "invalid-pin" },
		func(n *Node) { n.Options.UpMbps = -1 },
		func(n *Node) { n.Options.ServerPorts = []string{"65536"} },
		func(n *Node) { n.Options.ServerPorts = []string{"30000:20000"} },
		func(n *Node) { n.Options.HopIntervalSeconds = 1 },
	} {
		invalid := node
		change(&invalid)
		if err := invalid.validate(); err == nil {
			t.Fatal("invalid Hysteria2 settings accepted")
		}
	}
	if _, err := configuration(node, credentials{Password: "fixture-auth"}, "global", 19080, 19090, "fixture-api", upstreamNetwork{}); err == nil {
		t.Fatal("missing obfuscation password accepted")
	}
}

func TestCoreChecksHysteria2PortHoppingConfiguration(t *testing.T) {
	path := testCore(t)
	node := Node{ID: "hy2-check", Name: "HY2 ports", Revision: 1, Protocol: "hysteria2", Server: "example.test", Port: 443, TLS: true,
		Options: NodeOptions{Transport: "quic", Obfs: "salamander", ServerPorts: []string{"20000:30000", "443"}, HopIntervalSeconds: 30, CertificateSHA256: strings.Repeat("ab", 32)}}
	data, err := configuration(node, credentials{Password: "fixture-auth", ObfsPassword: "fixture-obfs"}, "global", 19080, 19090, "fixture-api", upstreamNetwork{})
	if err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(path, "check", "-c", "stdin")
	hideWindow(cmd)
	cmd.Stdin = strings.NewReader(string(data))
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("core rejected Hysteria2: %v, %s", err, output)
	}
}
