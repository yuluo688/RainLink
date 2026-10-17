package session

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func fallbackRule(target string) RouteRule {
	return RouteRule{ID: "fallback", Type: "MATCH", Target: target, Enabled: true}
}

func TestRoutingBoundaryValidation(t *testing.T) {
	valid := func() RoutingPlan {
		return RoutingPlan{Rules: []RouteRule{
			{ID: "domain", Type: "DOMAIN-SUFFIX", Value: " EXAMPLE.COM. ", Target: "direct", Enabled: true},
			{ID: "cidr", Type: "IP-CIDR", Value: "2001:db8::1234/32", Target: "reject", Enabled: true},
			fallbackRule("proxy"),
		}}
	}
	plan := valid()
	if err := plan.validate(true); err != nil {
		t.Fatal(err)
	}
	if plan.Rules[0].Value != "example.com" || plan.Rules[1].Value != "2001:db8::/32" {
		t.Fatal("rules not normalized")
	}
	for _, mutate := range []func(*RoutingPlan){
		func(p *RoutingPlan) { p.Rules[0].Value = "https://example.com/path" },
		func(p *RoutingPlan) { p.Rules[0].Value = "*.example.com" },
		func(p *RoutingPlan) { p.Rules[1].Value = "192.168.0.1/33" },
		func(p *RoutingPlan) { p.Rules[1].Value = "fe80::1%lo/64" },
		func(p *RoutingPlan) { p.Rules[0].ID = "fallback" },
		func(p *RoutingPlan) { p.Rules[2].Enabled = false },
		func(p *RoutingPlan) { p.Rules = append(p.Rules, fallbackRule("direct")) },
		func(p *RoutingPlan) { p.Rules = p.Rules[:2] },
		func(p *RoutingPlan) { p.Rules[0].Target = "group:missing" },
		func(p *RoutingPlan) { p.Rules[0].Target = "node:../configs" },
	} {
		plan := valid()
		mutate(&plan)
		if plan.validate(true) == nil {
			t.Fatal("invalid rule set accepted")
		}
	}
	plan = valid()
	plan.Rules[0].Enabled = false
	plan.Rules[0].Target = "group:deleted"
	if err := plan.validate(true); err != nil {
		t.Fatal("disabled reference should be repairable", err)
	}
	rules, err := compileRouteRules(&plan, nil)
	if err != nil || len(rules) != 4 {
		t.Fatal("disabled rule compiled", err)
	}
}

func routingProxyFixture(t *testing.T, name string) (Node, *atomic.Int32) {
	t.Helper()
	calls := &atomic.Int32{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodConnect {
			http.Error(w, "CONNECT required", 400)
			return
		}
		connection, buffer, err := w.(http.Hijacker).Hijack()
		if err != nil {
			return
		}
		defer connection.Close()
		connection.SetDeadline(time.Now().Add(3 * time.Second))
		io.WriteString(connection, "HTTP/1.1 200 Connection Established\r\n\r\n")
		request, err := http.ReadRequest(bufio.NewReader(buffer))
		if err != nil {
			return
		}
		request.Body.Close()
		calls.Add(1)
		fmt.Fprintf(connection, "HTTP/1.1 200 OK\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s", len(name), name)
	}))
	t.Cleanup(server.Close)
	u, _ := url.Parse(server.URL)
	port, _ := strconv.Atoi(u.Port())
	return Node{ID: name, Name: name, Revision: 1, Protocol: "http", Server: u.Hostname(), Port: port}, calls
}

