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
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"golang.org/x/sys/unix"
	"rainlink.local/host/internal/linuxnet"
	"rainlink.local/host/internal/linuxprocess"
	"rainlink.local/host/internal/linuxtun"
)

// This fixture speaks the ordinary host's public protocol and uses an actual
// Secret Service. It never sends plaintext credentials to connect or uses the
// mixed listener for data. The root test controls failures in another process.
func TestLinuxTUNManagerClientFixture(t *testing.T) {
	if os.Getenv("RAINLINK_TEST_MANAGER_CLIENT") != "1" {
		t.Skip("ordinary-user managed-host subprocess only")
	}
	if os.Geteuid() != 65534 {
		t.Fatal("managed host must use an ordinary UID")
	}
	ctx, cancel := context.WithTimeout(t.Context(), 30*time.Second)
	defer cancel()
	scenario := os.Getenv("RAINLINK_MANAGER_SCENARIO")
	t.Setenv("RAINLINK_TEST_SECRET_SERVICE", "isolated")
	t.Setenv("XDG_CURRENT_DESKTOP", "RainLink-Unsupported")
	if scenario == "system-proxy" {
		t.Setenv("XDG_CURRENT_DESKTOP", "GNOME")
		t.Setenv("GSETTINGS_BACKEND", "dconf")
	}
	host := newLinuxTestHost(t, ctx, "serve")
	if failure := host.rpc("hello", nil, nil); failure != nil {
		t.Fatal(failure)
	}
	protect := func(id string) Node {
		t.Helper()
		var result struct {
			Cipher string `json:"cipher"`
		}
		if failure := host.rpc("protect", map[string]string{"id": id, "username": "fixture-user", "password": "fixture-forward-password"}, &result); failure != nil || !strings.HasPrefix(result.Cipher, "rls1.") {
			t.Fatal("actual keyring did not protect node credentials", failure)
		}
		node := mobileNode(id, "socks")
		node.Name, node.Server, node.Port, node.Credential = "隔离节点 "+id, "10.123.0.1", 20000, result.Cipher
		return node
	}
	node := protect("manager-entry")
	settings := defaultRuntimeSettings()
	settings.DNSMode, settings.Resolver, settings.IPv6, settings.LogLevel = "custom", "udp://"+forwardDNSAddress, true, "error"
	if scenario == "stop" || scenario == "core-start-failure" {
		settings.LogLevel = "debug"
	}
	payload := map[string]any{"node": node, "mode": "global", "tun": true, "runtimeSettings": settings}
	if scenario == "core-start-failure" {
		// Retain this actual ordinary-user listener while the root core tries
		// to bind it. Configuration check succeeds, then real startup fails.
		listener, err := net.Listen("tcp4", "127.0.0.1:0")
		if err != nil {
			t.Fatal(err)
		}
		defer listener.Close()
		settings.ProxyPort = listener.Addr().(*net.TCPAddr).Port
		payload["runtimeSettings"] = settings
		if failure := host.rpc("connect", payload, nil); failure == nil || failure.Code != "tun_start_failed" {
			t.Fatal("occupied mixed port did not fail actual root core startup", failure)
		}
		logs := waitManagedTUNLogEntries(t, host, LogBatch{}, func(entries []LogEntry) bool {
			for _, entry := range entries {
				if entry.Source == "core" && entry.Level == "error" && strings.Contains(entry.Message, "address already in use") {
					return true
				}
			}
			return false
		})
		data, err := json.MarshalIndent(map[string]any{"startupFailureLogs": logs}, "", "  ")
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(os.Getenv("RAINLINK_MANAGER_FIXTURE_HOME"), "observed.json"), append(data, '\n'), 0600); err != nil {
			t.Fatal(err)
		}
		fmt.Println("rejected")
		host.finish(false)
		return
	}
	if scenario == "bad-cipher" {
		foreign := node
		foreign.ID = "foreign-node"
		payload["node"] = foreign
		if failure := host.rpc("connect", payload, nil); failure == nil || failure.Code != "credential_unavailable" {
			t.Fatal("connect accepted a credential belonging to a different node")
		}
		fmt.Println("rejected")
		host.finish(false)
		return
	}
	if scenario == "chain-rule" {
		exit, routed := protect("manager-exit"), protect("manager-route")
		delete(payload, "node")
		payload["chain"] = ChainSnapshot{ID: "manager-chain", Name: "隔离双跳链", Revision: 4, Hops: []Node{node, exit}}
		payload["mode"] = "rule"
		payload["routing"] = RoutingPlan{Revision: 9,
			Rules:     []RouteRule{{ID: "ipv6", Type: "IP-CIDR", Value: forwardIPv6 + "/128", Target: "node:manager-route", Enabled: true}, {ID: "final", Type: "MATCH", Target: "proxy", Enabled: true}},
			Outbounds: []RoutingOutbound{{Key: "node:manager-route", Name: "独立规则节点", Node: routed}}}
	}
	var proxyBefore []byte
	if scenario == "system-proxy" {
		proxyBefore = dconfCommand(t, nil, "dump", "/system/proxy/")
		payload["systemProxy"] = true
	}
	if scenario == "permission-denied" {
		if failure := host.rpc("connect", payload, nil); failure == nil || failure.Code != "tun_permission_denied" {
			t.Fatal("authorization refusal was not retained", failure)
		}
		fmt.Println("denied")
		host.finish(false)
		return
	}
	if scenario == "cancel-start" {
		cancelManagedHostOperation(t, host, "connect", payload, func() {
			for deadline := time.Now().Add(3 * time.Second); ; {
				if _, err := os.Stat("/run/rainlink-manager-authorizing"); err == nil {
					break
				}
				if time.Now().After(deadline) {
					t.Fatal("authorization was not reached before cancellation")
				}
				time.Sleep(10 * time.Millisecond)
			}
		}, "cancelled")
		var pending Snapshot
		if failure := host.rpc("snapshot", nil, &pending); failure != nil || pending.Phase != "failed" || pending.Error == "" {
			t.Fatal("interrupted startup falsely reported confirmed idle", failure)
		}
		fmt.Println("cancelled")
		commands := bufio.NewScanner(os.Stdin)
		if !commands.Scan() || commands.Text() != "retry" {
			t.Fatal("retry instruction missing")
		}
		if failure := host.rpc("disconnect", nil, nil); failure != nil {
			t.Fatal("interrupted startup did not confirm recovery", failure)
		}
		var state Snapshot
		if failure := host.rpc("snapshot", nil, &state); failure != nil || state.Phase != "idle" {
			t.Fatal("interrupted startup remained active", failure)
		}
		fmt.Println("stopped")
		host.finish(false)
		return
	}
	var snapshot Snapshot
	if failure := host.rpc("connect", payload, &snapshot); failure != nil || snapshot.Phase != "connected" || !snapshot.TUN || snapshot.SessionID == "" || snapshot.Target == nil {
		t.Fatal("ordinary host did not confirm TUN", failure)
	}
	public, err := json.Marshal(snapshot)
	if err != nil || bytes.Contains(public, []byte(node.Credential)) || bytes.Contains(public, []byte("fixture-forward-password")) || bytes.Contains(public, []byte("apiSecret")) {
		t.Fatal("private credentials crossed the ordinary host boundary", err)
	}
	if scenario == "chain-rule" {
		if snapshot.Node != nil || snapshot.Target.Kind != "chain" || snapshot.RuleRevision != 9 || len(snapshot.RouteBindings) != 3 || snapshot.RouteBindings["proxy/hop/1"].ID != "manager-exit" || snapshot.RouteBindings["node:manager-route"].ID != "manager-route" {
			t.Fatal("chain/rule identities were not preserved")
		}
	} else if snapshot.Node == nil || snapshot.Node.ID != node.ID || snapshot.Node.Credential != "" {
		t.Fatal("single-node snapshot does not match the desktop contract")
	}
	if err := confirmLinuxTUNIdle(ctx, installedTUNSocket); err == nil {
		t.Fatal("read-only idle request accepted another active capture lease")
	}
	fmt.Println("connected")
	commands := bufio.NewScanner(os.Stdin)
	if !commands.Scan() || commands.Text() != "exercise" {
		t.Fatal("exercise instruction missing")
	}
	for _, family := range []struct{ network, host string }{{"tcp4", forwardIPv4}, {"tcp6", forwardIPv6}, {"udp4", forwardIPv4}, {"udp6", forwardIPv6}} {
		if scenario == "chain-rule" && strings.HasPrefix(family.network, "udp") {
			continue
		}
		connection := forwardingDial(t, family.network, net.JoinHostPort(family.host, forwardEchoPort))
		payload := []byte("ordinary-host-" + family.network + "-exact-echo")
		if _, err := connection.Write(payload); err != nil {
			t.Fatal(err)
		}
		answer := make([]byte, len(payload))
		if _, err := io.ReadFull(connection, answer); err != nil || !bytes.Equal(payload, answer) {
			t.Fatal("ordinary host did not forward exact data", family.network, err)
		}
		if err := connection.SetDeadline(time.Time{}); err != nil {
			t.Fatal(err)
		}
	}
	var page ConnectionPage
	for deadline := time.Now().Add(2 * time.Second); ; {
		if failure := host.rpc("connections", map[string]any{"sessionId": snapshot.SessionID, "cursor": 0}, &page); failure != nil {
			t.Fatal(failure)
		}
		confirmed := map[string]bool{}
		for _, entry := range page.Entries {
			if entry.Upload > 0 && entry.Download > 0 && strings.HasSuffix(entry.Destination, ":"+forwardEchoPort) && !entry.Direct {
				confirmed[entry.Network+entry.Destination] = true
				if scenario == "chain-rule" && (strings.Contains(entry.Destination, forwardIPv6) && entry.Outbound != "独立规则节点" || strings.Contains(entry.Destination, forwardIPv4) && entry.Outbound != "隔离双跳链") {
					t.Fatal("rule or chain attribution was lost", entry)
				}
			}
		}
		want := 4
		if scenario == "chain-rule" {
			want = 2
		}
		if len(confirmed) == want {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("public connections did not retain bidirectional traffic", page)
		}
		time.Sleep(20 * time.Millisecond)
	}
	var observed Snapshot
	if failure := host.rpc("snapshot", nil, &observed); failure != nil || observed.Phase != "connected" || observed.SessionID != snapshot.SessionID || observed.Telemetry == nil || observed.Telemetry.UploadTotal <= 0 || observed.Telemetry.DownloadTotal <= 0 {
		t.Fatal("observed TUN/telemetry was not connected", failure)
	}
	if scenario == "system-proxy" {
		if !observed.SystemProxy || string(dconfCommand(t, nil, "read", "/system/proxy/mode")) != "'manual'\n" {
			t.Fatal("TUN and system proxy were not both applied")
		}
		for _, enabled := range []bool{false, true} {
			if failure := host.rpc("capture", map[string]bool{"enabled": enabled}, nil); failure != nil {
				t.Fatal(failure)
			}
			if failure := host.rpc("snapshot", nil, &observed); failure != nil || observed.SystemProxy != enabled || !observed.TUN || observed.Phase != "connected" {
				t.Fatal("capture switch changed the TUN lifetime", failure)
			}
		}
	}
	if failure := host.rpc("mode", map[string]string{"mode": "direct"}, nil); failure != nil {
		t.Fatal(failure)
	}
	if forwardingRejectDirect(t) != 4 || forwardingDNS(t, "managerdirect") != 4 {
		t.Fatal("direct/DNS checks incomplete")
	}
	if failure := host.rpc("mode", map[string]string{"mode": "global"}, nil); failure != nil {
		t.Fatal(failure)
	}
	if failure := host.rpc("snapshot", nil, &observed); failure != nil || observed.Mode != "global" {
		t.Fatal("host mode readback failed", failure)
	}
	var coreLogs, clearedLogs []LogEntry
	if scenario == "stop" {
		coreLogs = waitManagedTUNLogEntries(t, host, LogBatch{}, func(entries []LogEntry) bool {
			for _, entry := range entries {
				if entry.Source == "core" && strings.Contains(entry.Message, "inbound/tun") {
					return true
				}
			}
			return false
		})
		var checkpoint LogBatch
		if failure := host.rpc("clearLogs", nil, &checkpoint); failure != nil {
			t.Fatal("managed logs could not be cleared", failure)
		}
		if forwardingDNS(t, "managerafterclear") != 4 {
			t.Fatal("post-clear DNS checks incomplete")
		}
		clearedLogs = waitManagedTUNLogEntries(t, host, checkpoint, func(entries []LogEntry) bool {
			for _, entry := range entries {
				if entry.Source == "core" && strings.Contains(entry.Message, "managerafterclear") {
					return true
				}
			}
			return false
		})
	}
	data, err := json.MarshalIndent(map[string]any{"connected": snapshot, "observed": observed, "connections": page, "directChecks": 4, "dnsChecks": 4, "coreLogs": coreLogs, "postClearLogs": clearedLogs}, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(filepath.Join(os.Getenv("RAINLINK_MANAGER_FIXTURE_HOME"), "observed.json"), append(data, '\n'), 0600); err != nil {
		t.Fatal(err)
	}
	fmt.Println("exercised")
	if !commands.Scan() {
		t.Fatal("cleanup instruction missing")
	}
	switch commands.Text() {
	case "stop":
		if failure := host.rpc("disconnect", nil, nil); failure != nil {
			t.Fatal(failure)
		}
		if failure := host.rpc("disconnect", nil, nil); failure != nil {
			t.Fatal("stop was not idempotent", failure)
		}
	case "lost":
		if failure := host.rpc("snapshot", nil, &observed); failure != nil || observed.Phase != "failed" || observed.SessionID != snapshot.SessionID {
			t.Fatal("service loss discarded recoverable identity", failure)
		}
		if failure := host.rpc("disconnect", nil, nil); failure != nil {
			t.Fatal("root idle confirmation did not finish recovery", failure)
		}
	case "route-loss":
		if failure := host.rpc("snapshot", nil, &observed); failure != nil || observed.Phase != "failed" || observed.SessionID != snapshot.SessionID {
			t.Fatal("incomplete kernel policy was reported as connected", failure)
		}
		if failure := host.rpc("disconnect", nil, nil); failure != nil {
			t.Fatal("damaged policy did not restore", failure)
		}
	case "interrupt-stop":
		cancelManagedHostOperation(t, host, "disconnect", nil, func() { time.Sleep(100 * time.Millisecond) }, "tun_restore_failed")
		if failure := host.rpc("snapshot", nil, &observed); failure != nil || observed.Phase != "failed" || observed.SessionID != snapshot.SessionID {
			t.Fatal("unconfirmed stop discarded identity", failure)
		}
		fmt.Println("pending")
		if !commands.Scan() || commands.Text() != "retry" {
			t.Fatal("stop retry instruction missing")
		}
		if failure := host.rpc("disconnect", nil, nil); failure != nil {
			t.Fatal("stop retry failed after root recovery", failure)
		}
	case "eof":
		host.finish(false)
		fmt.Println("closed")
		return
	case "host-killed":
		host.finish(true)
		fmt.Println("closed")
		return
	default:
		t.Fatal("unknown manager fixture instruction")
	}
	if failure := host.rpc("snapshot", nil, &observed); failure != nil || observed.Phase != "idle" || observed.SessionID != "" || observed.Error != "" {
		t.Fatal("confirmed stop did not retire the session", failure)
	}
	if scenario == "system-proxy" && !bytes.Equal(proxyBefore, dconfCommand(t, nil, "dump", "/system/proxy/")) {
		t.Fatal("combined capture did not restore the original desktop settings")
	}
	if scenario == "stop" {
		waitManagedTUNLogEntries(t, host, LogBatch{}, func(entries []LogEntry) bool {
			for _, entry := range entries {
				if entry.Source == "host" && strings.Contains(entry.Message, "网络资源已恢复") {
					return true
				}
			}
			return false
		})
	}
	fmt.Println("stopped")
	host.finish(false)
}

