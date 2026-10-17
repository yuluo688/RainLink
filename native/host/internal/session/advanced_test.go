package session

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

const advancedFixture = `{
	"log":{"level":"debug","timestamp":true},
	"dns":{
		"servers":[
			{"type":"https","tag":"secure","server":"dns.example.test","path":"/dns-query","tls":{"enabled":true,"server_name":"dns.example.test"}},
			{"type":"udp","server":"127.0.0.1","server_port":15353},
			{"type":"tls","server":"1.1.1.1"},
			{"type":"tcp","server":"127.0.0.1"},
			{"type":"local"}
		],
		"final":"secure","strategy":"prefer_ipv4","disable_cache":false,"disable_expire":false,"independent_cache":true,"cache_capacity":4096,
		"rules":[{"domain_suffix":["example.com"],"server":"system"},{"domain":["blocked.test"],"action":"reject"},{"domain_keyword":["internal"],"server":"default"}]
	},
	"route":{"rules":[
		{"domain_suffix":["example.net"],"outbound":"direct"},
		{"ip_cidr":["192.0.2.0/24"],"port":[80,443],"network":["tcp"],"action":"route","outbound":"proxy"},
		{"ip_is_private":true,"action":"reject"}
	]}
}`

func TestAdvancedMergeChecksBundledCoreAndProtectsCapture(t *testing.T) {
	manager := New(testCore(t), t.TempDir())
	settings := defaultRuntimeSettings()
	settings.Advanced = advancedFixture
	if err := manager.ValidateRuntime(context.Background(), settings); err != nil {
		t.Fatal(err)
	}
	primary := preparedOutbound{RoutingOutbound: RoutingOutbound{Node: Node{Protocol: "http", Server: "127.0.0.1", Port: 9}}}
	raw, err := targetConfiguration(primary, "rule", 17890, 17891, "fixture-secret", nil, nil, settings)
	if err != nil {
		t.Fatal(err)
	}
	var config map[string]any
	if err := json.Unmarshal(raw, &config); err != nil {
		t.Fatal(err)
	}
	dns := config["dns"].(map[string]any)
	route := config["route"].(map[string]any)
	rules := route["rules"].([]any)
	if rules[0].(map[string]any)["clash_mode"] != "direct" || rules[1].(map[string]any)["clash_mode"] != "global" || rules[2].(map[string]any)["outbound"] != "direct" || len(rules) != 7 {
		t.Fatal("mode or managed-rule precedence changed")
	}
	if dns["final"] != "advanced-dns-secure" || route["default_domain_resolver"] != dns["final"] || dns["cache_capacity"] != float64(4096) {
		t.Fatal("advanced DNS not applied")
	}
	if config["log"].(map[string]any)["level"] != "debug" || config["log"].(map[string]any)["timestamp"] != true {
		t.Fatal("advanced log settings not applied")
	}
	if config["inbounds"].([]any)[0].(map[string]any)["listen"] != "127.0.0.1" || config["experimental"].(map[string]any)["clash_api"].(map[string]any)["secret"] != "fixture-secret" {
		t.Fatal("controlled listeners or authentication were changed")
	}
	tunRaw, err := configureTUN(raw, tunPlan{Name: "RainLink-fixture", Upstream: "fixture-upstream"})
	if err != nil || json.Unmarshal(tunRaw, &config) != nil {
		t.Fatal(err)
	}
	route = config["route"].(map[string]any)
	if route["rules"].([]any)[0].(map[string]any)["action"] != "hijack-dns" {
		t.Fatal("advanced rules displaced TUN DNS interception")
	}
	for _, raw := range config["dns"].(map[string]any)["servers"].([]any) {
		server := raw.(map[string]any)
		if server["type"] != "local" && server["bind_interface"] != "fixture-upstream" {
			t.Fatal("advanced DNS can recurse into TUN")
		}
	}
	if manager.active != nil {
		t.Fatal("configuration check started an interactive session")
	}
}

