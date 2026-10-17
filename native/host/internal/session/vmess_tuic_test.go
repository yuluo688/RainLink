package session

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"io"
	"math/rand/v2"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os/exec"
	"strconv"
	"strings"
	"testing"
	"time"
)

const protocolFixtureUUID = "a6db2f50-361a-4294-8bce-1df5f356764f"

func protocolFixturePort(t *testing.T, quic bool) int {
	t.Helper()
	// Check both transports for non-QUIC fixtures. Asking either OS allocator
	// for port zero repeatedly can remain in a range reserved by the other
	// transport on Windows; sample explicit unprivileged candidates instead.
	const firstPort, portCount = 1024, 65536 - 1024
	for attempt := 0; attempt < 100; attempt++ {
		port := firstPort + rand.IntN(portCount)
		listener, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: port})
		if err != nil {
			continue
		}
		if !quic {
			tcp, err := net.ListenTCP("tcp4", &net.TCPAddr{IP: net.ParseIP("127.0.0.1"), Port: port})
			if err != nil {
				if closeErr := listener.Close(); closeErr != nil {
					t.Fatal(closeErr)
				}
				continue
			}
			if err = tcp.Close(); err != nil {
				_ = listener.Close()
				t.Fatal(err)
			}
		}
		if err = listener.Close(); err != nil {
			t.Fatal(err)
		}
		return port
	}
	t.Fatal("no jointly available protocol fixture port")
	return 0
}

func TestCoreChecksVMessAndTUICOptions(t *testing.T) {
	core := testCore(t)
	for _, protocol := range []string{"vmess", "tuic"} {
		for _, variant := range []string{"default", "extended", "alternate"} {
			t.Run(protocol+"/"+variant, func(t *testing.T) {
				node := Node{ID: "options", Name: "协议参数验证", Protocol: protocol, Server: "example.test", Port: 443, Revision: 1}
				auth := credentials{Password: protocolFixtureUUID}
				if protocol == "vmess" {
					node.Options = NodeOptions{Transport: "ws", Path: "/ws", VMessSecurity: "auto"}
					if variant == "extended" {
						node.Options.GlobalPadding, node.Options.AuthenticatedLength = true, true
						node.Options.PacketEncoding = "xudp"
					} else if variant == "alternate" {
						node.Options.AlterID, node.Options.VMessSecurity, node.Options.PacketEncoding = 64, "auto", "packetaddr"
					}
				} else {
					node.TLS = true
					node.Options = NodeOptions{Transport: "quic", CongestionControl: "bbr", UDPRelayMode: "native", HeartbeatMillis: 1500}
					auth = credentials{Username: protocolFixtureUUID, Password: "fixture-secret"}
					if variant == "extended" {
						node.Options.UDPOverStream, node.Options.ZeroRTTHandshake, node.Options.DisableSNI = true, true, true
					} else if variant == "alternate" {
						node.Options.UDPRelayMode = "quic"
					}
				}
				if err := node.validate(); err != nil {
					t.Fatal(err)
				}
				compiled, err := configuration(node, auth, "global", 19080, 19090, "fixture", upstreamNetwork{})
				if err != nil {
					t.Fatal(err)
				}
				if protocol == "tuic" && variant == "extended" && bytes.Contains(compiled, []byte(`"udp_relay_mode"`)) {
					t.Fatal("mutually exclusive relay options compiled together")
				}
				command := exec.Command(core, "check", "-c", "stdin")
				hideWindow(command)
				command.Stdin = bytes.NewReader(compiled)
				if output, err := command.CombinedOutput(); err != nil {
					t.Fatalf("core rejected compiler output: %v, %s", err, output)
				}
			})
		}
	}
}