func waitManagedTUNLogEntries(t *testing.T, host *linuxTestHost, checkpoint LogBatch, ready func([]LogEntry) bool) []LogEntry {
	t.Helper()
	var entries []LogEntry
	for deadline := time.Now().Add(3 * time.Second); ; {
		var batch LogBatch
		if failure := host.rpc("logs", map[string]any{"stream": checkpoint.Stream, "after": checkpoint.Cursor}, &batch); failure != nil {
			t.Fatal("public managed log read failed", failure)
		}
		entries = append(entries, batch.Entries...)
		encoded, err := json.Marshal(entries)
		if err != nil || bytes.Contains(encoded, []byte("fixture-forward-password")) || bytes.Contains(encoded, []byte("fixture-user")) || bytes.Contains(encoded, []byte("apiSecret")) || bytes.Contains(encoded, []byte("rls1.")) {
			t.Fatal("private data entered managed public logs", err)
		}
		checkpoint.Stream, checkpoint.Cursor = batch.Stream, batch.Cursor
		if ready(entries) {
			return entries
		}
		if time.Now().After(deadline) {
			t.Fatal("real permission core diagnostics did not reach public logs")
		}
		if !batch.More {
			time.Sleep(20 * time.Millisecond)
		}
	}
}

func cancelManagedHostOperation(t *testing.T, host *linuxTestHost, method string, payload any, ready func(), code string) {
	t.Helper()
	host.id++
	id := host.id
	if err := host.encoder.Encode(map[string]any{"id": id, "method": method, "payload": payload}); err != nil {
		t.Fatal(err)
	}
	ready()
	host.id++
	if err := host.encoder.Encode(map[string]any{"id": host.id, "method": "cancel"}); err != nil {
		t.Fatal(err)
	}
	for _, expected := range []int{id, host.id} {
		var reply struct {
			ID    int      `json:"id"`
			Error *Failure `json:"error"`
		}
		if err := host.decoder.Decode(&reply); err != nil || reply.ID != expected {
			t.Fatal("cancel protocol lost its request", err)
		}
		if expected == id && (reply.Error == nil || reply.Error.Code != code) {
			t.Fatal("operation cancellation lost recovery state", reply.Error)
		}
		if expected != id && reply.Error != nil {
			t.Fatal(reply.Error)
		}
	}
}

