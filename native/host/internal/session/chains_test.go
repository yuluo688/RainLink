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
	"os"
	"reflect"
	"strconv"
	"sync"
	"testing"
	"time"
)

type chainRecorder struct {
	mu    sync.Mutex
	calls []string
}

func (r *chainRecorder) add(value string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.calls = append(r.calls, value)
}
func (r *chainRecorder) take() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	result := r.calls
	r.calls = nil
	return result
}

func chainProxyFixture(t *testing.T, id string, calls *chainRecorder, reject bool) Node {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodConnect {
			http.Error(w, "CONNECT required", 400)
			return
		}
		calls.add(id + ">" + r.Host)
		if reject {
			http.Error(w, "authentication required", http.StatusProxyAuthRequired)
			return
		}
		remote, err := net.DialTimeout("tcp", r.Host, time.Second)
		if err != nil {
			http.Error(w, "unavailable", 502)
			return
		}
		local, buffer, err := w.(http.Hijacker).Hijack()
		if err != nil {
			remote.Close()
			return
		}
		defer local.Close()
		defer remote.Close()
		local.SetDeadline(time.Now().Add(5 * time.Second))
		remote.SetDeadline(time.Now().Add(5 * time.Second))
		io.WriteString(local, "HTTP/1.1 200 Connection Established\r\n\r\n")
		done := make(chan struct{})
		go func() { io.Copy(remote, buffer); remote.Close(); close(done) }()
		io.Copy(local, remote)
		local.Close()
		<-done
	}))
	t.Cleanup(server.Close)
	u, _ := url.Parse(server.URL)
	port, _ := strconv.Atoi(u.Port())
	return Node{ID: id, Name: id, Revision: 1, Protocol: "http", Server: u.Hostname(), Port: port}
}

func TestRealCoreChainOrderRuleTargetAndBindings(t *testing.T) {
	core := testCore(t)
	calls := &chainRecorder{}
	a := chainProxyFixture(t, "entry", calls, false)
	b := chainProxyFixture(t, "exit", calls, false)
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "chain-payload") }))
	defer origin.Close()
	u, _ := url.Parse(origin.URL)
	chain := ChainSnapshot{ID: "chain", Name: "本地链", Revision: 2, Hops: []Node{a, b}}
	manager := New(core, t.TempDir())
	defer manager.Disconnect()
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	if err := manager.ValidateChain(ctx, chain); err != nil {
		t.Fatal(err)
	}
	connectAndGet := func(reverse bool, rule bool) {
		t.Helper()
		var snapshot Snapshot
		var err error
		if rule {
			plan := &RoutingPlan{Revision: 4, Rules: []RouteRule{fallbackRule("chain:chain")}, Outbounds: []RoutingOutbound{{Key: "chain:chain", Name: chain.Name, Chain: &chain}}}
			snapshot, err = manager.connectTarget(ctx, a, nil, "rule", false, plan, false)
		} else {
			snapshot, err = manager.connectTarget(ctx, Node{}, &chain, "global", false, nil, false)
		}
		if err != nil {
			t.Fatal(err)
		}
		if !rule && (snapshot.Node != nil || snapshot.Target == nil || snapshot.Target.Kind != "chain" || snapshot.Target.ID != chain.ID || len(snapshot.RouteBindings) != 2) {
			t.Fatal("chain identity/bindings lost", snapshot)
		}
		if rule && (snapshot.RouteBindings["chain:chain"].Revision != 2 || snapshot.RouteBindings["chain:chain/hop/1"].ID != chain.Hops[1].ID) {
			t.Fatal("rule chain binding lost")
		}
		proxy, _ := url.Parse(fmt.Sprintf("http://127.0.0.1:%d", snapshot.ProxyPort))
		client := &http.Client{Timeout: 3 * time.Second, Transport: &http.Transport{Proxy: http.ProxyURL(proxy), DisableKeepAlives: true}}
		response, err := client.Get(origin.URL)
		if err != nil {
			t.Fatal(err)
		}
		body, readErr := io.ReadAll(response.Body)
		response.Body.Close()
		client.CloseIdleConnections()
		if readErr != nil || string(body) != "chain-payload" {
			t.Fatal("chain transfer failed", readErr)
		}
		first, last := a, b
		if reverse {
			first, last = b, a
		}
		want := []string{first.ID + ">" + net.JoinHostPort(last.Server, strconv.Itoa(last.Port)), last.ID + ">" + u.Host}
		if got := calls.take(); !reflect.DeepEqual(got, want) {
			t.Fatalf("order: got %v, want %v", got, want)
		}
		if err := manager.Disconnect(); err != nil {
			t.Fatal(err)
		}
		listener, err := net.Listen("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(snapshot.ProxyPort)))
		if err != nil {
			t.Fatal("listener leaked", err)
		}
		listener.Close()
	}
	connectAndGet(false, false)
	chain.Hops = []Node{b, a}
	connectAndGet(true, false)
	chain.Hops = []Node{a, b}
	connectAndGet(false, true)
}

