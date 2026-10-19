//go:build linux && !android

package linuxmanage

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"

	"rainlink.local/host/internal/linuxinstall"
)

// This tests the real authority/agent protocol without a graphical desktop or
// passwords. Register an agent for the actual ordinary broker's process subject.
func TestRealPolkitManagementAuthenticationCancellation(t *testing.T) {
	if os.Getenv("RAINLINK_TEST_REAL_MANAGEMENT") != "disposable-vm" {
		t.Skip("requires disposable systemd/polkit VM")
	}
	if os.Geteuid() != 0 {
		t.Fatal("VM controller must be root")
	}
	if data, err := os.ReadFile("/proc/1/comm"); err != nil || strings.TrimSpace(string(data)) != "systemd" {
		t.Fatal("requires real systemd", err)
	}
	const rulePath = "/etc/polkit-1/rules.d/41-rainlink-authentication-qa.rules"
	if _, err := os.Lstat(rulePath); !os.IsNotExist(err) {
		t.Fatal("VM authentication rule already exists", err)
	}
	rule := "polkit.addRule(function(action, subject) {\n" +
		"  var program = action.lookup('program') || '';\n" +
		"  if (action.id === 'org.freedesktop.policykit.exec' && subject.user === 'nobody' &&\n" +
		"      /^\\/proc\\/[0-9]+\\/exe$/.test(program)) {\n" +
		"    return polkit.Result.AUTH_ADMIN;\n  }\n});\n"
	if err := os.WriteFile(rulePath, []byte(rule), 0644); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := os.Remove(rulePath); err != nil {
			t.Error(err)
		}
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		if data, err := exec.CommandContext(ctx, "/usr/bin/systemctl", "restart", "polkit.service").CombinedOutput(); err != nil {
			t.Errorf("policy cleanup: %v %s", err, data)
		}
	})
	ctx, cancel := context.WithTimeout(t.Context(), 2*time.Minute)
	defer cancel()
	if data, err := exec.CommandContext(ctx, "/usr/bin/systemctl", "restart", "polkit.service").CombinedOutput(); err != nil {
		t.Fatalf("policy reload: %v %s", err, data)
	}
	for _, scenario := range []string{"cancel", "eof", "agent-reject"} {
		t.Run(scenario, func(t *testing.T) { testAuthenticationCancellation(t, ctx, scenario) })
	}
}

