//go:build linux && !android

package linuxmanage

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"

	"rainlink.local/host/internal/linuxinstall"
)

// This acceptance installs into real system paths, exclusively in the QA VM.
func TestRealSystemdManagementViaOrdinaryBroker(t *testing.T) {
	if os.Getenv("RAINLINK_TEST_REAL_MANAGEMENT") != "disposable-vm" {
		t.Skip("requires disposable systemd/polkit VM")
	}
	if os.Geteuid() != 0 {
		t.Fatal("VM controller must be root")
	}
	if data, err := os.ReadFile("/proc/1/comm"); err != nil || strings.TrimSpace(string(data)) != "systemd" {
		t.Fatal("requires real systemd", err)
	}
	const rulePath = "/etc/polkit-1/rules.d/40-rainlink-management-qa.rules"
	if _, err := os.Lstat(rulePath); !os.IsNotExist(err) {
		t.Fatal("VM rule already exists", err)
	}
	if _, err := os.Lstat("/usr/libexec/rainlink/rainlink-host"); !os.IsNotExist(err) {
		t.Fatal("VM service already installed", err)
	}
	ctx, cancel := context.WithTimeout(t.Context(), 4*time.Minute)
	defer cancel()
	t.Cleanup(func() {
		cleanup, stop := context.WithTimeout(context.Background(), time.Minute)
		defer stop()
		host := filepath.Join(filepath.Dir(os.Args[0]), "rainlink-host")
		if data, err := exec.CommandContext(cleanup, host, "uninstall-tun").CombinedOutput(); err != nil {
			t.Errorf("VM cleanup failed: %v %s", err, data)
		}
		if err := os.Remove(rulePath); err != nil {
			t.Error(err)
		}
		if data, err := exec.CommandContext(cleanup, "/usr/bin/systemctl", "restart", "polkit.service").CombinedOutput(); err != nil {
			t.Errorf("policy cleanup: %v %s", err, data)
		}
	})
	for _, scenario := range []string{"deny", "allow"} {
		t.Run(scenario, func(t *testing.T) {
			decision := "NO"
			if scenario == "allow" {
				decision = "YES"
			}
			rule := "polkit.addRule(function(action, subject) {\n" +
				"  var program = action.lookup('program') || '';\n" +
				"  if (action.id === 'org.freedesktop.policykit.exec' && subject.user === 'nobody' &&\n" +
				"      (/^\\/proc\\/[0-9]+\\/exe$/.test(program) || program === '/opt/rainlink-qa/rainlink-host')) {\n" +
				"    return polkit.Result." + decision + ";\n  }\n});\n"
			if err := os.WriteFile(rulePath, []byte(rule), 0644); err != nil {
				t.Fatal(err)
			}
			if data, err := exec.CommandContext(ctx, "/usr/bin/systemctl", "restart", "polkit.service").CombinedOutput(); err != nil {
				t.Fatalf("policy reload: %v %s", err, data)
			}
			client := exec.CommandContext(ctx, os.Args[0], "-test.v", "-test.run=^TestOrdinaryManagementClientFixture$", "-test.timeout=150s")
			client.Env = []string{"PATH=/usr/bin:/bin", "LANG=C", "LC_ALL=C", "RAINLINK_TEST_MANAGEMENT_CLIENT=" + scenario}
			client.SysProcAttr = &syscall.SysProcAttr{Credential: &syscall.Credential{Uid: 65534, Gid: 65534}}
			data, err := client.CombinedOutput()
			if directory := os.Getenv("RAINLINK_TEST_MANAGEMENT_EVIDENCE"); directory != "" {
				if writeErr := os.WriteFile(filepath.Join(directory, "ordinary-broker-"+scenario+".log"), data, 0600); writeErr != nil {
					t.Fatal(writeErr)
				}
			}
			if err != nil {
				t.Fatalf("ordinary management failed: %v %s", err, data)
			}
			t.Logf("actual pkexec/polkit %s: %s", scenario, data)
		})
	}
}

func TestOrdinaryManagementClientFixture(t *testing.T) {
	scenario := os.Getenv("RAINLINK_TEST_MANAGEMENT_CLIENT")
	if scenario == "" {
		t.Skip("VM ordinary-user fixture")
	}
	if os.Geteuid() != 65534 {
		t.Fatal("client must be ordinary UID 65534")
	}
	ctx, cancel := context.WithTimeout(t.Context(), 140*time.Second)
	defer cancel()
	host := filepath.Join(filepath.Dir(os.Args[0]), "rainlink-host")
	command := exec.CommandContext(ctx, host, "manage-tun-service")
	input, err := command.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	output, err := command.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	var diagnostics bytes.Buffer
	command.Stderr = &diagnostics
	if err = command.Start(); err != nil {
		t.Fatal(err)
	}
	defer input.Close()
	encode, decode := json.NewEncoder(input), json.NewDecoder(output)
	id := 0
	call := func(method string) (json.RawMessage, *failure) {
		t.Helper()
		id++
		if err := encode.Encode(map[string]any{"id": id, "method": method, "payload": map[string]any{}}); err != nil {
			t.Fatal(err)
		}
		var result struct {
			ID     int
			Result json.RawMessage
			Error  *failure
		}
		if err := decode.Decode(&result); err != nil {
			t.Fatal("management reply", err)
		}
		if result.ID != id {
			t.Fatal("wrong reply identifier", result.ID)
		}
		return result.Result, result.Error
	}
	status := func(want string) {
		t.Helper()
		raw, failure := call("status")
		var value linuxinstall.ServiceStatus
		if failure != nil || json.Unmarshal(raw, &value) != nil || value.State != want || !value.CanManage {
			t.Fatalf("service status: %s %v, want %s", raw, failure, want)
		}
		t.Logf("status: %s", raw)
	}
	status("missing")
	_, failed := call("install")
	if scenario == "deny" {
		if failed == nil || !strings.HasPrefix(failed.Code, "authorization_") {
			t.Fatal("denied authorization was not reported", failed)
		}
		status("missing")
	} else {
		if failed != nil {
			t.Fatal("installation failed", failed)
		}
		status("current")
		for _, method := range []string{"recover", "install", "uninstall"} {
			result, failed := call(method)
			if failed != nil || !bytes.Contains(result, []byte(`"completed":true`)) {
				t.Fatal(method, string(result), failed)
			}
			want := "current"
			if method == "uninstall" {
				want = "missing"
			}
			status(want)
		}
	}
	if err := input.Close(); err != nil {
		t.Fatal(err)
	}
	if err := command.Wait(); err != nil {
		t.Fatal("broker exit", err, diagnostics.String())
	}
	fmt.Fprintln(os.Stdout, "real ordinary broker scenario completed:", scenario)
}
