//go:build windows

package update

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func awaitFile(t *testing.T, name string) {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		if _, err := os.Stat(name); err == nil {
			return
		}
		time.Sleep(25 * time.Millisecond)
	}
	t.Fatal("fixture process did not acknowledge")
}

func TestRealWindowsHelperHandshakeReplacementAndRollback(t *testing.T) {
	binaries := t.TempDir()
	fixture := filepath.Join(binaries, "fixture.exe")
	updater := filepath.Join(binaries, "rainlink-updater.exe")
	for _, build := range []struct {
		target string
		source string
	}{{fixture, "./internal/update/testdata/fixture.go"}, {updater, "./cmd/rainlink-updater"}} {
		command := exec.Command("go", "build", "-trimpath", "-o", build.target, build.source)
		command.Dir = "../.."
		if output, err := command.CombinedOutput(); err != nil {
			t.Fatalf("build fixture: %v %s", err, output)
		}
	}
	fixtureBytes, err := os.ReadFile(fixture)
	if err != nil {
		t.Fatal(err)
	}
	for _, scenario := range []string{"install", "rollback", "abort", "wrong-parent"} {
		t.Run(scenario, func(t *testing.T) {
			support := t.TempDir()
			oldFiles := testFiles("old")
			oldFiles["rainlink.exe"] = fixtureBytes
			target := installFixture(t, oldFiles)
			nextFiles := testFiles("new")
			nextFiles["rainlink.exe"] = fixtureBytes
			archive, hash := writeBundle(t, "0.2.0+1", nextFiles, nil)
			for name, content := range map[string]string{"rainlink.sqlite": "original-database", "rainlink.sqlite-wal": "original-wal"} {
				if err := os.WriteFile(filepath.Join(support, name), []byte(content), 0600); err != nil {
					t.Fatal(err)
				}
			}
			if scenario == "rollback" {
				if err := os.WriteFile(filepath.Join(support, "fail-start"), nil, 0600); err != nil {
					t.Fatal(err)
				}
			}
			parent := exec.Command(filepath.Join(target, "rainlink.exe"), "--wait")
			parent.Env = append(os.Environ(), "RAINLINK_UPDATE_FIXTURE_SUPPORT="+support)
			parentInput, err := parent.StdinPipe()
			if err != nil {
				t.Fatal(err)
			}
			if err := parent.Start(); err != nil {
				t.Fatal(err)
			}
			parentDone := false
			defer func() {
				if !parentDone {
					parentInput.Close()
					if err := parent.Wait(); err != nil {
						t.Error(err)
					}
				}
			}()
			awaitFile(t, filepath.Join(support, "parent-ready"))
			helper := exec.Command(updater)
			helper.Env = parent.Env
			helperInput, err := helper.StdinPipe()
			if err != nil {
				t.Fatal(err)
			}
			helperOutput, err := helper.StdoutPipe()
			if err != nil {
				t.Fatal(err)
			}
			helperContext, cancelHelper := context.WithTimeout(context.Background(), 25*time.Second)
			defer cancelHelper()
			if err := helper.Start(); err != nil {
				t.Fatal(err)
			}
			helperDone := make(chan error, 1)
			lines := make(chan string, 8)
			go func() {
				scanner := bufio.NewScanner(helperOutput)
				for scanner.Scan() {
					lines <- scanner.Text()
				}
				helperDone <- helper.Wait()
			}()
			readStatus := func(expected string) {
				t.Helper()
				select {
				case line := <-lines:
					if line != `{"status":"`+expected+`"}` {
						t.Fatalf("expected %s, got %s", expected, line)
					}
				case <-helperContext.Done():
					t.Fatal("helper response timed out")
				}
			}
			request := Request{Target: target, Support: support, Archive: archive, SHA256: hash, Version: "v0.2.0+1", Parent: uint32(parent.Process.Pid)}
			if scenario == "wrong-parent" {
				request.Parent = uint32(os.Getpid())
			}
			if err := json.NewEncoder(helperInput).Encode(request); err != nil {
				t.Fatal(err)
			}
			if scenario == "wrong-parent" {
				readStatus("failed")
			} else {
				readStatus("ready")
				contents, err := os.ReadFile(filepath.Join(target, "data", "app.so"))
				if err != nil || string(contents) != "old-data/app.so" {
					t.Fatal("preparation replaced a running application")
				}
				if scenario == "abort" {
					io.WriteString(helperInput, `{"command":"abort"}`+"\n")
					readStatus("aborted")
				} else {
					io.WriteString(helperInput, `{"command":"commit"}`+"\n")
					readStatus("committed")
					// The parent is still alive, so commit must not replace files.
					time.Sleep(200 * time.Millisecond)
					contents, err := os.ReadFile(filepath.Join(target, "data", "app.so"))
					if err != nil || string(contents) != "old-data/app.so" {
						t.Fatal("helper did not wait on original process")
					}
					if err := parentInput.Close(); err != nil {
						t.Fatal(err)
					}
					if err := parent.Wait(); err != nil {
						t.Fatal(err)
					}
					parentDone = true
				}
			}
			if err := helperInput.Close(); err != nil {
				t.Fatal(err)
			}
			select {
			case helperErr := <-helperDone:
				if scenario == "install" || scenario == "abort" {
					if helperErr != nil {
						t.Fatal(helperErr)
					}
				}
			case <-helperContext.Done():
				helper.Process.Kill()
				t.Fatal("helper did not terminate")
			}
			if scenario == "install" || scenario == "rollback" {
				data, err := os.ReadFile(filepath.Join(support, "update-result.json"))
				if err != nil {
					t.Fatal(err)
				}
				var result Outcome
				if err := json.Unmarshal(data, &result); err != nil {
					t.Fatal(err)
				}
				expected := "installed"
				if scenario == "rollback" {
					expected = "rolled-back"
					awaitFile(t, filepath.Join(support, "previous-restarted"))
					for name, content := range map[string]string{"rainlink.sqlite": "original-database", "rainlink.sqlite-wal": "original-wal"} {
						actual, err := os.ReadFile(filepath.Join(support, name))
						if err != nil || string(actual) != content {
							t.Fatal("real helper did not restore database")
						}
					}
				} else {
					awaitFile(t, filepath.Join(support, "candidate-accepted"))
				}
				if result.Status != expected {
					t.Fatalf("expected %s, got %s", expected, result.Status)
				}
			}
			if _, err := os.Stat(filepath.Join(target, MarkerName)); !errors.Is(err, os.ErrNotExist) {
				t.Fatal("finished transaction left ordinary startup blocked")
			}
			entries, err := os.ReadDir(filepath.Dir(target))
			if err != nil {
				t.Fatal(err)
			}
			for _, entry := range entries {
				if strings.HasPrefix(entry.Name(), ".rainlink-update-") {
					t.Fatal("finished helper leaked staging")
				}
			}
		})
	}
}
