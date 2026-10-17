//go:build linux && !android

package session

import (
	"bufio"
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"

	"rainlink.local/host/internal/linuxnet"
	"rainlink.local/host/internal/linuxprocess"
	"rainlink.local/host/internal/linuxtun"
)

type forwardingConnection struct {
	Metadata struct {
		Type            string `json:"type"`
		Network         string `json:"network"`
		DestinationIP   string `json:"destinationIP"`
		DestinationPort string `json:"destinationPort"`
	} `json:"metadata"`
	Chains   []string `json:"chains"`
	Upload   int64    `json:"upload"`
	Download int64    `json:"download"`
}

type forwardingClientReport struct {
	Connections    []forwardingConnection `json:"connections"`
	DNSChecks      int                    `json:"dnsChecks"`
	DirectRejected int                    `json:"directRejected"`
}

func forwardingDial(t *testing.T, network, address string) net.Conn {
	t.Helper()
	connection, err := net.DialTimeout(network, address, 2*time.Second)
	if err != nil {
		t.Fatal("forwarding dial failed", network, address, err)
	}
	t.Cleanup(func() { _ = connection.Close() })
	if err = connection.SetDeadline(time.Now().Add(2 * time.Second)); err != nil {
		t.Fatal(err)
	}
	return connection
}

func forwardingRejectDirect(t *testing.T) int {
	t.Helper()
	checks := 0
	for _, family := range []struct{ network, host string }{{"tcp4", forwardIPv4}, {"tcp6", forwardIPv6}, {"udp4", forwardIPv4}, {"udp6", forwardIPv6}} {
		connection := forwardingDial(t, family.network, net.JoinHostPort(family.host, forwardEchoPort))
		if strings.HasPrefix(family.network, "tcp") {
			data, err := io.ReadAll(connection)
			if err != nil || string(data) != forwardRejected {
				t.Fatal("origin accepted a direct TCP connection", family.network, err)
			}
		} else {
			if err := connection.SetReadDeadline(time.Now().Add(200 * time.Millisecond)); err != nil {
				t.Fatal(err)
			}
			if _, err := connection.Write([]byte("direct-must-fail")); err != nil {
				t.Fatal(err)
			}
			var buffer [64]byte
			_, err := connection.Read(buffer[:])
			var timeout net.Error
			if !errors.As(err, &timeout) || !timeout.Timeout() {
				t.Fatal("origin accepted a direct UDP packet", family.network, err)
			}
		}
		if err := connection.Close(); err != nil {
			t.Fatal(err)
		}
		checks++
	}
	return checks
}

func forwardingDNS(t *testing.T, mode string) int {
	t.Helper()
	checks := 0
	for _, family := range []struct{ network, host string }{{"udp4", "198.51.100.53"}, {"tcp4", "198.51.100.53"}, {"udp6", "2001:db8:53::53"}, {"tcp6", "2001:db8:53::53"}} {
		// Every request uses a different qname so resolver counters cannot be
		// satisfied by a previous answer in the core DNS cache.
		label := mode + family.network
		query := []byte{0x52, 0x4c, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, byte(len(label))}
		query = append(query, label...)
		query = append(query, 4, 't', 'e', 's', 't', 0, 0, 1, 0, 1)
		connection := forwardingDial(t, family.network, net.JoinHostPort(family.host, "53"))
		outbound := query
		if strings.HasPrefix(family.network, "tcp") {
			outbound = append(binary.BigEndian.AppendUint16(nil, uint16(len(query))), query...)
		}
		if _, err := connection.Write(outbound); err != nil {
			t.Fatal("DNS write failed", family.network, err)
		}
		var packet []byte
		if strings.HasPrefix(family.network, "tcp") {
			var header [2]byte
			if _, err := io.ReadFull(connection, header[:]); err != nil {
				t.Fatal("TCP DNS header failed", family.network, err)
			}
			packet = make([]byte, binary.BigEndian.Uint16(header[:]))
			if _, err := io.ReadFull(connection, packet); err != nil {
				t.Fatal("TCP DNS answer failed", family.network, err)
			}
		} else {
			packet = make([]byte, 2048)
			count, err := connection.Read(packet)
			if err != nil {
				t.Fatal("UDP DNS answer failed", family.network, err)
			}
			packet = packet[:count]
		}
		addresses, err := dohAddresses(packet, query)
		if err != nil || len(addresses) != 1 || addresses[0].String() != "203.0.113.88" {
			t.Fatal("DNS was not intercepted by the configured resolver", family.network, err)
		}
		if err = connection.Close(); err != nil {
			t.Fatal(err)
		}
		checks++
	}
	return checks
}

