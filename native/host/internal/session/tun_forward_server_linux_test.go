//go:build linux && !android

package session

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

const (
	forwardProxyAddress = "10.123.0.1:20000"
	forwardDNSAddress   = "10.123.0.1:20004"
	forwardIPv4         = "203.0.113.9"
	forwardIPv6         = "2001:db8:9::9"
	forwardEchoPort     = "20001"
	forwardRejected     = "DIRECT-BYPASS-REJECTED"
)

type forwardingServerReport struct {
	TCP4        int64 `json:"tcp4"`
	TCP6        int64 `json:"tcp6"`
	UDP4        int64 `json:"udp4"`
	UDP6        int64 `json:"udp6"`
	RejectedTCP int64 `json:"rejectedTcp"`
	RejectedUDP int64 `json:"rejectedUdp"`
	DNSQueries  int64 `json:"dnsQueries"`
}

type forwardingCounters struct{ tcp4, tcp6, udp4, udp6, rejectedTCP, rejectedUDP, dns atomic.Int64 }

func (counters *forwardingCounters) report() forwardingServerReport {
	return forwardingServerReport{counters.tcp4.Load(), counters.tcp6.Load(), counters.udp4.Load(), counters.udp6.Load(), counters.rejectedTCP.Load(), counters.rejectedUDP.Load(), counters.dns.Load()}
}

func forwardingIP(t *testing.T, args ...string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(t.Context(), time.Second)
	defer cancel()
	if output, err := exec.CommandContext(ctx, "ip", args...).CombinedOutput(); err != nil {
		t.Fatal("forwarding fixture network command failed", args, err, string(output))
	}
}

func waitForwardingDAD(t *testing.T) {
	t.Helper()
	for deadline := time.Now().Add(4 * time.Second); ; {
		output, err := exec.Command("ip", "-6", "-o", "address", "show", "tentative").Output()
		if err != nil {
			t.Fatal(err)
		}
		if len(bytes.TrimSpace(output)) == 0 {
			return
		}
		if time.Now().After(deadline) {
			t.Fatal("forwarding fixture IPv6 DAD did not complete")
		}
		time.Sleep(20 * time.Millisecond)
	}
}