func TestVMessTUICBoundariesAndChainCompatibility(t *testing.T) {
	vmess := Node{ID: "vmess", Name: "VMess", Revision: 1, Protocol: "vmess", Server: "example.test", Port: 443, Options: NodeOptions{Transport: "tcp", VMessSecurity: "auto"}}
	tuic := Node{ID: "tuic", Name: "TUIC", Revision: 1, Protocol: "tuic", Server: "example.test", Port: 443, TLS: true, Options: NodeOptions{Transport: "quic", CongestionControl: "cubic", UDPRelayMode: "native", HeartbeatMillis: 10000}}
	for _, change := range []func(*Node){
		func(n *Node) { n.TLS = false }, func(n *Node) { n.Options.Transport = "ws" },
		func(n *Node) { n.Options.CongestionControl = "unsupported" },
		func(n *Node) { n.Options.UDPRelayMode = "unsupported" },
		func(n *Node) { n.Options.UDPOverStream = true; n.Options.UDPRelayMode = "quic" },
		func(n *Node) { n.Options.HeartbeatMillis = 1 }, func(n *Node) { n.Options.HeartbeatMillis = 3600001 },
		func(n *Node) { n.Options.Fingerprint = "chrome" }, func(n *Node) { n.Options.Obfs = "salamander" },
		func(n *Node) { n.Options.CertificateSHA256 = "bad-pin" },
	} {
		invalid := tuic
		change(&invalid)
		if invalid.validate() == nil {
			t.Fatal("invalid TUIC accepted")
		}
	}
	for _, change := range []func(*Node){
		func(n *Node) { n.Options.VMessSecurity = "unsupported" },
		func(n *Node) { n.Options.AlterID = -1 }, func(n *Node) { n.Options.AlterID = 65536 },
		func(n *Node) { n.Options.PacketEncoding = "unsupported" },
		func(n *Node) { n.Options.UDPOverStream = true }, func(n *Node) { n.Options.DisableSNI = true },
	} {
		invalid := vmess
		change(&invalid)
		if invalid.validate() == nil {
			t.Fatal("invalid VMess accepted")
		}
	}
	if vmess.validateCredentials(credentials{Password: "invalid"}) == nil || tuic.validateCredentials(credentials{Username: "invalid", Password: "fixture"}) == nil {
		t.Fatal("malformed UUID accepted")
	}
	if err := tuic.validateCredentials(credentials{Username: protocolFixtureUUID}); err != nil {
		t.Fatal("optional empty TUIC password rejected", err)
	}
	httpNode := Node{ID: "http", Name: "HTTP", Protocol: "http", Server: "example.test", Port: 80, Revision: 1}
	chain := ChainSnapshot{ID: "chain", Name: "协议组合", Revision: 1, Hops: []Node{httpNode, tuic}}
	if chain.validate() == nil {
		t.Fatal("TUIC behind TCP-only HTTP was accepted")
	}
	chain.Hops = []Node{tuic, httpNode}
	if err := chain.validate(); err != nil {
		t.Fatal(err)
	}
	chain.Hops = []Node{vmess, tuic}
	if err := chain.validate(); err != nil {
		t.Fatal(err)
	}
}