type managedTUNTestService struct {
	listener    *net.UnixListener
	done        chan struct{}
	mu          sync.Mutex
	children    []*managedChild
	err         error
	diagnostics *permissionDiagnostics
}

func startManagedTUNTestService(t *testing.T) *managedTUNTestService {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(installedTUNSocket), 0755); err != nil {
		t.Fatal(err)
	}
	listener, err := net.ListenUnix("unix", &net.UnixAddr{Name: installedTUNSocket, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	if err = os.Chmod(installedTUNSocket, 0666); err != nil {
		_ = listener.Close()
		t.Fatal(err)
	}
	service := &managedTUNTestService{listener: listener, done: make(chan struct{}), diagnostics: &permissionDiagnostics{}}
	go func() {
		defer close(service.done)
		for {
			connection, err := listener.AcceptUnix()
			if err != nil {
				if !errors.Is(err, net.ErrClosed) {
					service.mu.Lock()
					service.err = err
					service.mu.Unlock()
				}
				return
			}
			file, err := connection.File()
			_ = connection.Close()
			if err == nil {
				command := exec.Command(installedTUNHost, "serve-tun")
				command.Env = []string{"PATH=", "LANG=C", "LC_ALL=C"}
				command.Stdin, command.Stdout, command.Stderr = file, service.diagnostics, service.diagnostics
				var child *managedChild
				child, err = startManagedChild(command)
				_ = file.Close()
				if err == nil {
					service.mu.Lock()
					service.children = append(service.children, child)
					service.mu.Unlock()
				}
			}
			if err != nil {
				service.mu.Lock()
				service.err = err
				service.mu.Unlock()
				return
			}
		}
	}()
	t.Cleanup(func() {
		_ = listener.Close()
		<-service.done
		service.mu.Lock()
		defer service.mu.Unlock()
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		for _, child := range service.children {
			if err := child.stop(ctx); err != nil {
				t.Error(err)
			}
		}
		if service.err != nil {
			t.Error("socket activation fixture failed", service.err, service.diagnostics.String())
		}
	})
	return service
}

type managedHostFixture struct {
	*tunPermissionFixture
	directory string
}

func startManagedHostClient(t *testing.T, scenario string) *managedHostFixture {
	t.Helper()
	directory, err := os.MkdirTemp("/run", "rainlink-manager-client-")
	if err != nil {
		t.Fatal(err)
	}
	if err = os.Chown(directory, 65534, 65534); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(directory) })
	command := exec.Command("/bin/sh", os.Getenv("RAINLINK_TEST_MANAGER_SESSION_SCRIPT"), os.Args[0])
	command.Env = append(os.Environ(), "RAINLINK_TEST_MANAGER_CLIENT=1", "RAINLINK_MANAGER_SCENARIO="+scenario, "RAINLINK_MANAGER_FIXTURE_HOME="+directory)
	command.SysProcAttr = &syscall.SysProcAttr{Credential: &syscall.Credential{Uid: 65534, Gid: 65534}, Setsid: true}
	input, err := command.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	output, err := command.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	fixture := &tunPermissionFixture{client: command, input: input, output: bufio.NewReader(output), diagnostics: &permissionDiagnostics{}}
	command.Stderr = fixture.diagnostics
	if err = command.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = input.Close()
		if !fixture.clientReaped {
			_ = syscall.Kill(-command.Process.Pid, syscall.SIGKILL)
			_ = command.Wait()
		}
	})
	return &managedHostFixture{tunPermissionFixture: fixture, directory: directory}
}

