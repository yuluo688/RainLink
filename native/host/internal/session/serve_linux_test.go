//go:build linux && !android

package session

import (
	"context"
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

func TestLinuxHostPrivateProtocolAndEOFCleanup(t *testing.T) {
	requireCredentialStore(t)
	t.Setenv("XDG_CURRENT_DESKTOP", "RainLink-Unsupported")
	ctx, cancel := context.WithTimeout(t.Context(), 20*time.Second)
	defer cancel()
	host := newLinuxTestHost(t, ctx, "serve")
	rpc := host.rpc
	var hello struct {
		ProtocolVersion int    `json:"protocolVersion"`
		CoreVersion     string `json:"coreVersion"`
	}
	if failure := rpc("hello", map[string]any{}, &hello); failure != nil || hello.ProtocolVersion != 2 || hello.CoreVersion == "" {
		t.Fatalf("Linux handshake failed: %v", failure)
	}
	var protected struct {
		Cipher string `json:"cipher"`
	}
	if failure := rpc("protect", map[string]string{"id": "linux-node", "username": "fixture-user", "password": "fixture-password"}, &protected); failure != nil || !strings.HasPrefix(protected.Cipher, "rls1.") {
		t.Fatalf("Linux protect failed: %v", failure)
	}
	var revealed credentials
	if failure := rpc("reveal", map[string]string{"id": "linux-node", "cipher": protected.Cipher}, &revealed); failure != nil || revealed.Password != "fixture-password" {
		t.Fatalf("Linux reveal failed: %v", failure)
	}
	if failure := rpc("reveal", map[string]string{"id": "foreign-node", "cipher": protected.Cipher}, nil); failure == nil || failure.Code != "credential_read_failed" {
		t.Fatal("Linux IPC lost credential binding")
	}
	var hits atomic.Int32
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		_, _ = io.WriteString(w, "linux-host-origin")
	}))
	defer origin.Close()
	node := chainProxyFixture(t, "linux-node", &chainRecorder{}, false)
	node.Credential = protected.Cipher
	for _, capture := range []map[string]any{{"systemProxy": true}, {"tun": true}} {
		capture["node"], capture["mode"] = node, "global"
		if failure := rpc("connect", capture, nil); failure == nil || failure.Code != "capture_unavailable" {
			t.Fatal("unsupported Linux capture was accepted")
		}
	}
	var snapshot Snapshot
	if failure := rpc("connect", map[string]any{"node": node, "mode": "global", "systemProxy": false, "tun": false}, &snapshot); failure != nil || snapshot.Phase != "connected" || snapshot.ProxyPort == 0 || snapshot.SystemProxy || snapshot.TUN {
		t.Fatalf("Linux connect failed: %v", failure)
	}
	proxy, err := url.Parse(fmt.Sprintf("http://127.0.0.1:%d", snapshot.ProxyPort))
	if err != nil {
		t.Fatal(err)
	}
	transport := &http.Transport{Proxy: http.ProxyURL(proxy), DisableKeepAlives: true}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, Timeout: time.Second}
	get := func() {
		t.Helper()
		response, err := client.Get(origin.URL)
		if err != nil {
			t.Fatal(err)
		}
		body, err := io.ReadAll(response.Body)
		_ = response.Body.Close()
		if err != nil || string(body) != "linux-host-origin" {
			t.Fatalf("Linux actual transfer failed: %v", err)
		}
	}
	get()
	if failure := rpc("mode", map[string]string{"mode": "direct"}, nil); failure != nil {
		t.Fatal(failure)
	}
	get()
	if failure := rpc("capture", map[string]bool{"enabled": true}, nil); failure == nil || failure.Code != "capture_unavailable" {
		t.Fatal("unsupported capture switch succeeded")
	}
	get()
	if hits.Load() != 3 {
		t.Fatalf("missing origin transfers: %d", hits.Load())
	}
	host.finish(false)
	if _, err := client.Get(origin.URL); err == nil {
		t.Fatal("EOF left the Linux proxy listener running")
	}
	listener, err := net.Listen("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(snapshot.ProxyPort)))
	if err != nil {
		t.Fatalf("Linux listener was not released: %v", err)
	}
	_ = listener.Close()
}