func TestRealCoreChainPrefixFailureCancellationAndIsolation(t *testing.T) {
	core := testCore(t)
	calls := &chainRecorder{}
	a := chainProxyFixture(t, "entry", calls, false)
	b := chainProxyFixture(t, "bad-auth", calls, true)
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(204) }))
	defer origin.Close()
	chain := ChainSnapshot{ID: "chain", Name: "前缀测试", Revision: 1, Hops: []Node{a, b}}
	liveDir := t.TempDir()
	manager := New(core, liveDir)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	live, err := manager.connectTarget(ctx, a, nil, "global", false, nil, false)
	if err != nil {
		t.Fatal(err)
	}
	defer manager.Disconnect()
	probe := New(core, t.TempDir())
	probe.isolated = true
	result, err := probe.testChain(ctx, chain, origin.URL)
	if err != nil || result.Passed || len(result.Hops) != 2 || !result.Hops[0].Passed || result.Hops[1].Passed {
		t.Fatal("failed segment not identified", result, err)
	}
	current := manager.Snapshot(ctx)
	if current.SessionID != live.SessionID || current.ProxyPort != live.ProxyPort {
		t.Fatal("probe replaced live session")
	}
	if entries, readErr := os.ReadDir(liveDir); readErr != nil || len(entries) != 0 {
		t.Fatal("test modified capture state", err)
	}
	if _, err = probe.connectTarget(ctx, a, nil, "global", true, nil, false); err == nil {
		t.Fatal("test capture permitted")
	}
	if _, err = manager.TestChain(ctx, chain); err == nil {
		t.Fatal("probe allowed on normal manager")
	}
	cancelled, stop := context.WithCancel(ctx)
	stop()
	if _, err = probe.testChain(cancelled, chain, origin.URL); err == nil {
		t.Fatal("cancelled probe succeeded")
	}
	if probe.active != nil {
		t.Fatal("probe leaked active core")
	}
}

func TestChainValidationAndSafeCompilation(t *testing.T) {
	a := Node{ID: "a", Name: "入口", Revision: 1, Protocol: "http", Server: "127.0.0.1", Port: 8080}
	b := a
	b.ID = "b"
	chain := ChainSnapshot{ID: "chain", Name: "链", Revision: 1, Hops: []Node{a, b}}
	if err := chain.validate(); err != nil {
		t.Fatal(err)
	}
	original := chainFingerprint(chain)
	chain.Name = "重命名"
	chain.Revision++
	if chainFingerprint(chain) != original {
		t.Fatal("rename expired test")
	}
	chain.Hops = []Node{b, a}
	if chainFingerprint(chain) == original {
		t.Fatal("order not fingerprinted")
	}
	chain.Hops = []Node{a, a}
	if chain.validate() == nil {
		t.Fatal("duplicate accepted")
	}
	hy := b
	hy.Protocol = "hysteria2"
	hy.TLS = true
	hy.Options = NodeOptions{Transport: "quic"}
	chain.Hops = []Node{a, hy}
	if chain.validate() == nil {
		t.Fatal("HTTP to QUIC accepted")
	}
	chain.Hops = []Node{hy, a}
	if chain.validate() != nil {
		t.Fatal("QUIC entry to TCP rejected")
	}
	primary := preparedOutbound{RoutingOutbound: RoutingOutbound{Chain: &chain}, hops: []preparedHop{
		{node: hy, auth: credentials{Password: "fixture-secret"}, network: upstreamNetwork{InterfaceName: "physical", EncryptedDNS: true}},
		{node: a, network: upstreamNetwork{InterfaceName: "must-not-bind", EncryptedDNS: true}},
	}}
	raw, err := targetConfiguration(primary, "global", 1234, 2345, "control", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	var config map[string]any
	if err = json.Unmarshal(raw, &config); err != nil {
		t.Fatal(err)
	}
	outbounds := config["outbounds"].([]any)
	first, last := outbounds[0].(map[string]any), outbounds[1].(map[string]any)
	if first["bind_interface"] != "physical" || last["detour"] != "proxy-hop-0" || last["bind_interface"] != nil || last["domain_resolver"] != nil {
		t.Fatal("detour bypassed entry")
	}
}

func TestRealCoreChainCancellationDuringRequest(t *testing.T) {
	core := testCore(t)
	calls := &chainRecorder{}
	a := chainProxyFixture(t, "entry", calls, false)
	b := chainProxyFixture(t, "exit", calls, false)
	started, closed := make(chan struct{}), make(chan struct{})
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		close(started)
		<-r.Context().Done()
		close(closed)
	}))
	defer origin.Close()
	probe := New(core, t.TempDir())
	probe.isolated = true
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() {
		_, err := probe.testChain(ctx, ChainSnapshot{ID: "chain", Name: "取消测试", Revision: 1, Hops: []Node{a, b}}, origin.URL)
		done <- err
	}()
	select {
	case <-started:
	case err := <-done:
		t.Fatal("probe ended before request", err)
	case <-time.After(5 * time.Second):
		t.Fatal("probe never reached origin")
	}
	cancel()
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("cancelled probe succeeded")
		}
	case <-time.After(5 * time.Second):
		t.Fatal("cancelled prefix did not exit")
	}
	select {
	case <-closed:
	case <-time.After(5 * time.Second):
		t.Fatal("prefix request leaked after cancellation")
	}
}