// This goes through the actual mixed inbound and the upstream protocol's UDP
// relay. An HTTP response through a QUIC connection alone does not prove UDP.
func TestRealCoreVMessAndTUICDatagrams(t *testing.T) {
	core := testCore(t)
	certificate, key := fixtureCertificate(t)
	for _, tc := range []struct{ protocol, mode string }{
		{"tuic", "native"}, {"tuic", "quic"}, {"tuic", "stream"},
		{"vmess", ""}, {"vmess", "xudp"}, {"vmess", "packetaddr"},
	} {
		t.Run(tc.protocol+"/"+tc.mode, func(t *testing.T) {
			origin, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.ParseIP("127.0.0.1")})
			if err != nil {
				t.Fatal(err)
			}
			done := make(chan struct{})
			go func() {
				defer close(done)
				buffer := make([]byte, 2048)
				for {
					n, address, readErr := origin.ReadFromUDP(buffer)
					if readErr != nil {
						return
					}
					if _, writeErr := origin.WriteToUDP(buffer[:n], address); writeErr != nil {
						return
					}
				}
			}()
			t.Cleanup(func() { origin.Close(); <-done })
			port := protocolFixturePort(t, tc.protocol == "tuic")
			inbound := map[string]any{"type": tc.protocol, "listen": "127.0.0.1", "listen_port": port}
			auth := credentials{Password: protocolFixtureUUID}
			node := Node{ID: "udp", Name: "本机 UDP 验收", Protocol: tc.protocol, Revision: 1, Server: "127.0.0.1", Port: port, Options: NodeOptions{Transport: "tcp", VMessSecurity: "auto", PacketEncoding: tc.mode}}
			inbound["users"] = []any{map[string]any{"uuid": protocolFixtureUUID}}
			if tc.protocol == "tuic" {
				auth = credentials{Username: protocolFixtureUUID, Password: "fixture-password"}
				inbound["users"] = []any{map[string]any{"uuid": auth.Username, "password": auth.Password}}
				inbound["tls"] = map[string]any{"enabled": true, "certificate": []string{certificate}, "key": []string{key}}
				node.TLS = true
				node.Options = NodeOptions{Transport: "quic", ServerName: "localhost", Insecure: true, CongestionControl: "bbr", UDPRelayMode: tc.mode}
				if tc.mode == "stream" {
					node.Options.UDPRelayMode = "native"
					node.Options.UDPOverStream = true
				}
			}
			// packetaddr supplies destinations inside each datagram, after route
			// matching. Only this test's UDP traffic is accepted; probes are off.
			config, err := json.Marshal(map[string]any{"log": map[string]any{"level": "error"}, "inbounds": []any{inbound}, "outbounds": []any{map[string]any{"type": "direct", "tag": "direct"}}, "route": map[string]any{"rules": []any{map[string]any{"network": "udp", "action": "route", "outbound": "direct"}, map[string]any{"action": "reject"}}}})
			if err != nil {
				t.Fatal(err)
			}
			upstream := exec.Command(core, "run", "-c", "stdin")
			hideWindow(upstream)
			upstream.Stdin = bytes.NewReader(config)
			if err = upstream.Start(); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { upstream.Process.Kill(); upstream.Wait() })
			if node.usesQUIC() {
				time.Sleep(200 * time.Millisecond)
			} else {
				ready := false
				for deadline := time.Now().Add(3 * time.Second); time.Now().Before(deadline); {
					c, e := net.DialTimeout("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(port)), 100*time.Millisecond)
					if e == nil {
						c.Close()
						ready = true
						break
					}
					time.Sleep(25 * time.Millisecond)
				}
				if !ready {
					t.Fatal("protocol fixture did not start")
				}
			}
			raw, err := json.Marshal(auth)
			if err != nil {
				t.Fatal(err)
			}
			node.Credential, err = seal(t.Context(), raw, node.ID)
			if err != nil {
				t.Fatal(err)
			}
			manager := New(core, t.TempDir())
			t.Cleanup(func() {
				if e := manager.Disconnect(); e != nil {
					t.Error(e)
				}
			})
			ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
			defer cancel()
			snapshot, err := manager.connectTarget(ctx, node, nil, "global", false, nil, false)
			if err != nil {
				t.Fatal(err)
			}
			socksUDPEcho(t, snapshot.ProxyPort, origin.LocalAddr().(*net.UDPAddr).Port)
		})
	}
}

