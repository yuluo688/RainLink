package session

import (
	"context"
	"crypto/ecdh"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os/exec"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func fixtureCertificate(t *testing.T) (string, string) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	template := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "localhost"}, DNSNames: []string{"localhost"}, IPAddresses: []net.IP{net.ParseIP("127.0.0.1")}, NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour), KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	private, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	return string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})), string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: private}))
}

func TestCoreChecksRealityVisionConfigurations(t *testing.T) {
	path := testCore(t)
	key, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	n := Node{ID: "reality-check", Name: "Reality 配置验证", Revision: 1, Protocol: "vless", Server: "example.test", Port: 443, TLS: true, Options: NodeOptions{Transport: "tcp", ServerName: "edge.example.test", Flow: "xtls-rprx-vision", Fingerprint: "chrome", RealityPublicKey: base64.RawURLEncoding.EncodeToString(key.PublicKey().Bytes()), RealityShortID: "01ab"}}
	if err = n.validate(); err != nil {
		t.Fatal(err)
	}
	data, err := configuration(n, credentials{Password: "a6db2f50-361a-4294-8bce-1df5f356764f"}, "global", 19080, 19090, "test-only", upstreamNetwork{})
	if err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(path, "check", "-c", "stdin")
	hideWindow(cmd)
	cmd.Stdin = strings.NewReader(string(data))
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("core rejected Reality/Vision configuration: %v, %s", err, output)
	}
	n.Options.RealityShortID = "xyz"
	if err = n.validate(); err == nil {
		t.Fatal("invalid Reality short ID accepted")
	}
	n.Options.RealityShortID = "01ab"
	n.Options.Flow = "unsupported-flow"
	if err = n.validate(); err == nil {
		t.Fatal("unsupported flow accepted")
	}
}

