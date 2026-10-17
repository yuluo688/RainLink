package session

import (
	"encoding/json"
	"strings"
	"testing"
)

func mobileNode(id, protocol string) Node {
	node := Node{ID: id, Name: id, Revision: 1, Protocol: protocol, Server: "proxy.example", Port: 443,
		TLS:        protocol == "trojan" || protocol == "hysteria2" || protocol == "tuic",
		Credential: "cipher-" + id,
		Options:    NodeOptions{Method: "aes-128-gcm", Transport: "tcp", VMessSecurity: "auto", CongestionControl: "cubic", UDPRelayMode: "native", HeartbeatMillis: 10000}}
	if node.usesQUIC() {
		node.Options.Transport = "quic"
	}
	return node
}

func compileMobileFixture(t *testing.T, request MobileRequest) MobileConfiguration {
	t.Helper()
	raw, err := json.Marshal(request)
	if err != nil {
		t.Fatal(err)
	}
	result, err := CompileMobile(raw, request.TUN)
	if err != nil {
		t.Fatal(err)
	}
	return result
}

func TestMobileCompilerEightProtocolsAndPrivateSecrets(t *testing.T) {
	for _, protocol := range []string{"http", "socks", "shadowsocks", "vless", "vmess", "trojan", "hysteria2", "tuic"} {
		t.Run(protocol, func(t *testing.T) {
			node := mobileNode("fixture", protocol)
			secret := MobileCredentials{Password: "fixture-password"}
			if protocol == "vless" || protocol == "vmess" {
				secret.Password = "0f390f79-2673-4e24-95da-09a039352b3a"
			}
			if protocol == "tuic" {
				secret.Username = "0f390f79-2673-4e24-95da-09a039352b3a"
			}
			result := compileMobileFixture(t, MobileRequest{Node: &node, Mode: "global", TUN: true,
				Secrets: map[string]MobileCredentials{node.Credential: secret}})
			if !strings.Contains(result.Configuration, secret.Password) {
				t.Fatal("credential not compiled")
			}
			public, _ := json.Marshal(result.Snapshot)
			for _, private := range []string{secret.Password, node.Credential, node.Server, result.APISecret} {
				if strings.Contains(string(public), private) {
					t.Fatal("secret or upstream leaked through public snapshot")
				}
			}
			if result.Snapshot.Target.ID != node.ID || !result.Snapshot.TUN || result.Snapshot.SystemProxy {
				t.Fatal("incorrect applied state")
			}
		})
	}
}

func TestMobileTunnelCapturesBothFamiliesAndInterceptsDNSBeforeModes(t *testing.T) {
	node := mobileNode("entry", "http")
	result := compileMobileFixture(t, MobileRequest{Node: &node, Mode: "direct", TUN: true,
		Secrets: map[string]MobileCredentials{node.Credential: {}}})
	var config struct {
		Inbounds []struct {
			Type    string   `json:"type"`
			Listen  string   `json:"listen"`
			Address []string `json:"address"`
		} `json:"inbounds"`
		Route struct{ Rules []map[string]any } `json:"route"`
	}
	if err := json.Unmarshal([]byte(result.Configuration), &config); err != nil {
		t.Fatal(err)
	}
	if len(config.Inbounds) != 2 || config.Inbounds[0].Listen != "127.0.0.1" || len(config.Inbounds[1].Address) != 2 ||
		!strings.Contains(config.Inbounds[1].Address[1], ":") || config.Route.Rules[1]["action"] != "hijack-dns" ||
		config.Route.Rules[2]["clash_mode"] != "direct" {
		t.Fatal("capture or DNS ordering changed")
	}
}

func TestMobileNodeBindingsMatchDesktopAndLogsRedactCompiledSecrets(t *testing.T) {
	node := mobileNode("entry", "http")
	secret := MobileCredentials{Username: "fixture-user", Password: "fixture-password"}
	result := compileMobileFixture(t, MobileRequest{Node: &node, Mode: "rule", TUN: true,
		Secrets: map[string]MobileCredentials{node.Credential: secret},
		Routing: &RoutingPlan{Revision: 7, Rules: []RouteRule{{ID: "final", Type: "MATCH", Target: "proxy", Enabled: true}}}})
	if len(result.Snapshot.RouteBindings) != 0 {
		t.Fatal("node identity is already in target; unexpected proxy rule binding")
	}
	if result.Snapshot.TUNInterface != "" {
		t.Fatal("compiler must not invent an observed tunnel interface")
	}
	logs := NewMobileLogs(result.SecretValues)
	logs.WriteLine("error " + secret.Username + " " + secret.Password + " " + result.APISecret)
	encoded, err := json.Marshal(logs.Read("", 0))
	if err != nil {
		t.Fatal(err)
	}
	for _, value := range []string{secret.Username, secret.Password, result.APISecret} {
		if strings.Contains(string(encoded), value) {
			t.Fatal("mobile log contains a secret")
		}
	}
	private, err := json.Marshal(result)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(private), "SecretValues") {
		t.Fatal("redaction inputs were serialized")
	}
}

func TestMobileChainAndRuleBindings(t *testing.T) {
	entry, exit := mobileNode("entry", "http"), mobileNode("exit", "vless")
	chain := ChainSnapshot{ID: "chain", Name: "代理链", Revision: 3, Hops: []Node{entry, exit}}
	route := mobileNode("route", "socks")
	request := MobileRequest{Chain: &chain, Mode: "rule", Routing: &RoutingPlan{Revision: 4,
		Rules: []RouteRule{{ID: "domain", Type: "DOMAIN", Value: "example.com", Target: "node:route", Enabled: true},
			{ID: "final", Type: "MATCH", Target: "proxy", Enabled: true}},
		Outbounds: []RoutingOutbound{{Key: "node:route", Name: "route", Node: route}}},
		Secrets: map[string]MobileCredentials{entry.Credential: {}, exit.Credential: {Password: "0f390f79-2673-4e24-95da-09a039352b3a"}, route.Credential: {}}}
	result := compileMobileFixture(t, request)
	if result.Snapshot.RuleRevision != 4 || result.Snapshot.RouteBindings["proxy/hop/0"].ID != "entry" ||
		result.Snapshot.RouteBindings["node:route"].ID != "route" || !strings.Contains(result.Configuration, `"detour":"proxy-hop-0"`) {
		t.Fatal("chain/rule identity or detour lost")
	}
	request.Chain.Hops[1] = mobileNode("quic", "hysteria2")
	raw, _ := json.Marshal(request)
	if _, err := CompileMobile(raw, false); err == nil {
		t.Fatal("HTTP followed by QUIC was accepted")
	}
}

func TestMobileRejectsMissingCredentialCaptureMismatchAndUntrustedInput(t *testing.T) {
	node := mobileNode("node", "trojan")
	for _, request := range []MobileRequest{
		{Node: &node, Mode: "global"},
		{Node: &node, Mode: "global", SystemProxy: true},
		{Node: &node, Mode: "invalid"},
		{Node: &node, Mode: "global", TUN: true},
	} {
		raw, _ := json.Marshal(request)
		if _, err := CompileMobile(raw, false); err == nil {
			t.Fatal("invalid input accepted")
		}
	}
	for _, raw := range []string{`{"unknown":"not allowed"}`, `{}`, `{} {}`, strings.Repeat("x", 4<<20+1)} {
		if _, err := CompileMobile([]byte(raw), false); err == nil {
			t.Fatal("untrusted input accepted")
		}
	}
}
