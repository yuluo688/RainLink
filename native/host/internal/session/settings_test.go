package session

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"strings"
	"sync/atomic"
	"syscall"
	"testing"
	"time"
)

func dnsFixtureAnswer(query []byte) []byte {
	end := 12
	for end < len(query) && query[end] != 0 {
		end += int(query[end]) + 1
	}
	end += 5
	if end > len(query) {
		return nil
	}
	packet := append([]byte(nil), query[:end]...)
	packet[2], packet[3], packet[6], packet[7] = 0x81, 0x80, 0, 1
	packet[8], packet[9], packet[10], packet[11] = 0, 0, 0, 0
	return append(packet, 0xc0, 0x0c, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 203, 0, 113, 88)
}

func TestRuntimeSettingsValidateAndCompile(t *testing.T) {
	path := testCore(t)
	manager := New(path, t.TempDir())
	for _, mode := range []string{"system", "encrypted", "custom"} {
		for _, ipv6 := range []bool{false, true} {
			s := defaultRuntimeSettings()
			s.DNSMode, s.IPv6 = mode, ipv6
			if mode == "custom" {
				s.Resolver = "udp://[2606:4700:4700::1111]:53"
			}
			if err := manager.ValidateRuntime(context.Background(), s); err != nil {
				t.Fatalf("%s ipv6=%v: %v", mode, ipv6, err)
			}
		}
	}
	for _, resolver := range []string{"https://1.1.1.1/dns-query", "https://dns.example.test:8443/dns-query", "udp://127.0.0.1:15353"} {
		s := defaultRuntimeSettings()
		s.DNSMode, s.Resolver = "custom", resolver
		if err := manager.ValidateRuntime(context.Background(), s); err != nil {
			t.Fatal(resolver, err)
		}
	}
	for _, raw := range []string{`{"proxyPort":-1}`, `{"proxyPort":65536}`, `{"dnsMode":"fake"}`,
		`{"logLevel":"trace"}`, `{"dnsMode":"encrypted","resolver":"http://example.com"}`,
		`{"dnsMode":"custom","resolver":"https://user:secret@example.com/dns-query"}`,
		`{"dnsMode":"custom","resolver":"https://example.com/dns-query?token=secret"}`,
		`{"dnsMode":"custom","resolver":"udp://example.com"}`, `{"dnsMode":"custom","resolver":"udp://1.1.1.1/path"}`,
		`{"dnsMode":"custom","bootstrapDns":"localhost"}`, `{"dnsMode":"custom","resolver":"https://example.com:65536"}`,
		`{"unknown":true}`, `null`, `[]`} {
		if _, err := decodeRuntime([]byte(raw)); err == nil {
			t.Fatalf("invalid settings accepted: %s", raw)
		}
	}
	s := defaultRuntimeSettings()
	s.DNSMode, s.IPv6, s.LogLevel = "encrypted", true, "error"
	primary := preparedOutbound{RoutingOutbound: RoutingOutbound{Node: Node{Protocol: "http", Server: "127.0.0.1", Port: 9}}}
	data, err := targetConfiguration(primary, "direct", 17890, 17891, "fixture", nil, nil, s)
	if err != nil {
		t.Fatal(err)
	}
	var config map[string]any
	if err := json.Unmarshal(data, &config); err != nil {
		t.Fatal(err)
	}
	if config["dns"].(map[string]any)["final"] != "user-dns" || config["dns"].(map[string]any)["strategy"] != "prefer_ipv4" ||
		config["route"].(map[string]any)["default_domain_resolver"] != "user-dns" || config["log"].(map[string]any)["level"] != "error" {
		t.Fatal("runtime settings were not compiled")
	}
	if manager.active != nil {
		t.Fatal("validation started a session")
	}
}

func TestDNSActualHTTPSAndMalformedResponses(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.Header.Get("Content-Type") != "application/dns-message" {
			t.Error("not a DoH request")
		}
		query, err := io.ReadAll(r.Body)
		if err != nil {
			t.Error(err)
			return
		}
		w.Header().Set("Content-Type", "application/dns-message")
		w.Write(dnsFixtureAnswer(query))
	}))
	defer server.Close()
	ips, err := testDoH(context.Background(), server.Client(), server.URL)
	if err != nil || len(ips) != 1 || ips[0].String() != "203.0.113.88" {
		t.Fatal(ips, err)
	}
	query := []byte{0x52, 0x4c, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 7, 'e', 'x', 'a', 'm', 'p', 'l', 'e', 3, 'c', 'o', 'm', 0, 0, 1, 0, 1}
	valid := dnsFixtureAnswer(query)
	for length := 0; length < len(valid); length++ {
		if _, err := dohAddresses(valid[:length], query); err == nil {
			t.Fatalf("truncated packet accepted at %d", length)
		}
	}
	for _, change := range []func([]byte){func(p []byte) { p[0]++ }, func(p []byte) { p[2] |= 2 }, func(p []byte) { p[3] |= 3 },
		func(p []byte) { p[13] = 'z' }, func(p []byte) { p[len(query)+1] = 255 }, func(p []byte) { binary.BigEndian.PutUint16(p[6:8], 65535) }} {
		bad := append([]byte(nil), valid...)
		change(bad)
		if _, err := dohAddresses(bad, query); err == nil {
			t.Fatal("malformed packet accepted")
		}
	}
}