func (service *managedTUNTestService) signalOwnedGuardian(t *testing.T, identity linuxprocess.Identity, signal os.Signal) {
	t.Helper()
	service.mu.Lock()
	defer service.mu.Unlock()
	for _, child := range service.children {
		if child.command.Process.Pid == identity.PID {
			current, alive, err := linuxprocess.ReadIdentity(identity.PID)
			if err != nil || !alive || current != identity {
				t.Fatal("fixture guardian identity changed", err)
			}
			// Signal our exec.Cmd's retained process handle. The production
			// recovery Handle intentionally permits shutdown signals only.
			if err := child.command.Process.Signal(signal); err != nil {
				t.Fatal(err)
			}
			return
		}
	}
	t.Fatal("fixture does not own this guardian")
}

func waitManagedNetworkRestored(t *testing.T, before linuxnet.State) linuxnet.State {
	t.Helper()
	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()
	for {
		state, err := linuxnet.Read(ctx)
		_, journalErr := os.Stat("/run/rainlink-tun/capture-recovery.json")
		if err == nil && errors.Is(journalErr, os.ErrNotExist) && reflect.DeepEqual(before, state) {
			return state
		}
		select {
		case <-ctx.Done():
			t.Fatal("managed host did not restore the complete network", err, journalErr)
		case <-time.After(20 * time.Millisecond):
		}
	}
}

