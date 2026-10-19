//go:build linux && !android

package linuxmanage

import (
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
	"rainlink.local/host/internal/privatefs"
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
	for _, scenario := range []string{"deny", "allow", "upgrade", "cancel", "eof"} {
		t.Run(scenario, func(t *testing.T) {
			decision := "NO"
			if scenario != "deny" {
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
			if scenario == "upgrade" {
				previous := filepath.Join(filepath.Dir(os.Args[0]), "previous", "rainlink-host")
				old, err := os.ReadFile(previous)
				if err != nil {
					t.Fatal("previous QA build unavailable", err)
				}
				current, err := os.ReadFile(filepath.Join(filepath.Dir(os.Args[0]), "rainlink-host"))
				if err != nil || bytes.Equal(old, current) {
					t.Fatal("upgrade requires distinct, valid QA host builds", err)
				}
				if data, err := exec.CommandContext(ctx, previous, "install-tun").CombinedOutput(); err != nil {
					t.Fatalf("previous QA install: %v %s", err, data)
				}
				if data, err := exec.CommandContext(ctx, "/usr/bin/systemctl", "disable", "--now", "rainlink-tun.socket").CombinedOutput(); err != nil {
					t.Fatalf("disable previous socket: %v %s", err, data)
				}
			}
			client := exec.CommandContext(ctx, os.Args[0], "-test.v", "-test.run=^TestOrdinaryManagementClientFixture$", "-test.timeout=150s")
			client.Env = []string{"PATH=/usr/bin:/bin", "LANG=C", "LC_ALL=C", "RAINLINK_TEST_MANAGEMENT_CLIENT=" + scenario}
			client.SysProcAttr = &syscall.SysProcAttr{Credential: &syscall.Credential{Uid: 65534, Gid: 65534}}
			var data bytes.Buffer
			client.Stdout, client.Stderr = &data, &data
			var gateRead, gateWrite *os.File
			if scenario == "cancel" || scenario == "eof" {
				directory, err := privatefs.Open("/var/lib/rainlink/tun-install")
				if err != nil {
					t.Fatal(err)
				}
				defer directory.Close()
				unlock, err := directory.Lock(ctx, "install.lock")
				if err != nil {
					t.Fatal(err)
				}
				defer unlock()
				gateRead, gateWrite, err = os.Pipe()
				if err != nil {
					t.Fatal(err)
				}
				defer gateRead.Close()
				defer gateWrite.Close()
				client.ExtraFiles = []*os.File{gateRead}
			}
			if err := client.Start(); err != nil {
				t.Fatal(err)
			}
			waited := false
			defer func() {
				if !waited {
					if err := client.Process.Kill(); err != nil && !errors.Is(err, os.ErrProcessDone) {
						t.Error(err)
					}
					_ = client.Wait()
				}
			}()
			elevatedPID := 0
			if gateWrite != nil {
				if err := gateRead.Close(); err != nil {
					t.Fatal(err)
				}
				elevatedPID = waitForBlockedElevatedWorker(t, ctx, client.Process.Pid)
				if _, err := gateWrite.Write([]byte{'C'}); err != nil {
					t.Fatal(err)
				}
			}
			err := client.Wait()
			waited = true
			if directory := os.Getenv("RAINLINK_TEST_MANAGEMENT_EVIDENCE"); directory != "" {
				if writeErr := os.WriteFile(filepath.Join(directory, "ordinary-broker-"+scenario+".log"), data.Bytes(), 0600); writeErr != nil {
					t.Fatal(writeErr)
				}
			}
			if err != nil {
				t.Fatalf("ordinary management failed: %v %s", err, data.Bytes())
			}
			if elevatedPID != 0 {
				if _, err := os.Stat(fmt.Sprintf("/proc/%d", elevatedPID)); !os.IsNotExist(err) {
					t.Fatal("elevated worker remained alive after cancellation", elevatedPID, err)
				}
				entries, err := os.ReadDir("/var/lib/rainlink/tun-install")
				if err != nil {
					t.Fatal(err)
				}
				for _, entry := range entries {
					if entry.Name() != "install.lock" {
						t.Fatal("cancelled operation left installation data", entry.Name())
					}
				}
				t.Logf("root worker %d exited before the installation lock was released", elevatedPID)
			}
			t.Logf("actual pkexec/polkit %s: %s", scenario, data.Bytes())
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
	status := func(want string) linuxinstall.ServiceStatus {
		t.Helper()
		raw, failure := call("status")
		var value linuxinstall.ServiceStatus
		if failure != nil || json.Unmarshal(raw, &value) != nil || value.State != want || !value.CanManage {
			t.Fatalf("service status: %s %v, want %s", raw, failure, want)
		}
		t.Logf("status: %s", raw)
		if scenario == "upgrade" && want != "missing" && (value.Enabled || value.Active) {
			t.Fatal("upgrade changed the disabled, inactive socket state", value)
		}
		return value
	}
	if scenario == "upgrade" {
		status("different")
	} else {
		status("missing")
	}
	if scenario == "cancel" || scenario == "eof" {
		id++
		if err := encode.Encode(map[string]any{"id": id, "method": "install"}); err != nil {
			t.Fatal(err)
		}
		gate := os.NewFile(3, "root-fixture-gate")
		if gate == nil {
			t.Fatal("root fixture gate missing")
		}
		defer gate.Close()
		var ready [1]byte
		if _, err := io.ReadFull(gate, ready[:]); err != nil || ready[0] != 'C' {
			t.Fatal("root did not observe an elevated worker waiting on the real lock", err)
		}
		if scenario == "eof" {
			if err := input.Close(); err != nil {
				t.Fatal(err)
			}
			var exit *exec.ExitError
			if err := command.Wait(); !errors.As(err, &exit) || exit.ExitCode() != 1 {
				t.Fatal("EOF did not retain the cancelled transaction failure", err)
			}
			fmt.Fprintln(os.Stdout, "actual EOF cancelled elevated transaction before lock release")
			return
		}
		ack, failed := call("cancel")
		var requested map[string]bool
		if failed != nil || json.Unmarshal(ack, &requested) != nil || !requested["requested"] {
			t.Fatal("cancel request was not acknowledged", string(ack), failed)
		}
		var original struct {
			ID     int
			Error  *failure
			Result json.RawMessage
		}
		if err := decode.Decode(&original); err != nil || original.ID != 2 || original.Error == nil || original.Error.Code != "cancelled" || len(original.Result) != 0 {
			t.Fatal("original install did not report actual cancellation", original, err)
		}
		status("missing")
		if err := input.Close(); err != nil {
			t.Fatal(err)
		}
		if err := command.Wait(); err != nil {
			t.Fatal("broker did not exit after confirmed cancellation", err)
		}
		fmt.Fprintln(os.Stdout, "actual cancel retained original failure and confirmed absent service")
		return
	}
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

// No production fault-injection hook: the VM controller holds the real lock and
// observes the root process's open descriptor before allowing the user to cancel.
func waitForBlockedElevatedWorker(t *testing.T, parent context.Context, clientPID int) int {
	t.Helper()
	ctx, cancel := context.WithTimeout(parent, 45*time.Second)
	defer cancel()
	ticker := time.NewTicker(50 * time.Millisecond)
	defer ticker.Stop()
	for {
		paths, err := filepath.Glob("/proc/[0-9]*/cmdline")
		if err != nil {
			t.Fatal(err)
		}
		for _, path := range paths {
			data, err := os.ReadFile(path)
			if err != nil {
				continue
			}
			args := bytes.Split(data, []byte{0})
			if len(args) < 3 || string(args[1]) != "manage-tun-elevated" || string(args[2]) != "install" {
				continue
			}
			pid, err := strconv.Atoi(filepath.Base(filepath.Dir(path)))
			if err != nil {
				t.Fatal(err)
			}
			brokerPID, uid, err := fixtureProcessParent(pid)
			if err != nil || uid != 0 {
				continue
			}
			ownerPID, _, err := fixtureProcessParent(brokerPID)
			if err != nil || ownerPID != clientPID {
				continue
			}
			fds, err := os.ReadDir(fmt.Sprintf("/proc/%d/fd", pid))
			if err != nil {
				continue
			}
			for _, fd := range fds {
				target, err := os.Readlink(fmt.Sprintf("/proc/%d/fd/%s", pid, fd.Name()))
				if err == nil && target == "/var/lib/rainlink/tun-install/install.lock" {
					return pid
				}
			}
		}
		select {
		case <-ctx.Done():
			t.Fatal("elevated worker never reached the held installation lock", ctx.Err())
		case <-ticker.C:
		}
	}
}

func fixtureProcessParent(pid int) (parent, uid int, err error) {
	data, err := os.ReadFile(fmt.Sprintf("/proc/%d/status", pid))
	if err != nil {
		return 0, 0, err
	}
	parent, uid = -1, -1
	for _, line := range strings.Split(string(data), "\n") {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		switch fields[0] {
		case "PPid:":
			parent, err = strconv.Atoi(fields[1])
		case "Uid:":
			uid, err = strconv.Atoi(fields[1])
		}
		if err != nil {
			return 0, 0, err
		}
	}
	if parent < 0 || uid < 0 {
		return 0, 0, fmt.Errorf("missing process identity")
	}
	return parent, uid, nil
}