func testAuthenticationCancellation(t *testing.T, parent context.Context, scenario string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(parent, 25*time.Second)
	defer cancel()
	if status := linuxinstall.InspectService(ctx); status.State != "missing" {
		t.Fatal("authentication fixture requires absent service", status)
	}
	host := filepath.Join(filepath.Dir(os.Args[0]), "rainlink-host")
	broker := exec.CommandContext(ctx, host, "manage-tun-service")
	broker.Env = []string{"PATH=/usr/bin:/bin", "LANG=C", "LC_ALL=C"}
	broker.SysProcAttr = &syscall.SysProcAttr{Credential: &syscall.Credential{Uid: 65534, Gid: 65534}}
	input, err := broker.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	defer input.Close()
	output, err := broker.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	var brokerDiagnostics bytes.Buffer
	broker.Stderr = &brokerDiagnostics
	if err = broker.Start(); err != nil {
		t.Fatal(err)
	}
	brokerWaited := false
	defer func() {
		if !brokerWaited {
			_ = input.Close()
			cancel()
			_ = broker.Wait()
		}
	}()

	agentScript := filepath.Join(filepath.Dir(os.Args[0]), "linux_polkit_agent.py")
	agent := exec.CommandContext(ctx, "/usr/bin/python3", agentScript, strconv.Itoa(broker.Process.Pid), scenario)
	agent.Env = []string{"PATH=/usr/bin:/bin", "LANG=C", "LC_ALL=C", "RAINLINK_TEST_AUTH_AGENT=disposable-vm"}
	agent.SysProcAttr = &syscall.SysProcAttr{Credential: &syscall.Credential{Uid: 65534, Gid: 65534}}
	agentOutput, err := agent.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	var agentDiagnostics bytes.Buffer
	agent.Stderr = &agentDiagnostics
	if err = agent.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() {
		_ = agent.Process.Signal(syscall.SIGTERM)
		_ = agent.Wait()
		if agentDiagnostics.Len() > 0 {
			t.Log("agent diagnostics:", agentDiagnostics.String())
		}
	}()
	read := bufio.NewScanner(agentOutput)
	var evidence bytes.Buffer
	waitEvent := func(want string) {
		t.Helper()
		if !read.Scan() {
			t.Fatal("authentication agent did not report", want, read.Err())
		}
		line := read.Text()
		fmt.Fprintln(&evidence, line)
		var event struct{ Event string }
		if json.Unmarshal([]byte(line), &event) != nil || event.Event != want {
			t.Fatal("unexpected authentication event", line, "want", want)
		}
	}
	waitEvent("registered")
	encode, decode := json.NewEncoder(input), json.NewDecoder(output)
	if err = encode.Encode(request{ID: 1, Method: "install"}); err != nil {
		t.Fatal(err)
	}
	waitEvent("began")
	start := time.Now()
	if scenario == "cancel" {
		if err = encode.Encode(request{ID: 2, Method: "cancel"}); err != nil {
			t.Fatal(err)
		}
		var ack struct {
			ID     int
			Result map[string]bool
			Error  *failure
		}
		if err = decode.Decode(&ack); err != nil || ack.ID != 2 || ack.Error != nil || !ack.Result["requested"] {
			t.Fatal("cancellation acknowledgement", ack, err)
		}
	}
	if scenario == "eof" {
		if err = input.Close(); err != nil {
			t.Fatal(err)
		}
	} else {
		var result struct {
			ID     int
			Result json.RawMessage
			Error  *failure
		}
		if err = decode.Decode(&result); err != nil || result.ID != 1 || result.Error == nil || len(result.Result) != 0 {
			t.Fatal("authorization returned a false success", result, err)
		}
		want := "cancelled"
		if scenario == "agent-reject" {
			want = "authorization_cancelled"
		}
		if result.Error.Code != want {
			t.Fatal("incorrect authorization result", result.Error)
		}
		fmt.Fprintf(&evidence, "original operation error: %s\n", result.Error.Code)
		if err = input.Close(); err != nil {
			t.Fatal(err)
		}
	}
	err = broker.Wait()
	brokerWaited = true
	if scenario == "eof" {
		var exit *exec.ExitError
		if !errors.As(err, &exit) || exit.ExitCode() != 1 {
			t.Fatal("EOF swallowed pending-authorization failure", err)
		}
	} else if err != nil {
		t.Fatal("broker exit", err, brokerDiagnostics.String())
	}
	if elapsed := time.Since(start); elapsed > 5*time.Second {
		t.Fatal("pending authorization was not promptly dismissed", elapsed)
	}
	if scenario != "agent-reject" {
		waitEvent("cancelled")
	}
	if status := linuxinstall.InspectService(ctx); status.State != "missing" {
		t.Fatal("cancelled authentication altered service", status)
	}
	// A successful auth cancellation must not have launched an installation.
	if _, err := os.Lstat("/var/lib/rainlink/tun-install/transaction.json"); !os.IsNotExist(err) {
		t.Fatal("cancelled authentication left an installation transaction", err)
	}
	fmt.Fprintln(&evidence, "service remains missing; no installation transaction")
	if directory := os.Getenv("RAINLINK_TEST_MANAGEMENT_EVIDENCE"); directory != "" {
		if err = os.WriteFile(filepath.Join(directory, "authentication-"+scenario+".log"), evidence.Bytes(), 0600); err != nil {
			t.Fatal(err)
		}
	}
	t.Logf("actual authority/agent %s: %s", scenario, &evidence)
	// Ensure the pipe was consumed before Wait closes it, including rejection.
	if _, err = io.Copy(io.Discard, output); err != nil && !errors.Is(err, os.ErrClosed) {
		t.Fatal(err)
	}
}