// The fixture is another real sing-box process, not a mocked protocol decoder.
func TestRealCoreEncryptedProtocolsAndAuthentication(t *testing.T) {
	path := testCore(t)
	requireCredentialStore(t)
	certificate, key := fixtureCertificate(t)
	for _, tc := range []struct {
		name, protocol, method, transport, obfs, security, congestion string
		tls                                                           bool
		alterID                                                       int
	}{
		{name: "SS AEAD", protocol: "shadowsocks", method: "aes-128-gcm"},
		{name: "SS 2022", protocol: "shadowsocks", method: "2022-blake3-aes-128-gcm"},
		{name: "VLESS TCP", protocol: "vless"},
		{name: "VLESS WebSocket TLS", protocol: "vless", transport: "ws", tls: true},
		{name: "VLESS gRPC TLS", protocol: "vless", transport: "grpc", tls: true},
		{name: "VMess AEAD auto", protocol: "vmess", security: "auto"},
		{name: "VMess AEAD AES", protocol: "vmess", security: "aes-128-gcm"},
		{name: "VMess AEAD ChaCha", protocol: "vmess", security: "chacha20-poly1305"},
		{name: "VMess legacy Alter ID", protocol: "vmess", security: "auto", alterID: 64},
		{name: "VMess WebSocket TLS", protocol: "vmess", security: "auto", transport: "ws", tls: true},
		{name: "VMess gRPC TLS", protocol: "vmess", security: "auto", transport: "grpc", tls: true},
		{name: "Trojan TLS", protocol: "trojan", tls: true},
		{name: "Trojan WebSocket TLS", protocol: "trojan", transport: "ws", tls: true},
		{name: "Hysteria2 QUIC", protocol: "hysteria2", transport: "quic", tls: true},
		{name: "Hysteria2 Salamander", protocol: "hysteria2", transport: "quic", tls: true, obfs: "salamander"},
		{name: "TUIC QUIC cubic", protocol: "tuic", transport: "quic", tls: true, congestion: "cubic"},
		{name: "TUIC QUIC bbr", protocol: "tuic", transport: "quic", tls: true, congestion: "bbr"},
		{name: "TUIC QUIC new_reno", protocol: "tuic", transport: "quic", tls: true, congestion: "new_reno"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var hits atomic.Int32
			destination := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				hits.Add(1)
				io.WriteString(w, "verified encrypted upstream")
			}))
			defer destination.Close()
			port := protocolFixturePort(t, tc.protocol == "hysteria2" || tc.protocol == "tuic")
			password := "fixture-password"
			if tc.protocol == "vless" || tc.protocol == "vmess" {
				password = "a6db2f50-361a-4294-8bce-1df5f356764f"
			}
			if strings.HasPrefix(tc.method, "2022-") {
				password = base64.StdEncoding.EncodeToString([]byte("test-key-16bytes"))
			}
			inbound := map[string]any{"type": tc.protocol, "listen": "127.0.0.1", "listen_port": port}
			switch tc.protocol {
			case "shadowsocks":
				inbound["method"] = tc.method
				inbound["password"] = password
			case "vless":
				inbound["users"] = []any{map[string]any{"uuid": password}}
			case "vmess":
				inbound["users"] = []any{map[string]any{"uuid": password, "alterId": tc.alterID}}
			case "tuic":
				inbound["users"] = []any{map[string]any{"uuid": "a6db2f50-361a-4294-8bce-1df5f356764f", "password": password}}
				inbound["congestion_control"] = tc.congestion
			case "trojan", "hysteria2":
				inbound["users"] = []any{map[string]any{"password": password}}
			}
			if tc.obfs != "" {
				inbound["obfs"] = map[string]any{"type": tc.obfs, "password": "fixture-obfs"}
			}
			if tc.tls {
				inbound["tls"] = map[string]any{"enabled": true, "certificate": []string{certificate}, "key": []string{key}}
			}
			if tc.transport == "ws" {
				inbound["transport"] = map[string]any{"type": "ws", "path": "/rainlink"}
			}
			if tc.transport == "grpc" {
				inbound["transport"] = map[string]any{"type": "grpc", "service_name": "rainlink"}
			}
			config, err := json.Marshal(map[string]any{"log": map[string]any{"level": "error"}, "inbounds": []any{inbound}, "outbounds": []any{map[string]any{"type": "direct"}}})
			if err != nil {
				t.Fatal(err)
			}
			upstream := exec.Command(path, "run", "-c", "stdin")
			hideWindow(upstream)
			upstream.Stdin = strings.NewReader(string(config))
			fixtureLogs := newLogBuffer()
			fixtureWriter := &coreLogWriter{logs: fixtureLogs, secrets: []string{password, "fixture-obfs"}}
			upstream.Stdout, upstream.Stderr = fixtureWriter, fixtureWriter
			if err = upstream.Start(); err != nil {
				t.Fatal(err)
			}
			defer func() { upstream.Process.Kill(); upstream.Wait() }()
			ready := false
			for deadline := time.Now().Add(3 * time.Second); time.Now().Before(deadline); {
				if tc.protocol == "hysteria2" || tc.protocol == "tuic" {
					// QUIC has no TCP listener. The actual transfer below verifies readiness.
					time.Sleep(200 * time.Millisecond)
					ready = true
					break
				}
				c, e := net.DialTimeout("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(port)), 100*time.Millisecond)
				if e == nil {
					c.Close()
					ready = true
					break
				}
				time.Sleep(25 * time.Millisecond)
			}
			if !ready {
				t.Fatalf("upstream fixture did not start: %v", fixtureLogs.read("", 0).Entries)
			}
			manager := New(path, t.TempDir())
			defer manager.Disconnect()
			node := Node{ID: "encrypted-fixture", Name: tc.name, Revision: 1, Protocol: tc.protocol, Server: "127.0.0.1", Port: port, TLS: tc.tls, Options: NodeOptions{Method: tc.method, ServerName: "localhost", Insecure: tc.tls, Transport: tc.transport, Path: "/rainlink", ServiceName: "rainlink"}}
			node.Options.Obfs = tc.obfs
			node.Options.VMessSecurity = tc.security
			node.Options.AlterID = tc.alterID
			node.Options.CongestionControl = tc.congestion
			obfsPassword := ""
			if tc.obfs != "" {
				obfsPassword = "fixture-obfs"
			}
			username := ""
			if tc.protocol == "tuic" {
				username = "a6db2f50-361a-4294-8bce-1df5f356764f"
			}
			var lastDiagnostic string
			request := func(secret string, insecure bool) bool {
				t.Helper()
				raw, _ := json.Marshal(credentials{Username: username, Password: secret, ObfsPassword: obfsPassword})
				node.Credential, err = seal(t.Context(), raw, node.ID)
				if err != nil {
					t.Fatal(err)
				}
				node.Options.Insecure = insecure
				ctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
				defer cancel()
				snapshot, e := manager.Connect(ctx, node, "global", false)
				if e != nil {
					t.Fatal(e)
				}
				// This assertion tests the local protocol fixture, independently of
				// the availability of public egress diagnostic endpoints.
				manager.active.cancelProbe()
				proxy, _ := url.Parse("http://127.0.0.1:" + strconv.Itoa(snapshot.ProxyPort))
				requestTimeout := 1500 * time.Millisecond
				if node.usesQUIC() {
					// QUIC includes TLS, HTTP/3 authentication and retransmission.
					// Bound it separately from an already-listening TCP fixture.
					requestTimeout = 5 * time.Second
				}
				client := &http.Client{Timeout: requestTimeout, Transport: &http.Transport{Proxy: http.ProxyURL(proxy), DisableKeepAlives: true}}
				defer client.CloseIdleConnections()
				response, e := client.Get(destination.URL)
				success := false
				if e == nil {
					data, readErr := io.ReadAll(response.Body)
					response.Body.Close()
					success = readErr == nil && string(data) == "verified encrypted upstream"
				}
				if !success {
					lastDiagnostic = fmt.Sprintf("fixture transfer failed: %v", e)
					batch := manager.logs.read("", 0)
					for _, entry := range batch.Entries {
						lastDiagnostic += "\n" + entry.Level + " " + entry.Message
					}
					for _, entry := range fixtureLogs.read("", 0).Entries {
						lastDiagnostic += "\nfixture " + entry.Level + " " + entry.Message
					}
				}
				if e = manager.Disconnect(); e != nil {
					t.Fatal(e)
				}
				return success
			}
			if !request(password, tc.tls) || hits.Load() != 1 {
				t.Fatalf("configured upstream did not carry actual HTTP payload: %s", lastDiagnostic)
			}
			wrong := "wrong-password"
			if tc.protocol == "vless" || tc.protocol == "vmess" {
				wrong = "b6db2f50-361a-4294-8bce-1df5f356764f"
			}
			if strings.HasPrefix(tc.method, "2022-") {
				wrong = base64.StdEncoding.EncodeToString([]byte("wrong-key-16byte"))
			}
			if request(wrong, tc.tls) || hits.Load() != 1 {
				t.Fatal("invalid authentication reached the origin")
			}
			if (tc.name == "Trojan TLS" || tc.name == "Hysteria2 QUIC" || tc.protocol == "tuic") && (request(password, false) || hits.Load() != 1) {
				t.Fatal("untrusted certificate was accepted without explicit opt-in")
			}
			if tc.obfs != "" {
				obfsPassword = "wrong-obfs"
				if request(password, tc.tls) || hits.Load() != 1 {
					t.Fatal("invalid obfuscation password reached the origin")
				}
			}
			if node.usesQUIC() {
				if tc.obfs != "" {
					obfsPassword = "fixture-obfs"
				}
				block, _ := pem.Decode([]byte(certificate))
				if block == nil {
					t.Fatal("fixture certificate is invalid")
				}
				hash := sha256.Sum256(block.Bytes)
				node.Options.CertificateSHA256 = hex.EncodeToString(hash[:])
				if !request(password, false) || hits.Load() != 2 {
					t.Fatal("pinned self-signed certificate did not carry payload")
				}
				node.Options.CertificateSHA256 = strings.Repeat("0", 64)
				for _, insecure := range []bool{false, true} {
					if request(password, insecure) || hits.Load() != 2 {
						t.Fatal("incorrect certificate pin bypassed verification")
					}
				}
			}
			if tc.protocol == "tuic" {
				node.Options.CertificateSHA256 = ""
				username = "b6db2f50-361a-4294-8bce-1df5f356764f"
				if request(password, true) || hits.Load() != 2 {
					t.Fatal("wrong TUIC UUID reached origin")
				}
			}
		})
	}
}

func TestPrivateCredentialRevealIsIdentityBound(t *testing.T) {
	requireCredentialStore(t)
	m := New("", t.TempDir())
	ctx := context.Background()
	payload, _ := json.Marshal(map[string]string{"id": "group-test", "username": "", "password": "https://example.test/sub?token=fixture"})
	result, err := m.execute(ctx, request{Method: "protect", Payload: payload})
	if err != nil {
		t.Fatal(err)
	}
	cipher := result.(map[string]any)["cipher"].(string)
	payload, _ = json.Marshal(map[string]string{"id": "group-test", "cipher": cipher})
	revealed, err := m.execute(ctx, request{Method: "reveal", Payload: payload})
	if err != nil || revealed.(credentials).Password != "https://example.test/sub?token=fixture" {
		t.Fatal("private reveal roundtrip failed")
	}
	payload, _ = json.Marshal(map[string]string{"id": "different-group", "cipher": cipher})
	if _, err = m.execute(ctx, request{Method: "reveal", Payload: payload}); err == nil {
		t.Fatal("credential decrypted for a different group")
	}
}