func TestRealCoreOrderedRoutingAndModeOverride(t *testing.T) {
	corePath := testCore(t)
	primary, aCalls := routingProxyFixture(t, "via-primary")
	secondary, bCalls := routingProxyFixture(t, "via-secondary")
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "direct-origin") }))
	defer origin.Close()
	plan := RoutingPlan{Revision: 7, Rules: []RouteRule{
		{ID: "exact", Type: "DOMAIN", Value: "api.example.test", Target: "group:work", Enabled: true},
		{ID: "blocked", Type: "DOMAIN", Value: "blocked.test", Target: "reject", Enabled: true},
		{ID: "suffix", Type: "DOMAIN-SUFFIX", Value: "example.test", Target: "node:via-primary", Enabled: true},
		{ID: "local", Type: "IP-CIDR", Value: "127.0.0.0/8", Target: "direct", Enabled: true},
		fallbackRule("proxy"),
	}, Outbounds: []RoutingOutbound{
		{Key: "group:work", Name: "工作分组", Node: secondary},
		{Key: "node:via-primary", Name: primary.Name, Node: primary},
	}}
	manager := New(corePath, t.TempDir())
	t.Cleanup(func() {
		if err := manager.Disconnect(); err != nil {
			t.Error(err)
		}
	})
	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
	defer cancel()
	if err := manager.ValidateRules(ctx, plan); err != nil {
		t.Fatal(err)
	}
	snapshot, err := manager.ConnectRouting(ctx, primary, "rule", false, &plan)
	if err != nil {
		t.Fatal(err)
	}
	manager.active.cancelProbe()
	if snapshot.RuleRevision != 7 || snapshot.RouteBindings["group:work"].ID != secondary.ID {
		t.Fatal("applied bindings not reported")
	}
	proxyURL, _ := url.Parse(fmt.Sprintf("http://127.0.0.1:%d", snapshot.ProxyPort))
	client := &http.Client{Timeout: 3 * time.Second, Transport: &http.Transport{Proxy: http.ProxyURL(proxyURL), DisableKeepAlives: true}}
	defer client.CloseIdleConnections()
	get := func(target, want string) {
		t.Helper()
		res, err := client.Get(target)
		if err != nil {
			t.Fatal(err)
		}
		data, err := io.ReadAll(res.Body)
		res.Body.Close()
		if err != nil || string(data) != want {
			t.Fatalf("route %s returned %q, want %q: %v", target, data, want, err)
		}
	}
	get("http://api.example.test/", "via-secondary")
	get("http://nested.example.test/", "via-primary")
	get(origin.URL, "direct-origin")
	get("http://192.0.2.123/", "via-primary")
	if response, err := client.Get("http://blocked.test/"); err == nil {
		response.Body.Close()
		if response.StatusCode < 400 {
			t.Fatal("reject rule allowed a request")
		}
	}
	if aCalls.Load() != 2 || bCalls.Load() != 1 {
		t.Fatal("priority or group outbound wrong")
	}
	// Checking an invalid draft never changes the existing session or routing.
	invalid := plan
	invalid.Rules = append([]RouteRule{}, plan.Rules...)
	invalid.Rules[0].Value = "https://bad.test"
	if err := manager.ValidateRules(ctx, invalid); err == nil {
		t.Fatal("invalid draft accepted")
	}
	if manager.Snapshot(ctx).SessionID != snapshot.SessionID {
		t.Fatal("validation replaced active core")
	}
	plan.Outbounds[0].Node.Port = 1
	get("http://api.example.test/", "via-secondary")
	if err := manager.SetMode(ctx, "global"); err != nil {
		t.Fatal(err)
	}
	get("http://blocked.test/", "via-primary")
	get(origin.URL, "via-primary")
	if err := manager.SetMode(ctx, "direct"); err != nil {
		t.Fatal(err)
	}
	get(origin.URL, "direct-origin")
	if err := manager.SetMode(ctx, "rule"); err != nil {
		t.Fatal(err)
	}
	get("http://api.example.test/", "via-secondary")
	// The same compiler accepts IPv6 matching and a rejecting fallback.
	checkPlan := RoutingPlan{Rules: []RouteRule{{ID: "ipv6", Type: "IP-CIDR", Value: "2001:db8::1234/32", Target: "direct", Enabled: true}, fallbackRule("reject")}}
	if err := manager.ValidateRules(ctx, checkPlan); err != nil {
		t.Fatal(err)
	}
}

func TestRuleCompilerPreservesPerOutboundSecurity(t *testing.T) {
	primary := Node{ID: "primary", Name: "primary", Protocol: "http", Server: "127.0.0.1", Port: 80, Revision: 1}
	hy2 := Node{ID: "hy2", Name: "hy2", Protocol: "hysteria2", Server: "hy2.example.test", Port: 443, TLS: true, Revision: 1,
		Options: NodeOptions{Transport: "quic", CertificateSHA256: strings.Repeat("ab", 32)}}
	plan := RoutingPlan{Rules: []RouteRule{fallbackRule("group:test")}, Outbounds: []RoutingOutbound{{Key: "group:test", Name: "test", Node: hy2}}}
	config, err := routingConfiguration(primary, credentials{}, "rule", 1080, 1081, "fixture", upstreamNetwork{}, &plan,
		[]preparedOutbound{{RoutingOutbound: plan.Outbounds[0], auth: credentials{Password: "fixture"}, network: upstreamNetwork{InterfaceName: "fixture-interface", EncryptedDNS: true}}})
	if err != nil {
		t.Fatal(err)
	}
	var data map[string]any
	if err := json.Unmarshal(config, &data); err != nil {
		t.Fatal(err)
	}
	out := data["outbounds"].([]any)[2].(map[string]any)
	if out["bind_interface"] != "fixture-interface" || out["domain_resolver"].(map[string]any)["server"] != "upstream-dns-route-0" ||
		out["tls"].(map[string]any)["rainlink_certificate_sha256"] != strings.Repeat("ab", 32) {
		t.Fatal("rule target lost upstream protection")
	}
}
