package session

import (
	"context"
	"encoding/json"
	"errors"
	"net/netip"
	"os/exec"
	"runtime"
	"strings"
	"testing"
)

func TestUpstreamAddressPolicy(t *testing.T) {
	for _, tc := range []struct {
		name              string
		addresses         []string
		local, fake, ipv6 bool
	}{
		{name: "loopback", addresses: []string{"127.0.0.1", "::1"}, local: true},
		{name: "private", addresses: []string{"192.168.1.2", "fd00::1"}, local: true},
		{name: "link local", addresses: []string{"fe80::1"}, local: true, ipv6: true},
		{name: "public IPv4", addresses: []string{"8.8.8.8"}},
		{name: "public IPv6", addresses: []string{"2606:4700:4700::1111"}, ipv6: true},
		{name: "fake start", addresses: []string{"198.18.0.0"}, fake: true},
		{name: "fake end", addresses: []string{"198.19.255.255"}, fake: true},
		{name: "outside fake range", addresses: []string{"198.20.0.1"}},
		{name: "mapped fake", addresses: []string{"::ffff:198.18.0.2"}, fake: true},
		{name: "mixed answers", addresses: []string{"8.8.8.8", "198.18.0.2"}, fake: true},
		{name: "private and fake", addresses: []string{"192.168.1.2", "198.18.0.2"}, fake: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var addresses []netip.Addr
			for _, value := range tc.addresses {
				addresses = append(addresses, netip.MustParseAddr(value))
			}
			local, fake, ipv6 := upstreamAddressPolicy(addresses)
			if local != tc.local || fake != tc.fake || ipv6 != tc.ipv6 {
				t.Fatalf("got local=%v fake=%v ipv6=%v", local, fake, ipv6)
			}
		})
	}
}

func TestPrepareUpstreamPreservesLocalRoutesAndRejectsFakeLiteral(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("Windows upstream preparation")
	}
	for _, server := range []string{"127.0.0.1", "::1", "192.168.1.2", "fd00::1"} {
		network, err := prepareUpstream(context.Background(), Node{Protocol: "hysteria2", Server: server})
		if err != nil || network != (upstreamNetwork{}) {
			t.Fatalf("local upstream routes were overridden: %v", err)
		}
	}
	for _, server := range []string{"198.18.0.2", "::ffff:198.19.0.2"} {
		_, err := prepareUpstream(context.Background(), Node{Protocol: "hysteria2", Server: server})
		var public *Failure
		if !errors.As(err, &public) || public.Code != "invalid_server_address" || strings.Contains(public.Message, server) {
			t.Fatal("a temporary fake address must fail with a redacted actionable error")
		}
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err := prepareUpstream(ctx, Node{Protocol: "hysteria2", Server: "example.test"})
	var public *Failure
	if !errors.As(err, &public) || public.Code != "cancelled" {
		t.Fatal("cancelled connection started network preparation")
	}
	// The fix is scoped to QUIC upstreams; existing TCP/proxy behavior stays intact.
	network, err := prepareUpstream(context.Background(), Node{Protocol: "http", Server: "example.test"})
	if err != nil || network != (upstreamNetwork{}) {
		t.Fatal("unrelated protocols acquired a network override")
	}
}

func TestHysteria2UpstreamConfigurationIsolation(t *testing.T) {
	node := Node{ID: "upstream-test", Name: "HY2", Revision: 1, Protocol: "hysteria2", Server: "edge.example.test", Port: 443, TLS: true,
		Options: NodeOptions{Transport: "quic", CertificateSHA256: strings.Repeat("ab", 32), ServerPorts: []string{"20000:30000"}}}
	network := upstreamNetwork{InterfaceName: "fixture-interface", EncryptedDNS: true}
	data, err := configuration(node, credentials{Password: "fixture-password"}, "global", 19080, 19090, "fixture-api", network)
	if err != nil {
		t.Fatal(err)
	}
	var config struct {
		DNS struct {
			Servers []map[string]any `json:"servers"`
			Final   string           `json:"final"`
		} `json:"dns"`
		Route     map[string]any   `json:"route"`
		Outbounds []map[string]any `json:"outbounds"`
	}
	if err = json.Unmarshal(data, &config); err != nil {
		t.Fatal(err)
	}
	out := config.Outbounds[0]
	if out["bind_interface"] != network.InterfaceName || out["server"] != node.Server || out["password"] != "fixture-password" {
		t.Fatal("upstream binding changed the server or authentication")
	}
	if out["tls"].(map[string]any)["rainlink_certificate_sha256"] != node.Options.CertificateSHA256 || len(out["server_ports"].([]any)) != 1 {
		t.Fatal("upstream fix dropped certificate verification or port hopping")
	}
	if out["domain_resolver"].(map[string]any)["server"] != upstreamDNSTag {
		t.Fatal("fake-IP lookup did not use the isolated resolver")
	}
	if len(config.DNS.Servers) != 2 || config.DNS.Final != "local-dns" || config.Route["default_domain_resolver"] != "local-dns" || config.Route["default_interface"] != nil {
		t.Fatal("upstream policy replaced global routing or the system resolver")
	}
	resolver := config.DNS.Servers[1]
	if resolver["type"] != "https" || resolver["bind_interface"] != network.InterfaceName || resolver["server"] != upstreamDNSServer || resolver["tls"].(map[string]any)["server_name"] != upstreamDNSServerName {
		t.Fatal("encrypted resolver does not share the upstream interface and verified TLS")
	}
	if len(config.Outbounds[1]) != 2 || config.Outbounds[1]["type"] != "direct" {
		t.Fatal("direct outbound acquired upstream-only options")
	}
	path := testCore(t)
	cmd := exec.Command(path, "check", "-c", "stdin")
	hideWindow(cmd)
	cmd.Stdin = strings.NewReader(string(data))
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("real core rejected upstream DNS configuration: %v, %s", err, output)
	}
}
