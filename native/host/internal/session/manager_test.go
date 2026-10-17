package session

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func testCore(t *testing.T) string {
	t.Helper()
	path := os.Getenv("RAINLINK_TEST_CORE_PATH")
	if path == "" {
		t.Skip("set RAINLINK_TEST_CORE_PATH to run real-core integration tests")
	}
	if _, err := Version(path); err != nil {
		t.Fatal(err)
	}
	return path
}

func requireCredentialStore(t *testing.T) {
	t.Helper()
	if runtime.GOOS == "windows" || (runtime.GOOS == "linux" && os.Getenv("RAINLINK_TEST_SECRET_SERVICE") == "isolated") {
		return
	}
	t.Skip("requires Windows DPAPI or an explicitly isolated Linux Secret Service")
}

func TestRealCoreRoutesAndLiveModeChanges(t *testing.T) {
	path := testCore(t)
	requireCredentialStore(t)
	var requests atomic.Int32
	destination := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "direct-origin") }))
	defer destination.Close()
	destinationURL, _ := url.Parse(destination.URL)
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Proxy-Authorization") != "Basic "+base64.StdEncoding.EncodeToString([]byte("fixture-user:fixture-password")) {
			http.Error(w, "authentication required", http.StatusProxyAuthRequired)
			return
		}
		if r.Method != http.MethodConnect {
			http.Error(w, "CONNECT required", 400)
			return
		}
		if r.Host != destinationURL.Host {
			http.Error(w, "fixture destination only", 502)
			return
		}
		remote, err := net.DialTimeout("tcp", r.Host, time.Second)
		if err != nil {
			http.Error(w, "destination unavailable", 502)
			return
		}
		local, buffer, err := w.(http.Hijacker).Hijack()
		if err != nil {
			remote.Close()
			return
		}
		defer local.Close()
		defer remote.Close()
		requests.Add(1)
		io.WriteString(local, "HTTP/1.1 200 Connection Established\r\n\r\n")
		copied := make(chan struct{})
		go func() { io.Copy(remote, buffer); remote.Close(); close(copied) }()
		io.Copy(local, remote)
		local.Close()
		<-copied
	}))
	defer upstream.Close()
	u, _ := url.Parse(upstream.URL)
	host, portString, _ := net.SplitHostPort(u.Host)
	port, _ := strconv.Atoi(portString)
	manager := New(path, t.TempDir())
	defer func() {
		if err := manager.Disconnect(); err != nil {
			t.Error(err)
		}
	}()
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	cipher, err := seal(t.Context(), []byte(`{"username":"fixture-user","password":"fixture-password"}`), "test")
	if err != nil {
		t.Fatal(err)
	}
	snapshot, err := manager.Connect(ctx, Node{ID: "test", Name: "HTTP fixture", Revision: 1, Protocol: "http", Server: host, Port: port, Credential: cipher}, "global", false)
	if err != nil {
		t.Fatal(err)
	}
	proxyURL, _ := url.Parse("http://127.0.0.1:" + strconv.Itoa(snapshot.ProxyPort))
	client := &http.Client{Timeout: 3 * time.Second, Transport: &http.Transport{Proxy: http.ProxyURL(proxyURL), DisableKeepAlives: true}}
	defer client.CloseIdleConnections()
	get := func(want string) {
		t.Helper()
		res, err := client.Get(destination.URL)
		if err != nil {
			t.Fatal(err)
		}
		data, err := io.ReadAll(res.Body)
		res.Body.Close()
		if err != nil || string(data) != want {
			t.Fatalf("route returned %q, want %q, error %v", data, want, err)
		}
	}
	get("direct-origin")
	if requests.Load() != 1 {
		t.Fatal("global request did not traverse upstream")
	}
	for _, mode := range []string{"direct", "rule"} {
		if err = manager.SetMode(ctx, mode); err != nil {
			var diagnostics map[string]any
			apiErr := manager.active.apiJSON(ctx, http.MethodGet, "/configs", nil, &diagnostics)
			t.Logf("configs: %+v, error: %v", diagnostics, apiErr)
			t.Fatal(err)
		}
		get("direct-origin")
		if requests.Load() != 1 {
			t.Fatalf("%s did not bypass upstream for private destination", mode)
		}
	}
	if err = manager.SetMode(ctx, "global"); err != nil {
		t.Fatal(err)
	}
	get("direct-origin")
	if requests.Load() < 2 {
		t.Fatal("traffic never reached the configured upstream")
	}
	observed := manager.Snapshot(ctx)
	if observed.Telemetry == nil || observed.Telemetry.UploadTotal == 0 || observed.Telemetry.DownloadTotal == 0 {
		t.Fatalf("core did not report actual byte counters: %+v", observed.Telemetry)
	}
	unavailable := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "unavailable", http.StatusServiceUnavailable)
	}))
	previousAPI := manager.active.api
	manager.active.api = unavailable.URL
	unknown := manager.Snapshot(ctx)
	manager.active.api = previousAPI
	unavailable.Close()
	if unknown.Phase != "failed" || unknown.SessionID != snapshot.SessionID || unknown.Error == "" {
		t.Fatal("unavailable core API was reported as a confirmed live connection")
	}
	if err = manager.Disconnect(); err != nil {
		t.Fatal(err)
	}
	if _, err = client.Get(destination.URL); err == nil {
		t.Fatal("listener survived disconnect")
	}
	if manager.Snapshot(ctx).Phase != "idle" {
		t.Fatal("disconnect was not observed")
	}
}