// This process has a real ordinary UID. Data requests use raw OS sockets;
// neither HTTP proxy environment variables nor the mixed listener are used.
func TestLinuxTUNForwardingClientFixture(t *testing.T) {
	if os.Getenv("RAINLINK_PERMISSION_CLIENT_FIXTURE") != "1" {
		t.Skip("ordinary-user forwarding subprocess only")
	}
	if os.Geteuid() != 65534 {
		t.Fatal("forwarding client must be an ordinary user")
	}
	ctx, cancel := context.WithTimeout(t.Context(), 22*time.Second)
	defer cancel()
	report := forwardingClientReport{DirectRejected: forwardingRejectDirect(t)}
	node := mobileNode("forwarding-fixture", "socks")
	node.Server, node.Port = "10.123.0.1", 20000
	settings := defaultRuntimeSettings()
	settings.DNSMode, settings.Resolver, settings.IPv6, settings.LogLevel = "custom", "udp://"+forwardDNSAddress, true, "error"
	request := MobileRequest{Node: &node, Mode: "global", TUN: true, RuntimeSettings: &settings,
		Secrets: map[string]MobileCredentials{node.Credential: {Username: "fixture-user", Password: "fixture-forward-password"}}}
	startup, finishStartup := context.WithCancel(ctx)
	tunClient, err := dialLinuxTUNClient(startup, os.Getenv("RAINLINK_PERMISSION_SOCKET"), request)
	finishStartup()
	if err != nil {
		t.Fatal("native forwarding client did not confirm capture", err)
	}
	defer tunClient.close()
	// Cancelling the completed start RPC must not tear down its live session.
	started := tunClient.started
	client := &http.Client{Transport: &http.Transport{Proxy: nil}}
	defer client.CloseIdleConnections()
	core := &runningCore{client: client, api: "http://" + net.JoinHostPort("127.0.0.1", strconv.Itoa(started.APIPort)), secret: started.APISecret}
	fmt.Println("connected")
	commands := bufio.NewScanner(os.Stdin)
	if !commands.Scan() || commands.Text() != "exercise" {
		t.Fatal("forwarding exercise instruction missing", commands.Err())
	}
	for _, family := range []struct{ network, host string }{{"tcp4", forwardIPv4}, {"tcp6", forwardIPv6}, {"udp4", forwardIPv4}, {"udp6", forwardIPv6}} {
		stream := forwardingDial(t, family.network, net.JoinHostPort(family.host, forwardEchoPort))
		payload := []byte("rainlink-tun-" + family.network + "-exact-echo")
		if _, err = stream.Write(payload); err != nil {
			t.Fatal("TUN write failed", family.network, err)
		}
		answer := make([]byte, len(payload))
		if _, err = io.ReadFull(stream, answer); err != nil || !bytes.Equal(payload, answer) {
			t.Fatal("TUN echo failed", family.network, err)
		}
		if err = stream.SetDeadline(time.Time{}); err != nil {
			t.Fatal(err)
		}
	}
	for deadline := time.Now().Add(2 * time.Second); ; {
		var data struct {
			Connections []forwardingConnection `json:"connections"`
		}
		if err = core.apiJSON(ctx, http.MethodGet, "/connections", nil, &data); err != nil {
			t.Fatal("TUN telemetry failed", err)
		}
		found := map[string]bool{}
		var confirmed []forwardingConnection
		for _, item := range data.Connections {
			if item.Metadata.DestinationPort != forwardEchoPort || (item.Metadata.DestinationIP != forwardIPv4 && item.Metadata.DestinationIP != forwardIPv6) {
				continue
			}
			if item.Metadata.Type != "tun/rainlink-tun" || !slices.Contains(item.Chains, "proxy") || item.Upload <= 0 || item.Download <= 0 {
				continue
			}
			found[item.Metadata.Network+"/"+item.Metadata.DestinationIP] = true
			confirmed = append(confirmed, item)
		}
		if len(found) == 4 {
			report.Connections = confirmed
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("four live TUN proxy connections with bidirectional bytes were not observed", data.Connections)
		}
		time.Sleep(20 * time.Millisecond)
	}
	report.DNSChecks += forwardingDNS(t, "global")
	if err = core.apiJSON(ctx, http.MethodPatch, "/configs", map[string]string{"mode": "Direct"}, nil); err != nil {
		t.Fatal(err)
	}
	report.DirectRejected += forwardingRejectDirect(t)
	report.DNSChecks += forwardingDNS(t, "direct")
	if err = core.apiJSON(ctx, http.MethodPatch, "/configs", map[string]string{"mode": "Global"}, nil); err != nil {
		t.Fatal(err)
	}
	if err = json.NewEncoder(os.Stdout).Encode(report); err != nil {
		t.Fatal(err)
	}
	if !commands.Scan() || commands.Text() != "stop" {
		t.Fatal("forwarding stop instruction missing", commands.Err())
	}
	if err = tunClient.stop(ctx); err != nil {
		t.Fatal("native forwarding cleanup was not acknowledged", err)
	}
	if err = tunClient.stop(ctx); err != nil {
		t.Fatal("repeated native stop lost its confirmed result", err)
	}
	fmt.Println("stopped")
}