// This real second network namespace contains both the locked SOCKS core and
// destinations. Origins reject sources from the caller namespace, so direct
// kernel routing cannot pass the proxy test merely because a server is local.
func TestLinuxTUNForwardingServerFixture(t *testing.T) {
	if os.Getenv("RAINLINK_FORWARD_SERVER_FIXTURE") != "1" {
		t.Skip("forwarding server subprocess only")
	}
	if os.Geteuid() != 0 || os.Getenv("RAINLINK_TEST_ROOT_TUN_NAMESPACE") != "isolated" {
		t.Fatal("forwarding server requires disposable root namespaces")
	}
	current, err := os.Readlink("/proc/self/ns/net")
	outer := os.Getenv("RAINLINK_FORWARD_OUTER_NAMESPACE")
	if err != nil || outer == "" || current == outer || current == os.Getenv("RAINLINK_TEST_PARENT_NETNS") {
		t.Fatal("forwarding server did not enter an independent network namespace", err)
	}
	commands := bufio.NewScanner(os.Stdin)
	fmt.Println("ready-for-link")
	if !commands.Scan() || commands.Text() != "configure" {
		t.Fatal("forwarding server was not configured")
	}
	for _, args := range [][]string{
		{"link", "set", "lo", "up"}, {"link", "set", "server0", "up"},
		{"address", "add", "10.123.0.1/30", "dev", "server0"},
		{"-6", "address", "add", "fd42:1234::1/64", "dev", "server0", "nodad"},
		{"address", "add", forwardIPv4 + "/32", "dev", "lo"},
		{"-6", "address", "add", forwardIPv6 + "/128", "dev", "lo", "nodad"},
	} {
		forwardingIP(t, args...)
	}
	waitForwardingDAD(t)
	ctx, cancel := context.WithCancel(t.Context())
	defer cancel()
	counters := &forwardingCounters{}
	var listeners, workers sync.WaitGroup
	var closeListeners []io.Closer
	var connections sync.Map
	defer func() {
		cancel()
		for _, listener := range closeListeners {
			_ = listener.Close()
		}
		// An accept already in progress may register a connection after Close.
		// Stop the accept loops before enumerating all live connection workers.
		listeners.Wait()
		connections.Range(func(key, value any) bool { _ = key.(net.Conn).Close(); return true })
		workers.Wait()
	}()
	reportError := func(operation string, err error) {
		if err != nil && ctx.Err() == nil && !errors.Is(err, net.ErrClosed) {
			t.Errorf("forwarding fixture %s failed: %v", operation, err)
		}
	}
	for _, family := range []struct {
		network, address, source string
		tcp, udp                 *atomic.Int64
	}{
		{"tcp4", net.JoinHostPort(forwardIPv4, forwardEchoPort), forwardIPv4, &counters.tcp4, &counters.udp4},
		{"tcp6", net.JoinHostPort(forwardIPv6, forwardEchoPort), forwardIPv6, &counters.tcp6, &counters.udp6},
	} {
		listener, err := net.Listen(family.network, family.address)
		if err != nil {
			t.Fatal(err)
		}
		closeListeners = append(closeListeners, listener)
		listeners.Add(1)
		go func() {
			defer listeners.Done()
			for {
				connection, err := listener.Accept()
				if err != nil {
					reportError("accept", err)
					return
				}
				connections.Store(connection, true)
				workers.Add(1)
				go func() {
					defer workers.Done()
					defer connection.Close()
					defer connections.Delete(connection)
					host, _, err := net.SplitHostPort(connection.RemoteAddr().String())
					if err != nil || host != family.source {
						counters.rejectedTCP.Add(1)
						_, err = io.WriteString(connection, forwardRejected)
						reportError("reject direct TCP", err)
						return
					}
					family.tcp.Add(1)
					_, err = io.Copy(connection, connection)
					reportError("echo TCP", err)
				}()
			}
		}()
		packet, err := net.ListenPacket(strings.Replace(family.network, "tcp", "udp", 1), family.address)
		if err != nil {
			t.Fatal(err)
		}
		closeListeners = append(closeListeners, packet)
		listeners.Add(1)
		go func() {
			defer listeners.Done()
			buffer := make([]byte, 2048)
			for {
				count, address, err := packet.ReadFrom(buffer)
				if err != nil {
					reportError("receive UDP", err)
					return
				}
				host, _, err := net.SplitHostPort(address.String())
				if err != nil || host != family.source {
					counters.rejectedUDP.Add(1)
					continue
				}
				family.udp.Add(1)
				if _, err = packet.WriteTo(buffer[:count], address); err != nil {
					reportError("echo UDP", err)
					return
				}
			}
		}()
	}
	resolver, err := net.ListenPacket("udp4", forwardDNSAddress)
	if err != nil {
		t.Fatal(err)
	}
	closeListeners = append(closeListeners, resolver)
	listeners.Add(1)
	go func() {
		defer listeners.Done()
		buffer := make([]byte, 2048)
		for {
			count, address, err := resolver.ReadFrom(buffer)
			if err != nil {
				reportError("receive DNS", err)
				return
			}
			answer := dnsFixtureAnswer(buffer[:count])
			if len(answer) == 0 {
				continue
			}
			counters.dns.Add(1)
			if _, err = resolver.WriteTo(answer, address); err != nil {
				reportError("reply DNS", err)
				return
			}
		}
	}()
	configuration, err := json.Marshal(map[string]any{
		"log": map[string]any{"level": "error"},
		"inbounds": []any{map[string]any{"type": "socks", "tag": "fixture-socks", "listen": "10.123.0.1", "listen_port": 20000,
			"users": []any{map[string]any{"username": "fixture-user", "password": "fixture-forward-password"}}}},
		"outbounds": []any{map[string]any{"type": "direct", "tag": "direct"}},
		"route":     map[string]any{"final": "direct"},
	})
	if err != nil {
		t.Fatal(err)
	}
	upstream := exec.Command(testCore(t), "run", "-c", "stdin")
	upstream.Stdin = bytes.NewReader(configuration)
	upstream.Env = []string{"PATH=", "LANG=C"}
	if err = upstream.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { _ = upstream.Process.Kill(); _ = upstream.Wait() }()
	for deadline := time.Now().Add(3 * time.Second); ; {
		connection, err := net.DialTimeout("tcp4", forwardProxyAddress, 100*time.Millisecond)
		if err == nil {
			_ = connection.Close()
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("locked SOCKS fixture did not become ready")
		}
		time.Sleep(20 * time.Millisecond)
	}
	fmt.Println("server-ready")
	for commands.Scan() {
		switch commands.Text() {
		case "report":
			if err = json.NewEncoder(os.Stdout).Encode(counters.report()); err != nil {
				t.Fatal(err)
			}
		case "exit":
			return
		default:
			t.Fatal("unknown forwarding server fixture command")
		}
		if ctx.Err() != nil {
			return
		}
	}
	if err = commands.Err(); err != nil {
		t.Fatal(err)
	}
}