func TestRealCoreSOCKS5Authentication(t *testing.T) {
	path := testCore(t)
	requireCredentialStore(t)
	destination := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		io.WriteString(w, "SOCKS5 authenticated origin")
	}))
	defer destination.Close()
	port, err := freePort()
	if err != nil {
		t.Fatal(err)
	}
	config, err := json.Marshal(map[string]any{
		"log": map[string]any{"level": "error"},
		"inbounds": []any{map[string]any{"type": "socks", "listen": "127.0.0.1", "listen_port": port,
			"users": []any{map[string]any{"username": "fixture-user", "password": "fixture-password"}}}},
		"outbounds": []any{map[string]any{"type": "direct"}},
	})
	if err != nil {
		t.Fatal(err)
	}
	upstream := exec.Command(path, "run", "-c", "stdin")
	hideWindow(upstream)
	upstream.Stdin = strings.NewReader(string(config))
	if err = upstream.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { upstream.Process.Kill(); upstream.Wait() }()
	address := net.JoinHostPort("127.0.0.1", strconv.Itoa(port))
	ready := false
	for deadline := time.Now().Add(3 * time.Second); time.Now().Before(deadline); {
		connection, dialErr := net.DialTimeout("tcp", address, 100*time.Millisecond)
		if dialErr == nil {
			connection.Close()
			ready = true
			break
		}
		time.Sleep(25 * time.Millisecond)
	}
	if !ready {
		t.Fatal("SOCKS5 fixture failed to start")
	}
	cipher, err := seal(t.Context(), []byte(`{"username":"fixture-user","password":"fixture-password"}`), "socks-fixture")
	if err != nil {
		t.Fatal(err)
	}
	manager := New(path, t.TempDir())
	defer func() {
		if err := manager.Disconnect(); err != nil {
			t.Error(err)
		}
	}()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	snapshot, err := manager.Connect(ctx, Node{ID: "socks-fixture", Name: "SOCKS5 fixture", Revision: 1,
		Protocol: "socks", Server: "127.0.0.1", Port: port, Credential: cipher}, "global", false)
	if err != nil {
		t.Fatal(err)
	}
	proxyURL, _ := url.Parse("http://127.0.0.1:" + strconv.Itoa(snapshot.ProxyPort))
	client := &http.Client{Timeout: 3 * time.Second, Transport: &http.Transport{Proxy: http.ProxyURL(proxyURL), DisableKeepAlives: true}}
	defer client.CloseIdleConnections()
	response, err := client.Get(destination.URL)
	if err != nil {
		t.Fatal(err)
	}
	body, err := io.ReadAll(response.Body)
	response.Body.Close()
	if err != nil || string(body) != "SOCKS5 authenticated origin" {
		t.Fatalf("SOCKS5 authenticated transfer failed: %q, %v", body, err)
	}
}

func TestCredentialsAreUserProtectedAndNodeBound(t *testing.T) {
	requireCredentialStore(t)
	plain := []byte(`{"username":"test-user","password":"not-a-real-password"}`)
	cipher, err := seal(t.Context(), plain, "node-a")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(cipher, "not-a-real-password") {
		t.Fatal("credential was not encrypted")
	}
	decoded, err := unseal(t.Context(), cipher, "node-a")
	if err != nil || string(decoded) != string(plain) {
		t.Fatal("system credential store round trip failed")
	}
	if _, err = unseal(t.Context(), cipher, "node-b"); err == nil {
		t.Fatal("ciphertext was accepted for another node")
	}
}

func TestInvalidNodeAndCancelledConnectNeverCommit(t *testing.T) {
	manager := New("missing-core", t.TempDir())
	_, err := manager.Connect(context.Background(), Node{ID: "x", Name: "x", Revision: 1, Protocol: "http", Server: "https://invalid/path", Port: 443}, "global", true)
	if err == nil || manager.active != nil {
		t.Fatal("invalid node started a session")
	}
	path := testCore(t)
	manager = New(path, t.TempDir())
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err = manager.Connect(ctx, Node{ID: "x", Name: "x", Revision: 1, Protocol: "http", Server: "127.0.0.1", Port: 1}, "global", true)
	if err == nil || manager.active != nil {
		t.Fatal("cancelled connection committed")
	}
	if _, err = os.Stat(filepath.Join(manager.stateDir, "proxy-recovery.bin")); !os.IsNotExist(err) {
		t.Fatal("cancelled connection acquired system proxy")
	}
}