type forwardingServer struct {
	command *exec.Cmd
	input   io.WriteCloser
	output  *bufio.Reader
	reaped  bool
}

func startForwardingServer(t *testing.T) *forwardingServer {
	t.Helper()
	namespace, err := os.Readlink("/proc/self/ns/net")
	if err != nil {
		t.Fatal(err)
	}
	command := exec.Command(os.Args[0], "-test.run=^TestLinuxTUNForwardingServerFixture$", "-test.timeout=180s")
	command.SysProcAttr = &syscall.SysProcAttr{Cloneflags: syscall.CLONE_NEWNET, Setsid: true}
	command.Env = append(os.Environ(), "RAINLINK_FORWARD_SERVER_FIXTURE=1", "RAINLINK_FORWARD_OUTER_NAMESPACE="+namespace)
	input, err := command.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	output, err := command.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	command.Stderr = os.Stderr
	server := &forwardingServer{command: command, input: input, output: bufio.NewReader(output)}
	t.Cleanup(func() {
		_ = input.Close()
		if !server.reaped {
			// Include the upstream core when a failed fixture cannot run its
			// defers; otherwise it would keep the second namespace and veth alive.
			_ = syscall.Kill(-command.Process.Pid, syscall.SIGKILL)
			_ = command.Wait()
		}
	})
	if err = command.Start(); err != nil {
		server.reaped = true
		t.Fatal(err)
	}
	server.expect(t, "ready-for-link")
	forwardingIP(t, "link", "add", "forward0", "type", "veth", "peer", "name", "server0")
	forwardingIP(t, "link", "set", "server0", "netns", strconv.Itoa(command.Process.Pid))
	for _, args := range [][]string{
		{"link", "set", "forward0", "up"},
		{"address", "add", "10.123.0.2/30", "dev", "forward0"},
		{"-6", "address", "add", "fd42:1234::2/64", "dev", "forward0", "nodad"},
		{"route", "add", "default", "via", "10.123.0.1", "dev", "forward0", "metric", "5"},
		{"-6", "route", "add", "default", "via", "fd42:1234::1", "dev", "forward0", "metric", "5"},
	} {
		forwardingIP(t, args...)
	}
	server.send(t, "configure")
	server.expect(t, "server-ready")
	waitForwardingDAD(t)
	return server
}

func (server *forwardingServer) send(t *testing.T, command string) {
	t.Helper()
	if _, err := io.WriteString(server.input, command+"\n"); err != nil {
		t.Fatal(err)
	}
}

func (server *forwardingServer) expect(t *testing.T, want string) {
	t.Helper()
	line, err := server.output.ReadString('\n')
	if err != nil || strings.TrimSpace(line) != want {
		t.Fatal("forwarding server stage failed", want, strings.TrimSpace(line), err)
	}
}