func TestIsolatedLinuxTUNManagerLifecycle(t *testing.T) {
	requireIsolatedTUNClient(t)
	if os.Getenv("RAINLINK_TEST_MANAGER_NAMESPACE") != "isolated" {
		t.Skip("requires disposable real Secret Service")
	}
	const pkcheck = "/usr/bin/pkcheck"
	if _, err := os.Lstat(pkcheck); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("fixture must not replace the original authorizer", err)
	}
	defer os.Remove(pkcheck)
	beforeWire, err := linuxnet.Read(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	server := startForwardingServer(t)
	var service *managedTUNTestService
	for _, scenario := range []string{"no-service", "core-start-failure", "stop", "chain-rule", "system-proxy", "eof", "host-killed", "guardian-killed", "core-killed", "watchdog-killed", "stop-timeout", "route-loss", "permission-denied", "cancel-start", "bad-cipher"} {
		if scenario != "no-service" && service == nil {
			service = startManagedTUNTestService(t)
		}
		if !t.Run(scenario, func(t *testing.T) {
			authorizer := "#!/bin/sh\nexit 0\n"
			if scenario == "permission-denied" {
				authorizer = "#!/bin/sh\nexit 1\n"
			}
			if scenario == "cancel-start" {
				authorizer = "#!/bin/sh\nprintf 1 > /run/rainlink-manager-authorizing\nexec /bin/sleep 10\n"
			}
			if err := os.WriteFile(pkcheck, []byte(authorizer), 0755); err != nil {
				t.Fatal(err)
			}
			if scenario == "no-service" {
				if _, err := os.Lstat(installedTUNSocket); !errors.Is(err, os.ErrNotExist) {
					t.Fatal("missing-service fixture has an installed socket", err)
				}
				t.Setenv("RAINLINK_MANAGER_TEST_PATTERN", "^TestLinuxHostPrivateProtocolAndEOFCleanup$")
			}
			before, err := linuxnet.Read(t.Context())
			if err != nil {
				t.Fatal(err)
			}
			fixture := startManagedHostClient(t, scenario)
			evidence := map[string]any{"scenario": scenario, "before": before}
			if scenario == "no-service" {
				// Existing regression exercises both unsupported capture refusals,
				// actual keyring/host RPC, local-port traffic, modes and EOF cleanup.
			} else if scenario == "permission-denied" {
				fixture.expect(t, "denied")
			} else if scenario == "bad-cipher" || scenario == "core-start-failure" {
				fixture.expect(t, "rejected")
			} else if scenario == "cancel-start" {
				fixture.expect(t, "cancelled")
				// A journal can be absent before authorization completes. Wait for
				// the actual guardian too; idle alone cannot fence late startup.
				service.mu.Lock()
				children := append([]*managedChild(nil), service.children...)
				service.mu.Unlock()
				for _, child := range children {
					select {
					case <-child.done:
					case <-time.After(3 * time.Second):
						t.Fatal("cancelled authorization guardian did not exit")
					}
				}
				waitManagedNetworkRestored(t, before)
				fixture.command(t, "retry")
				fixture.expect(t, "stopped")
			} else {
				fixture.expect(t, "connected")
				var journal struct {
					Owner     linuxprocess.Identity  `json:"owner"`
					Core      linuxprocess.Identity  `json:"core"`
					Resources linuxtun.Specification `json:"resources"`
				}
				data, err := os.ReadFile("/run/rainlink-tun/capture-recovery.json")
				if err != nil || json.Unmarshal(data, &journal) != nil || !journal.Owner.Valid() || !journal.Core.Valid() {
					t.Fatal("managed host has no durable ownership", err)
				}
				if err = confirmManagedTUN(t.Context(), journal.Resources); err != nil {
					t.Fatal(err)
				}
				evidence["owner"], evidence["core"], evidence["resources"] = journal.Owner, journal.Core, journal.Resources
				evidence["ready"], err = linuxnet.Read(t.Context())
				if err != nil {
					t.Fatal(err)
				}
				watchdog := permissionWatchdog(t, journal.Owner.PID)
				fixture.command(t, "exercise")
				fixture.expect(t, "exercised")
				switch scenario {
				case "eof", "host-killed":
					fixture.command(t, scenario)
					fixture.expect(t, "closed")
				case "guardian-killed", "core-killed", "watchdog-killed":
					victim := journal.Owner
					if scenario == "core-killed" {
						victim = journal.Core
					}
					if scenario == "watchdog-killed" {
						victim = watchdog
					}
					handle, err := linuxprocess.Open(victim)
					if err != nil {
						t.Fatal(err)
					}
					err = handle.Signal(unix.SIGKILL)
					_ = handle.Close()
					if err != nil {
						t.Fatal(err)
					}
					waitManagedNetworkRestored(t, before)
					fixture.command(t, "lost")
					fixture.expect(t, "stopped")
				case "stop-timeout":
					service.signalOwnedGuardian(t, journal.Owner, syscall.SIGSTOP)
					fixture.command(t, "interrupt-stop")
					fixture.expect(t, "pending")
					service.signalOwnedGuardian(t, journal.Owner, syscall.SIGCONT)
					waitManagedNetworkRestored(t, before)
					fixture.command(t, "retry")
					fixture.expect(t, "stopped")
				case "route-loss":
					rules, err := journal.Resources.ExpectedRules()
					if err != nil {
						t.Fatal(err)
					}
					removed, err := linuxnet.DeleteExactRule(t.Context(), rules[0])
					if err != nil || !removed {
						t.Fatal("fixture did not remove its exact rule", err)
					}
					fixture.command(t, "route-loss")
					fixture.expect(t, "stopped")
				default:
					fixture.command(t, "stop")
					fixture.expect(t, "stopped")
				}
				waitManagedNetworkRestored(t, before)
				for _, identity := range []linuxprocess.Identity{journal.Core, watchdog} {
					if alive, err := linuxprocess.Alive(identity); err != nil || alive {
						t.Fatal("managed host left a core or watchdog alive", err)
					}
				}
			}
			rest, err := io.ReadAll(fixture.output)
			if err != nil {
				t.Fatal(err)
			}
			err = fixture.client.Wait()
			fixture.clientReaped = true
			if err != nil || strings.TrimSpace(string(rest)) != "PASS" {
				diagnostics := ""
				if service != nil {
					diagnostics = service.diagnostics.String()
				}
				t.Fatal("ordinary managed-host fixture failed", err, string(rest), fixture.diagnostics.String(), diagnostics)
			}
			evidence["after"] = waitManagedNetworkRestored(t, before)
			if data, err := os.ReadFile(filepath.Join(fixture.directory, "observed.json")); err == nil {
				var observed map[string]any
				if err = json.Unmarshal(data, &observed); err != nil {
					t.Fatal(err)
				}
				evidence["client"] = observed
			} else if scenario != "bad-cipher" && scenario != "permission-denied" && scenario != "cancel-start" && scenario != "no-service" {
				t.Fatal("missing native host observations", err)
			}
			if directory := os.Getenv("RAINLINK_TEST_NETWORK_EVIDENCE_DIR"); directory != "" {
				data, err := json.MarshalIndent(evidence, "", "  ")
				if err != nil {
					t.Fatal(err)
				}
				if err = os.WriteFile(filepath.Join(directory, "manager-"+scenario+"-state.json"), append(data, '\n'), 0600); err != nil {
					t.Fatal(err)
				}
			}
		}) {
			return
		}
	}
	server.send(t, "report")
	line, err := server.output.ReadString('\n')
	var report forwardingServerReport
	if err != nil || json.Unmarshal([]byte(line), &report) != nil || report.TCP4 < 10 || report.TCP6 < 10 || report.UDP4 < 9 || report.UDP6 < 9 || report.RejectedTCP != 20 || report.RejectedUDP != 20 || report.DNSQueries < 40 {
		t.Fatal("independent origins did not confirm managed-host traffic", line, err)
	}
	server.send(t, "exit")
	rest, err := io.ReadAll(server.output)
	if err != nil {
		t.Fatal(err)
	}
	err = server.command.Wait()
	server.reaped = true
	if err != nil || strings.TrimSpace(string(rest)) != "PASS" {
		t.Fatal("origin server did not exit", err, string(rest))
	}
	afterWire := waitManagedNetworkRestored(t, beforeWire)
	if directory := os.Getenv("RAINLINK_TEST_NETWORK_EVIDENCE_DIR"); directory != "" {
		data, err := json.MarshalIndent(map[string]any{"beforeWire": beforeWire, "afterWire": afterWire, "server": report}, "", "  ")
		if err != nil {
			t.Fatal(err)
		}
		if err = os.WriteFile(filepath.Join(directory, "manager-forwarding-state.json"), append(data, '\n'), 0600); err != nil {
			t.Fatal(err)
		}
	}
}