func TestDNSActualUDPAndCancellation(t *testing.T) {
	listener, err := net.ListenPacket("udp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	done := make(chan struct{})
	go func() {
		defer close(done)
		buffer := make([]byte, 4096)
		for {
			n, addr, err := listener.ReadFrom(buffer)
			if err != nil {
				return
			}
			listener.WriteTo(dnsFixtureAnswer(buffer[:n]), addr)
		}
	}()
	s := defaultRuntimeSettings()
	s.DNSMode, s.Resolver = "custom", "udp://"+listener.LocalAddr().String()
	m := New("", t.TempDir())
	result, err := m.TestDNS(context.Background(), s)
	if err != nil || len(result.Addresses) != 1 || result.Addresses[0] != "203.0.113.88" {
		t.Fatal(result, err)
	}
	var protected atomic.Int32
	physical := &net.Dialer{Control: func(_, _ string, socket syscall.RawConn) error {
		protected.Add(1)
		return nil
	}}
	if _, err := TestDNSWithDialer(context.Background(), s, physical); err != nil || protected.Load() == 0 {
		t.Fatal("physical DNS sockets were not protected", err)
	}
	physical.Control = func(_, _ string, socket syscall.RawConn) error {
		return errors.New("private-platform-error")
	}
	if _, err := TestDNSWithDialer(context.Background(), s, physical); err == nil || strings.Contains(err.Error(), "private-platform-error") {
		t.Fatal("protection failure was ignored or leaked", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := m.TestDNS(ctx, s); err == nil {
		t.Fatal("cancelled lookup reported success")
	}
	listener.Close()
	<-done
}

func TestRuntimeSettingsApplyPortAndPreserveLiveSession(t *testing.T) {
	path := testCore(t)
	manager := New(path, t.TempDir())
	defer manager.Disconnect()
	settings := defaultRuntimeSettings()
	port, err := freePort()
	if err != nil {
		t.Fatal(err)
	}
	settings.ProxyPort = port
	node := Node{ID: "settings-runtime", Name: "runtime fixture", Revision: 1, Protocol: "http", Server: "127.0.0.1", Port: 9}
	snapshot, err := manager.connectTarget(context.Background(), node, nil, "direct", false, nil, false, settings)
	if err != nil || snapshot.ProxyPort != port {
		t.Fatal(snapshot, err)
	}
	if snapshot.RuntimeSettings == nil || *snapshot.RuntimeSettings != settings {
		t.Fatal("snapshot does not acknowledge applied settings")
	}
	conn, err := net.DialTimeout("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(port)), time.Second)
	if err != nil {
		t.Fatal(err)
	}
	conn.Close()
	invalid := settings
	invalid.ProxyPort = 65536
	if manager.ValidateRuntime(context.Background(), invalid) == nil {
		t.Fatal("invalid settings accepted")
	}
	if manager.active.snapshot.SessionID != snapshot.SessionID {
		t.Fatal("failed validation interrupted live connection")
	}
	if err := manager.ValidateRuntime(context.Background(), settings); err != nil {
		t.Fatal(err)
	}
	if manager.active.snapshot.SessionID != snapshot.SessionID {
		t.Fatal("validation restarted live connection")
	}
	if err := manager.Disconnect(); err != nil {
		t.Fatal(err)
	}
	occupied, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer occupied.Close()
	settings.ProxyPort = occupied.Addr().(*net.TCPAddr).Port
	if _, err = manager.connectTarget(context.Background(), node, nil, "direct", false, nil, false, settings); err == nil {
		t.Fatal("occupied port accepted")
	}
	if manager.active != nil {
		t.Fatal("failed connect retained core")
	}
}

func TestCoreActuallyUsesCustomDNS(t *testing.T) {
	path := testCore(t)
	listener, err := net.ListenPacket("udp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	queries := make(chan struct{}, 8)
	done := make(chan struct{})
	go func() {
		defer close(done)
		buffer := make([]byte, 4096)
		for {
			n, addr, err := listener.ReadFrom(buffer)
			if err != nil {
				return
			}
			packet := dnsFixtureAnswer(buffer[:n])
			copy(packet[len(packet)-4:], []byte{127, 0, 0, 1})
			listener.WriteTo(packet, addr)
			select {
			case queries <- struct{}{}:
			default:
			}
		}
	}()
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "dns-origin") }))
	defer origin.Close()
	u, _ := url.Parse(origin.URL)
	settings := defaultRuntimeSettings()
	settings.DNSMode, settings.Resolver = "custom", "udp://"+listener.LocalAddr().String()
	m := New(path, t.TempDir())
	defer m.Disconnect()
	node := Node{ID: "dns-use", Name: "DNS runtime", Revision: 1, Protocol: "http", Server: "127.0.0.1", Port: 9}
	snapshot, err := m.connectTarget(context.Background(), node, nil, "direct", false, nil, false, settings)
	if err != nil {
		t.Fatal(err)
	}
	proxy, _ := url.Parse("http://127.0.0.1:" + strconv.Itoa(snapshot.ProxyPort))
	transport := &http.Transport{Proxy: http.ProxyURL(proxy)}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, Timeout: 4 * time.Second}
	response, err := client.Get("http://rainlink.example.test:" + u.Port() + "/fixture")
	if err != nil {
		t.Fatal(err)
	}
	data, err := io.ReadAll(response.Body)
	response.Body.Close()
	if err != nil || !bytes.Equal(data, []byte("dns-origin")) {
		t.Fatal(string(data), err)
	}
	select {
	case <-queries:
	default:
		t.Fatal("configured resolver received no request")
	}
	listener.Close()
	<-done
}