func TestIsolatedLinuxTUNForwarding(t *testing.T) {
	if os.Geteuid() != 0 || os.Getenv("RAINLINK_TEST_ROOT_TUN_NAMESPACE") != "isolated" {
		t.Skip("requires disposable root namespaces")
	}
	namespace, err := os.Readlink("/proc/self/ns/net")
	parent := os.Getenv("RAINLINK_TEST_PARENT_NETNS")
	if err != nil || parent == "" || namespace == parent {
		t.Fatal("forwarding fixture is not isolated", err)
	}
	ctx, cancel := context.WithTimeout(t.Context(), 35*time.Second)
	defer cancel()
	beforeWire, err := linuxnet.Read(ctx)
	if err != nil {
		t.Fatal(err)
	}
	server := startForwardingServer(t)
	before, err := linuxnet.Read(ctx)
	if err != nil {
		t.Fatal(err)
	}
	const pkcheck = "/usr/bin/pkcheck"
	if _, err = os.Lstat(pkcheck); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("fixture must not replace the system authorizer", err)
	}
	if err = os.WriteFile(pkcheck, []byte("#!/bin/sh\nexit 0\n"), 0755); err != nil {
		t.Fatal(err)
	}
	defer os.Remove(pkcheck)
	fixture := startTUNPermissionClientFixture(t, false, "TestLinuxTUNForwardingClientFixture")
	fixture.expect(t, "connected")
	var journal struct {
		Core      linuxprocess.Identity  `json:"core"`
		Resources linuxtun.Specification `json:"resources"`
	}
	data, err := os.ReadFile("/run/rainlink-tun/capture-recovery.json")
	if err != nil || json.Unmarshal(data, &journal) != nil || !journal.Core.Valid() {
		t.Fatal("forwarding core has no persistent recovery identity", err)
	}
	if err = confirmManagedTUN(ctx, journal.Resources); err != nil {
		t.Fatal(err)
	}
	ready, err := linuxnet.Read(ctx)
	if err != nil {
		t.Fatal(err)
	}
	fixture.command(t, "exercise")
	line, err := fixture.output.ReadString('\n')
	var clientReport forwardingClientReport
	if err != nil || json.Unmarshal([]byte(line), &clientReport) != nil || len(clientReport.Connections) != 4 || clientReport.DNSChecks != 8 || clientReport.DirectRejected != 8 {
		if strings.HasPrefix(line, "--- FAIL:") {
			rest, _ := io.ReadAll(fixture.output)
			line += string(rest)
		}
		t.Fatal("ordinary forwarding client did not confirm all traffic", strings.TrimSpace(line), err, fixture.diagnostics.String())
	}
	server.send(t, "report")
	line, err = server.output.ReadString('\n')
	var serverReport forwardingServerReport
	if err != nil || json.Unmarshal([]byte(line), &serverReport) != nil || serverReport.TCP4 < 1 || serverReport.TCP6 < 1 || serverReport.UDP4 < 1 || serverReport.UDP6 < 1 || serverReport.RejectedTCP != 4 || serverReport.RejectedUDP != 4 || serverReport.DNSQueries < 8 {
		t.Fatal("independent origins did not confirm proxy forwarding", strings.TrimSpace(line), err)
	}
	fixture.command(t, "stop")
	fixture.expect(t, "stopped")
	fixture.wait(t, true, true)
	if alive, err := linuxprocess.Alive(journal.Core); err != nil || alive {
		t.Fatal("forwarding core remained alive", err)
	}
	if _, err = os.Stat("/run/rainlink-tun/capture-recovery.json"); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("forwarding cleanup retained its journal", err)
	}
	after, err := linuxnet.Read(ctx)
	if err != nil || !reflect.DeepEqual(before, after) {
		t.Fatal("forwarding session did not restore the complete network", err)
	}
	server.send(t, "exit")
	rest, err := io.ReadAll(server.output)
	if err != nil {
		t.Fatal(err)
	}
	err = server.command.Wait()
	server.reaped = true
	if err != nil || strings.TrimSpace(string(rest)) != "PASS" {
		t.Fatal("forwarding server did not terminate cleanly", strings.TrimSpace(string(rest)), err)
	}
	// The final process can exit before the kernel's deferred namespace
	// destruction removes its veth peer and routes. Wait for exact equality;
	// never hide the wire or omit any preexisting network fields.
	afterWire, err := linuxnet.Read(ctx)
	for deadline := time.Now().Add(4 * time.Second); err == nil && !reflect.DeepEqual(beforeWire, afterWire) && time.Now().Before(deadline); {
		time.Sleep(20 * time.Millisecond)
		afterWire, err = linuxnet.Read(ctx)
	}
	if directory := os.Getenv("RAINLINK_TEST_NETWORK_EVIDENCE_DIR"); directory != "" {
		evidence := map[string]any{"client": clientReport, "server": serverReport, "resources": journal.Resources,
			"beforeWire": beforeWire, "before": before, "ready": ready, "after": after, "afterWire": afterWire}
		data, err := json.MarshalIndent(evidence, "", "  ")
		if err != nil {
			t.Fatal(err)
		}
		if err = os.WriteFile(filepath.Join(directory, "forwarding-state.json"), append(data, '\n'), 0600); err != nil {
			t.Fatal(err)
		}
	}
	if err != nil || !reflect.DeepEqual(beforeWire, afterWire) {
		t.Fatal("forwarding wire changed preexisting interfaces, routes or rules", err)
	}
}
