//go:build windows

package update

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"golang.org/x/sys/windows"
)

func TestInstallationMutexDoesNotWriteFilesAndSeparatesInstallations(t *testing.T) {
	target := t.TempDir()
	lease, err := AcquireLock(target)
	if err != nil {
		t.Fatal(err)
	}
	defer lease.Close()
	result := make(chan error, 1)
	go func() {
		other, err := AcquireLock(target)
		if err == nil {
			other.Close()
		}
		result <- err
	}()
	if err := <-result; !errors.Is(err, ErrInstallationBusy) {
		t.Fatalf("concurrent launcher did not respect lease: %v", err)
	}
	other, err := AcquireLock(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if err := other.Close(); err != nil {
		t.Fatal(err)
	}
	entries, err := os.ReadDir(target)
	if err != nil || len(entries) != 0 {
		t.Fatal("normal launch writes into the installation directory")
	}
}

func TestWindowsBootstrapCasingCannotRemoveRecoveryEntry(t *testing.T) {
	oldFiles, nextFiles := bootstrapFiles("old"), bootstrapFiles("new")
	for _, files := range []map[string][]byte{oldFiles, nextFiles} {
		files["RAINLINK.EXE"] = files["rainlink.exe"]
		delete(files, "rainlink.exe")
	}
	target := installFixture(t, oldFiles)
	archive, hash := writeBundle(t, "0.2.0+1", nextFiles, nil)
	transaction, err := Prepare(context.Background(), Request{Target: target,
		Support: t.TempDir(), Archive: archive, SHA256: hash, Version: "0.2.0+1"})
	if err != nil {
		t.Fatal(err)
	}
	if err := transaction.snapshotData(context.Background()); err != nil {
		t.Fatal(err)
	}
	if err := transaction.replace(); err != nil {
		t.Fatal(err)
	}
	if err := verifyRoot(context.Background(), target, "rainlink.exe", transaction.previous); err != nil {
		t.Fatal("case variant moved the surviving bootstrap")
	}
	if _, _, err := Recover(context.Background(), target); err != nil {
		t.Fatal(err)
	}
}

func TestKilledHelperRecoveryThroughRealBootstrap(t *testing.T) {
	binaries := t.TempDir()
	for name, source := range map[string]string{
		"fixture.exe": "./internal/update/testdata/fixture.go",
		"updater.exe": "./cmd/rainlink-updater", "launcher.exe": "./cmd/rainlink-launcher",
	} {
		command := exec.Command("go", "build", "-trimpath", "-o", filepath.Join(binaries, name), source)
		command.Dir = "../.."
		if output, err := command.CombinedOutput(); err != nil {
			t.Fatalf("build recovery binaries: %v %s", err, output)
		}
	}
	fixture, err := os.ReadFile(filepath.Join(binaries, "fixture.exe"))
	if err != nil {
		t.Fatal(err)
	}
	launcher, err := os.ReadFile(filepath.Join(binaries, "launcher.exe"))
	if err != nil {
		t.Fatal(err)
	}
	for _, accepted := range []bool{false, true} {
		t.Run(strconv.FormatBool(accepted), func(t *testing.T) {
			oldFiles, nextFiles := bootstrapFiles("old"), bootstrapFiles("new")
			for _, files := range []map[string][]byte{oldFiles, nextFiles} {
				files["rainlink.exe"], files["rainlink-ui.exe"] = launcher, fixture
			}
			target := installFixture(t, oldFiles)
			support := t.TempDir()
			writeOriginalData(t, support)
			hold := "hold-before-ready"
			if accepted {
				hold = "hold-before-consumed"
			}
			if err := os.WriteFile(filepath.Join(support, hold), nil, 0600); err != nil {
				t.Fatal(err)
			}
			archive, hash := writeBundle(t, "0.2.0+1", nextFiles, nil)
			ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
			defer cancel()
			parent := exec.CommandContext(ctx, filepath.Join(target, "rainlink-ui.exe"), "--wait")
			parent.Env = append(os.Environ(), "RAINLINK_UPDATE_FIXTURE_SUPPORT="+support)
			parentInput, err := parent.StdinPipe()
			if err != nil {
				t.Fatal(err)
			}
			if err := parent.Start(); err != nil {
				t.Fatal(err)
			}
			defer func() { parentInput.Close(); parent.Process.Kill(); parent.Wait() }()
			awaitFile(t, filepath.Join(support, "parent-ready"))
			busyRepair := exec.CommandContext(ctx, filepath.Join(target, "rainlink.exe"), "--repair")
			if output, err := busyRepair.CombinedOutput(); err == nil || !strings.Contains(string(output), `"error":"busy"`) {
				t.Fatalf("repair reported success while runtime was live: %v %s", err, output)
			}
			helper := exec.CommandContext(ctx, filepath.Join(binaries, "updater.exe"))
			helper.Env = parent.Env
			input, err := helper.StdinPipe()
			if err != nil {
				t.Fatal(err)
			}
			output, err := helper.StdoutPipe()
			if err != nil {
				t.Fatal(err)
			}
			if err := helper.Start(); err != nil {
				t.Fatal(err)
			}
			defer func() { input.Close(); helper.Process.Kill(); helper.Wait() }()
			scanner := bufio.NewScanner(output)
			if err := json.NewEncoder(input).Encode(Request{Target: target, Support: support,
				Archive: archive, SHA256: hash, Version: "v0.2.0+1", Parent: uint32(parent.Process.Pid)}); err != nil {
				t.Fatal(err)
			}
			if !scanner.Scan() || scanner.Text() != `{"status":"ready"}` {
				t.Fatalf("helper preparation failed: %s", scanner.Text())
			}
			if _, err := input.Write([]byte("{\"command\":\"commit\"}\n")); err != nil {
				t.Fatal(err)
			}
			if !scanner.Scan() || scanner.Text() != `{"status":"committed"}` {
				t.Fatal("helper commit failed")
			}
			parentInput.Close()
			if err := parent.Wait(); err != nil {
				t.Fatal(err)
			}
			awaitFile(t, filepath.Join(support, "candidate-pid"))
			pidBytes, err := os.ReadFile(filepath.Join(support, "candidate-pid"))
			if err != nil {
				t.Fatal(err)
			}
			pid, err := strconv.ParseUint(string(pidBytes), 10, 32)
			if err != nil {
				t.Fatal(err)
			}
			candidate, err := windows.OpenProcess(windows.SYNCHRONIZE|windows.PROCESS_TERMINATE, false, uint32(pid))
			if err != nil {
				t.Fatal(err)
			}
			defer func() {
				windows.TerminateProcess(candidate, 30)
				windows.WaitForSingleObject(candidate, 5000)
				windows.CloseHandle(candidate)
			}()
			if accepted {
				awaitFile(t, filepath.Join(support, "candidate-accepted"))
			}
			if err := helper.Process.Kill(); err != nil {
				t.Fatal(err)
			}
			if err := helper.Wait(); err == nil {
				t.Fatal("test did not interrupt the real helper")
			}
			state, err := windows.WaitForSingleObject(candidate, 1000)
			if err != nil || !accepted && state != windows.WAIT_OBJECT_0 || accepted && state != uint32(windows.WAIT_TIMEOUT) {
				t.Fatalf("helper-death candidate lifetime differs: accepted=%v state=%d err=%v", accepted, state, err)
			}
			if accepted {
				os.WriteFile(filepath.Join(support, "continue-consumed"), nil, 0600)
				if state, err := windows.WaitForSingleObject(candidate, 5000); err != nil || state != windows.WAIT_OBJECT_0 {
					t.Fatal("accepted candidate did not exit")
				}
			}
			// Use the actual surviving entry point. It recovers first, launches
			// the restored/accepted UI and releases the abandoned updater mutex.
			launch := exec.CommandContext(ctx, filepath.Join(target, "rainlink.exe"))
			launch.Env = parent.Env
			if output, err := launch.CombinedOutput(); err != nil {
				t.Fatalf("automatic bootstrap recovery: %v %s", err, output)
			}
			awaitFile(t, filepath.Join(support, "previous-restarted"))
			expected, status := testManifest("0.1.0+1", oldFiles), "interrupted-restored"
			if accepted {
				expected, status = testManifest("0.2.0+1", nextFiles), "installed"
				if data, err := os.ReadFile(filepath.Join(support, "rainlink.sqlite")); err != nil || string(data) != "candidate-database" {
					t.Fatal("accepted database lost after helper kill")
				}
			} else {
				assertOriginalData(t, support)
			}
			if err := verifyInstallation(ctx, target, expected); err != nil {
				t.Fatal(err)
			}
			data, err := os.ReadFile(filepath.Join(support, "update-result.json"))
			var receipt Outcome
			if err != nil || json.Unmarshal(data, &receipt) != nil || receipt.Status != status {
				t.Fatalf("wrong recovered receipt: %s %v", data, err)
			}
			repair := exec.CommandContext(ctx, filepath.Join(target, "rainlink.exe"), "--repair")
			if output, err := repair.CombinedOutput(); err != nil || !strings.Contains(string(output), `"recovered":false`) {
				t.Fatalf("repeated recovery was not idempotent: %v %s", err, output)
			}
		})
	}
}