func TestAdvancedRejectsUnknownSecretsAndInvalidPolicies(t *testing.T) {
	for _, raw := range []string{
		`{"outbounds":[{"password":"fixture-secret"}]}`,
		`{"inbounds":[{"listen":"0.0.0.0"}]}`,
		`{"experimental":{"clash_api":{"secret":"fixture-secret"}}}`,
		`{"log":{"output":"fixture-secret"}}`,
		`{"dns":{"servers":[{"type":"https","server":"user:fixture-secret@example.test"}]}}`,
		`{"dns":{"servers":[{"type":"https","server":"dns.example.test","path":"/dns-query?token=fixture-secret"}]}}`,
		`{"dns":{"servers":[{"type":"https","server":"dns.example.test","tls":{"insecure":true}}]}}`,
		`{"dns":{"servers":[{"type":"https","server":"dns.example.test","tls":{"enabled":false}}]}}`,
		`{"dns":{"servers":[{"type":"https","server":"dns.example.test","detour":"proxy"}]}}`,
		`{"dns":{"servers":[{"type":"https","server":"dns.example.test","tag":"system"}]}}`,
		`{"dns":{"servers":[{"type":"local","tag":"same"},{"type":"local","tag":"same"}]}}`,
		`{"dns":{"servers":[{"type":"local","server":"127.0.0.1"}]}}`,
		`{"dns":{"servers":[{"type":"fakeip"}]}}`,
		`{"dns":{"servers":[{"type":"udp","server":"127.0.0.1","server_port":65536}]}}`,
		`{"dns":{"final":"missing"}}`,
		`{"dns":{"rules":[{"domain":["example.com"],"server":"missing"}]}}`,
		`{"dns":{"rules":[{"server":"system"}]}}`,
		`{"dns":{"rules":[{"domain":["example.com"],"action":"reject","server":"system"}]}}`,
		`{"dns":{"cache_capacity":65537}}`,
		`{"dns":{"strategy":"auto"}}`,
		`{"route":{"final":"direct"}}`,
		`{"route":{"rules":[{"outbound":"direct"}]}}`,
		`{"route":{"rules":[{"domain_suffix":["example.com"],"outbound":"group:arbitrary"}]}}`,
		`{"route":{"rules":[{"domain_suffix":["example.com"],"action":"reject","outbound":"proxy"}]}}`,
		`{"route":{"rules":[{"network":["icmp"],"outbound":"direct"}]}}`,
		`{"route":{"rules":[{"ip_cidr":["not-a-prefix"],"outbound":"direct"}]}}`,
		`{"route":{"rules":[{"port":[0],"outbound":"direct"}]}}`,
		`{"route":{"rules":[{"ip_is_private":false,"outbound":"direct"}]}}`,
		`{"log":{},"log":{"level":"fixture-secret"}}`,
		`{"log":{"level":"info","level":"fixture-secret"}}`,
		`{"log":null}`, `{"log":{"timestamp":null}}`, `{"dns":{"rules":null}}`, `{"log":[]} `,
		`{"log":{"LEVEL":"debug"}}`, `{"DNS":{"strategy":"prefer_ipv6"}}`,
		`{} {}`, `null`, `[]`, `{"log":{"level":"trace"}}`,
		`{"route":{"rules":` + strings.Repeat("[", 20) + `1` + strings.Repeat("]", 20) + `}}`,
		`{"log":{"level":"` + strings.Repeat("x", maxAdvancedBytes) + `"}}`,
	} {
		if _, err := parseAdvanced(raw, "223.5.5.5"); err == nil {
			t.Fatalf("invalid patch accepted: %.70s", raw)
		} else if strings.Contains(err.Error(), "fixture-secret") {
			t.Fatal("configuration input leaked in a diagnostic")
		}
	}
}

func TestAdvancedActualDNSRouteAndLiveModes(t *testing.T) {
	core := testCore(t)
	var queries atomic.Int32
	dns, err := net.ListenPacket("udp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer dns.Close()
	done := make(chan struct{})
	go func() {
		defer close(done)
		buffer := make([]byte, 4096)
		for {
			count, address, err := dns.ReadFrom(buffer)
			if err != nil {
				return
			}
			answer := dnsFixtureAnswer(buffer[:count])
			copy(answer[len(answer)-4:], []byte{127, 0, 0, 1})
			queries.Add(1)
			dns.WriteTo(answer, address)
		}
	}()
	defer func() { dns.Close(); <-done }()
	calls := &chainRecorder{}
	node := chainProxyFixture(t, "advanced-upstream", calls, false)
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "advanced-origin") }))
	defer origin.Close()
	originURL, _ := url.Parse(origin.URL)
	settings := defaultRuntimeSettings()
	settings.Advanced = fmt.Sprintf(`{"dns":{"servers":[{"type":"udp","server":"127.0.0.1","server_port":%d}],"disable_cache":true},"route":{"rules":[{"domain":["route.advanced.test"],"outbound":"direct"},{"domain":["blocked.advanced.test"],"action":"reject"}]}}`, dns.LocalAddr().(*net.UDPAddr).Port)
	manager := New(core, t.TempDir())
	defer manager.Disconnect()
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	plan := &RoutingPlan{Revision: 1, Rules: []RouteRule{
		{ID: "local", Type: "IP-CIDR", Value: "127.0.0.0/8", Target: "direct", Enabled: true}, fallbackRule("proxy"),
	}}
	snapshot, err := manager.connectTarget(ctx, node, nil, "rule", false, plan, false, settings)
	if err != nil {
		t.Fatal(err)
	}
	proxy, _ := url.Parse("http://127.0.0.1:" + strconv.Itoa(snapshot.ProxyPort))
	transport := &http.Transport{Proxy: http.ProxyURL(proxy), DisableKeepAlives: true}
	defer transport.CloseIdleConnections()
	client := &http.Client{Timeout: 3 * time.Second, Transport: transport}
	get := func(address string) bool {
		response, err := client.Get(address)
		if err != nil {
			return false
		}
		defer response.Body.Close()
		body, err := io.ReadAll(response.Body)
		return err == nil && string(body) == "advanced-origin"
	}
	address := "http://route.advanced.test:" + originURL.Port()
	if !get(address) || queries.Load() == 0 || len(calls.take()) != 0 {
		t.Fatal("advanced DNS or direct route did not carry the actual request")
	}
	if get("http://blocked.advanced.test:"+originURL.Port()) || len(calls.take()) != 0 {
		t.Fatal("advanced reject rule was bypassed")
	}
	if err := manager.SetMode(ctx, "global"); err != nil || !get(origin.URL) || len(calls.take()) != 1 {
		t.Fatal("global mode lost precedence", err)
	}
	if err := manager.SetMode(ctx, "direct"); err != nil || !get("http://blocked.advanced.test:"+originURL.Port()) || len(calls.take()) != 0 {
		t.Fatal("direct mode lost precedence", err)
	}
	rejected := settings
	rejected.Advanced = `{"inbounds":[]}`
	if manager.ValidateRuntime(ctx, rejected) == nil || manager.active.snapshot.SessionID != snapshot.SessionID || !get(address) {
		t.Fatal("rejected configuration interrupted the active session")
	}
}