func socksUDPEcho(t *testing.T, proxyPort, originPort int) {
	t.Helper()
	control, err := net.DialTimeout("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(proxyPort)), time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer control.Close()
	if err = control.SetDeadline(time.Now().Add(6 * time.Second)); err != nil {
		t.Fatal(err)
	}
	if _, err = control.Write([]byte{5, 1, 0}); err != nil {
		t.Fatal(err)
	}
	hello := make([]byte, 2)
	if _, err = io.ReadFull(control, hello); err != nil || !bytes.Equal(hello, []byte{5, 0}) {
		t.Fatal("SOCKS negotiation failed", err)
	}
	if _, err = control.Write([]byte{5, 3, 0, 1, 0, 0, 0, 0, 0, 0}); err != nil {
		t.Fatal(err)
	}
	header := make([]byte, 4)
	if _, err = io.ReadFull(control, header); err != nil || header[1] != 0 {
		t.Fatal("UDP association failed", err)
	}
	length := 0
	switch header[3] {
	case 1:
		length = 4
	case 4:
		length = 16
	default:
		t.Fatal("unexpected UDP relay address type")
	}
	bound := make([]byte, length+2)
	if _, err = io.ReadFull(control, bound); err != nil {
		t.Fatal(err)
	}
	ip := net.IP(bound[:length])
	if ip.IsUnspecified() {
		ip = net.ParseIP("127.0.0.1")
	}
	relay := &net.UDPAddr{IP: ip, Port: int(binary.BigEndian.Uint16(bound[length:]))}
	packet, err := net.DialUDP("udp", nil, relay)
	if err != nil {
		t.Fatal(err)
	}
	defer packet.Close()
	if err = packet.SetDeadline(time.Now().Add(6 * time.Second)); err != nil {
		t.Fatal(err)
	}
	payload := []byte("rainlink-real-datagram")
	request := append([]byte{0, 0, 0, 1, 127, 0, 0, 1, byte(originPort >> 8), byte(originPort)}, payload...)
	if _, err = packet.Write(request); err != nil {
		t.Fatal(err)
	}
	buffer := make([]byte, 2048)
	count, err := packet.Read(buffer)
	if err != nil {
		t.Fatal("protocol did not carry UDP payload", err)
	}
	if count != len(request) || !bytes.Equal(buffer[:count], request) {
		t.Fatal("unexpected UDP response", strings.TrimSpace(string(buffer[:count])))
	}
}

func TestRealCoreVMessTUICChains(t *testing.T) {
	core := testCore(t)
	certificate, key := fixtureCertificate(t)
	vmess := Node{ID: "chain-vmess", Name: "VMess 入口", Revision: 1, Protocol: "vmess", Server: "127.0.0.1", Port: protocolFixturePort(t, false), Options: NodeOptions{Transport: "tcp", VMessSecurity: "auto"}}
	tuic := Node{ID: "chain-tuic", Name: "TUIC 出口", Revision: 1, Protocol: "tuic", Server: "127.0.0.1", Port: protocolFixturePort(t, true), TLS: true, Options: NodeOptions{Transport: "quic", ServerName: "localhost", Insecure: true, CongestionControl: "cubic", UDPRelayMode: "native"}}
	for _, target := range []struct {
		node *Node
		auth credentials
	}{
		{&vmess, credentials{Password: protocolFixtureUUID}},
		{&tuic, credentials{Username: protocolFixtureUUID, Password: "chain-fixture"}},
	} {
		raw, err := json.Marshal(target.auth)
		if err != nil {
			t.Fatal(err)
		}
		target.node.Credential, err = seal(t.Context(), raw, target.node.ID)
		if err != nil {
			t.Fatal(err)
		}
	}
	config, err := json.Marshal(map[string]any{
		"log": map[string]any{"level": "info"},
		"inbounds": []any{
			map[string]any{"type": "vmess", "tag": "v-in", "listen": "127.0.0.1", "listen_port": vmess.Port, "users": []any{map[string]any{"uuid": protocolFixtureUUID}}},
			map[string]any{"type": "tuic", "tag": "q-in", "listen": "127.0.0.1", "listen_port": tuic.Port, "users": []any{map[string]any{"uuid": protocolFixtureUUID, "password": "chain-fixture"}}, "tls": map[string]any{"enabled": true, "certificate": []string{certificate}, "key": []string{key}}},
		},
		"outbounds": []any{map[string]any{"type": "direct", "tag": "direct"}},
		"route":     map[string]any{"rules": []any{map[string]any{"ip_cidr": []string{"127.0.0.0/8"}, "action": "route", "outbound": "direct"}, map[string]any{"action": "reject"}}},
	})
	if err != nil {
		t.Fatal(err)
	}
	fixtureLogs := newLogBuffer()
	writer := &coreLogWriter{logs: fixtureLogs}
	upstream := exec.Command(core, "run", "-c", "stdin")
	hideWindow(upstream)
	upstream.Stdin = bytes.NewReader(config)
	upstream.Stdout, upstream.Stderr = writer, writer
	if err = upstream.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { upstream.Process.Kill(); upstream.Wait() })
	ready := false
	for deadline := time.Now().Add(3 * time.Second); time.Now().Before(deadline); {
		connection, e := net.DialTimeout("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(vmess.Port)), 100*time.Millisecond)
		if e == nil {
			connection.Close()
			ready = true
			break
		}
		time.Sleep(25 * time.Millisecond)
	}
	if !ready {
		t.Fatal("mixed protocol fixture did not start")
	}
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "verified mixed chain") }))
	defer origin.Close()
	udp, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.ParseIP("127.0.0.1")})
	if err != nil {
		t.Fatal(err)
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		buffer := make([]byte, 2048)
		for {
			n, address, e := udp.ReadFromUDP(buffer)
			if e != nil {
				return
			}
			if _, e = udp.WriteToUDP(buffer[:n], address); e != nil {
				return
			}
		}
	}()
	t.Cleanup(func() { udp.Close(); <-done })
	for _, hops := range [][]Node{{vmess, tuic}, {tuic, vmess}} {
		t.Run(hops[0].Protocol+"->"+hops[1].Protocol, func(t *testing.T) {
			chain := ChainSnapshot{ID: "mixed-chain", Name: "双协议链", Revision: 1, Hops: hops}
			manager := New(core, t.TempDir())
			t.Cleanup(func() {
				if e := manager.Disconnect(); e != nil {
					t.Error(e)
				}
			})
			ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
			defer cancel()
			snapshot, e := manager.connectTarget(ctx, Node{}, &chain, "global", false, nil, false)
			if e != nil {
				t.Fatal(e)
			}
			proxy, _ := url.Parse("http://127.0.0.1:" + strconv.Itoa(snapshot.ProxyPort))
			client := &http.Client{Timeout: 6 * time.Second, Transport: &http.Transport{Proxy: http.ProxyURL(proxy)}}
			defer client.CloseIdleConnections()
			response, e := client.Get(origin.URL)
			if e != nil {
				t.Fatal(e)
			}
			body, e := io.ReadAll(response.Body)
			response.Body.Close()
			if e != nil || string(body) != "verified mixed chain" {
				t.Fatal("mixed chain payload failed", e)
			}
			socksUDPEcho(t, snapshot.ProxyPort, udp.LocalAddr().(*net.UDPAddr).Port)
			// Confirm the entry actually received traffic for the next hop's
			// listener; origin success alone would not detect a direct bypass.
			observed := false
			cursor := int64(0)
			for {
				batch := fixtureLogs.read(fixtureLogs.id, cursor)
				for _, entry := range batch.Entries {
					if strings.Contains(entry.Message, "inbound/"+hops[0].Protocol) && strings.Contains(entry.Message, "127.0.0.1:"+strconv.Itoa(hops[1].Port)) {
						observed = true
					}
				}
				if !batch.More {
					break
				}
				cursor = batch.Cursor
			}
			if !observed {
				t.Fatal("entry did not carry traffic to the next hop")
			}
		})
	}
}
