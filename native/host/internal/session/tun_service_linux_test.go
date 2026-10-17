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
	"strconv"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"golang.org/x/sys/unix"
	"rainlink.local/host/internal/linuxipc"
	"rainlink.local/host/internal/linuxnet"
	"rainlink.local/host/internal/linuxprocess"
	"rainlink.local/host/internal/linuxtun"
)

func TestLinuxTUNPermissionClientFixture(t *testing.T) {
	if os.Getenv("RAINLINK_PERMISSION_CLIENT_FIXTURE") != "1" {
		t.Skip("ordinary-user fixture subprocess only")
	}
	ctx, cancel := context.WithTimeout(t.Context(), 15*time.Second)
	defer cancel()
	connection, err := net.DialUnix("unix", nil, &net.UnixAddr{Name: os.Getenv("RAINLINK_PERMISSION_SOCKET"), Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close()
	peer, err := linuxipc.InspectRootService(connection)
	if err != nil {
		t.Fatal(err)
	}
	defer peer.Close()
	node := mobileNode("permission-fixture", "http")
	node.Server = "192.0.2.1"
	node.Port = 9
	request := MobileRequest{Node: &node, Mode: "global", TUN: true, Secrets: map[string]MobileCredentials{node.Credential: {}}}
	raw, err := json.Marshal(request)
	if err != nil {
		t.Fatal(err)
	}
	codec := linuxipc.NewCodec(connection)
	if err = codec.Write(ctx, linuxipc.Command{Version: linuxipc.ProtocolVersion, ID: 1, Method: "start", Payload: raw}); err != nil {
		t.Fatal(err)
	}
	clear(raw)
	reply, err := codec.Read(ctx)
	if err != nil {
		t.Fatal("permission start transport failed", err)
	}
	var started struct {
		Version int           `json:"version"`
		ID      int           `json:"id"`
		Result  LinuxTUNStart `json:"result"`
		Error   string        `json:"error"`
	}
	if err = json.Unmarshal(reply, &started); err != nil {
		t.Fatal(err)
	}
	clear(reply)
	if os.Getenv("RAINLINK_PERMISSION_EXPECT_DENIED") == "1" {
		if started.Error != "permission_denied" || started.Result.Snapshot.TUN {
			t.Fatal("authorization refusal was not retained", started.Error)
		}
		fmt.Println("denied")
		return
	}
	if started.Version != linuxipc.ProtocolVersion || started.ID != 1 || started.Error != "" || started.Result.Snapshot.Phase != "connected" ||
		!started.Result.Snapshot.TUN || started.Result.APIPort < 1024 || len(started.Result.APISecret) < 16 {
		t.Fatal("permission service did not confirm capture", started.Error)
	}
	fmt.Println("connected")
	commands := bufio.NewScanner(os.Stdin)
	for commands.Scan() {
		switch commands.Text() {
		case "stop":
			if err = codec.Write(ctx, linuxipc.Command{Version: linuxipc.ProtocolVersion, ID: 2, Method: "stop"}); err != nil {
				t.Fatal(err)
			}
			reply, err = codec.Read(ctx)
			if err != nil {
				t.Fatal("stop acknowledgement failed", err)
			}
			var stopped struct {
				ID     int `json:"id"`
				Result struct {
					Stopped bool `json:"stopped"`
				} `json:"result"`
				Error string `json:"error"`
			}
			if err = json.Unmarshal(reply, &stopped); err != nil || stopped.ID != 2 || !stopped.Result.Stopped || stopped.Error != "" {
				t.Fatal("unconfirmed recovery", err, stopped.Error)
			}
			fmt.Println("stopped")
			return
		case "eof":
			if err = connection.Close(); err != nil {
				t.Fatal(err)
			}
			fmt.Println("closed")
			return
		case "expect-eof":
			if _, err = codec.Read(ctx); !errors.Is(err, io.EOF) {
				t.Fatal("lost guardian did not close its private transport", err)
			}
			fmt.Println("lost")
			return
		default:
			t.Fatal("invalid client fixture instruction")
		}
	}
	if err = commands.Err(); err != nil {
		t.Fatal(err)
	}
}

type tunPermissionFixture struct {
	client         *exec.Cmd
	guardian       *exec.Cmd
	input          io.WriteCloser
	output         *bufio.Reader
	diagnostics    *permissionDiagnostics
	clientReaped   bool
	guardianReaped bool
}

type permissionDiagnostics struct {
	mu     sync.Mutex
	buffer bytes.Buffer
}

func (diagnostics *permissionDiagnostics) Write(data []byte) (int, error) {
	diagnostics.mu.Lock()
	defer diagnostics.mu.Unlock()
	return diagnostics.buffer.Write(data)
}

func (diagnostics *permissionDiagnostics) String() string {
	diagnostics.mu.Lock()
	defer diagnostics.mu.Unlock()
	return diagnostics.buffer.String()
}

func startTUNPermissionFixture(t *testing.T, denied bool) *tunPermissionFixture {
	return startTUNPermissionClientFixture(t, denied, "TestLinuxTUNPermissionClientFixture")
}

func startTUNPermissionClientFixture(t *testing.T, denied bool, clientTest string) *tunPermissionFixture {
	t.Helper()
	directory, err := os.MkdirTemp("/run", "rainlink-permission-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(directory) })
	if err = os.Chmod(directory, 0755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(directory, "service.sock")
	listener, err := net.ListenUnix("unix", &net.UnixAddr{Name: path, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	if err = os.Chmod(path, 0666); err != nil {
		t.Fatal(err)
	}
	if err = listener.SetDeadline(time.Now().Add(3 * time.Second)); err != nil {
		t.Fatal(err)
	}
	client := exec.Command(os.Args[0], "-test.run=^"+clientTest+"$", "-test.timeout=25s")
	client.Env = append(os.Environ(), "RAINLINK_PERMISSION_CLIENT_FIXTURE=1", "RAINLINK_PERMISSION_SOCKET="+path)
	if denied {
		client.Env = append(client.Env, "RAINLINK_PERMISSION_EXPECT_DENIED=1")
	}
	client.SysProcAttr = &syscall.SysProcAttr{Credential: &syscall.Credential{Uid: 65534, Gid: 65534}}
	input, err := client.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	stdout, err := client.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	client.Stderr = os.Stderr
	fixture := &tunPermissionFixture{client: client, input: input, output: bufio.NewReader(stdout), diagnostics: &permissionDiagnostics{}}
	t.Cleanup(func() {
		_ = input.Close()
		if fixture.guardian != nil && !fixture.guardianReaped {
			_ = fixture.guardian.Process.Kill()
			_ = fixture.guardian.Wait()
		}
		if !fixture.clientReaped {
			_ = client.Process.Kill()
			_ = client.Wait()
		}
	})
	if err = client.Start(); err != nil {
		fixture.clientReaped = true
		t.Fatal(err)
	}
	connection, err := listener.AcceptUnix()
	if err != nil {
		t.Fatal(err)
	}
	file, err := connection.File()
	_ = connection.Close()
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	guardian := exec.Command(installedTUNHost, "serve-tun")
	guardian.Env = []string{"PATH=", "LANG=C", "LC_ALL=C"}
	guardian.Stdin = file
	guardian.Stdout, guardian.Stderr = fixture.diagnostics, fixture.diagnostics
	if err = guardian.Start(); err != nil {
		t.Fatal(err)
	}
	fixture.guardian = guardian
	return fixture
}

func (fixture *tunPermissionFixture) expect(t *testing.T, want string) {
	t.Helper()
	line, err := fixture.output.ReadString('\n')
	if err != nil || strings.TrimSpace(line) != want {
		if strings.HasPrefix(line, "--- FAIL:") {
			rest, _ := io.ReadAll(fixture.output)
			line += string(rest)
		}
		t.Fatal("permission fixture stage failed", want, strings.TrimSpace(line), err, fixture.diagnostics.String())
	}
}

func (fixture *tunPermissionFixture) command(t *testing.T, command string) {
	t.Helper()
	if _, err := io.WriteString(fixture.input, command+"\n"); err != nil {
		t.Fatal(err)
	}
}

func (fixture *tunPermissionFixture) wait(t *testing.T, guardianSuccess, clientSuccess bool) {
	t.Helper()
	guardianError := fixture.guardian.Wait()
	fixture.guardianReaped = true
	clientError := fixture.client.Wait()
	fixture.clientReaped = true
	if (guardianError == nil) != guardianSuccess || (clientError == nil) != clientSuccess {
		t.Fatal("unexpected permission fixture exit", guardianError, clientError, fixture.diagnostics.String())
	}
}

func permissionWatchdog(t *testing.T, pid int) linuxprocess.Identity {
	t.Helper()
	tasks, err := os.ReadDir("/proc/" + strconv.Itoa(pid) + "/task")
	if err != nil {
		t.Fatal(err)
	}
	for _, task := range tasks {
		children, err := os.ReadFile("/proc/" + strconv.Itoa(pid) + "/task/" + task.Name() + "/children")
		if err != nil {
			continue
		}
		for _, child := range strings.Fields(string(children)) {
			command, err := os.ReadFile("/proc/" + child + "/cmdline")
			if err != nil || !bytes.Contains(command, []byte("\x00watch-tun\x00")) {
				continue
			}
			childPID, err := strconv.Atoi(child)
			if err != nil {
				t.Fatal(err)
			}
			identity, alive, err := linuxprocess.ReadIdentity(childPID)
			if err != nil || !alive {
				t.Fatal(err)
			}
			return identity
		}
	}
	t.Fatal("guardian has no independent watchdog")
	return linuxprocess.Identity{}
}

func TestIsolatedLinuxTUNPermissionLifecycle(t *testing.T) {
	if os.Geteuid() != 0 || os.Getenv("RAINLINK_TEST_ROOT_TUN_NAMESPACE") != "isolated" {
		t.Skip("requires disposable root namespace")
	}
	namespace, err := os.Readlink("/proc/self/ns/net")
	parent := os.Getenv("RAINLINK_TEST_PARENT_NETNS")
	if err != nil || parent == "" || namespace == parent {
		t.Fatal("permission lifecycle fixture is not isolated", err)
	}
	const pkcheck = "/usr/bin/pkcheck"
	if _, err = os.Lstat(pkcheck); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("fixture must not replace the system authorizer", err)
	}
	if err = os.WriteFile(pkcheck, []byte("#!/bin/sh\nexit 0\n"), 0755); err != nil {
		t.Fatal(err)
	}
	defer os.Remove(pkcheck)
	for _, scenario := range []string{"stop", "eof", "client-killed", "core-killed", "watchdog-killed", "guardian-killed", "permission-denied"} {
		t.Run(scenario, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(t.Context(), 8*time.Second)
			defer cancel()
			before, err := linuxnet.Read(ctx)
			if err != nil {
				t.Fatal(err)
			}
			observed := map[string]any{"scenario": scenario, "before": before}
			denied := scenario == "permission-denied"
			if denied {
				if err = os.WriteFile(pkcheck, []byte("#!/bin/sh\nexit 1\n"), 0755); err != nil {
					t.Fatal(err)
				}
			}
			fixture := startTUNPermissionFixture(t, denied)
			if denied {
				fixture.expect(t, "denied")
				fixture.wait(t, true, true)
			} else {
				fixture.expect(t, "connected")
				var journal struct {
					Owner     linuxprocess.Identity  `json:"owner"`
					Core      linuxprocess.Identity  `json:"core"`
					Resources linuxtun.Specification `json:"resources"`
				}
				data, err := os.ReadFile("/run/rainlink-tun/capture-recovery.json")
				if err != nil || json.Unmarshal(data, &journal) != nil || journal.Owner.PID != fixture.guardian.Process.Pid || !journal.Core.Valid() {
					t.Fatal("guardian did not bind the live core before capture", err)
				}
				if err = confirmManagedTUN(ctx, journal.Resources); err != nil {
					t.Fatal(err)
				}
				watchdogIdentity := permissionWatchdog(t, fixture.guardian.Process.Pid)
				ready, readErr := linuxnet.Read(ctx)
				if readErr != nil {
					t.Fatal(readErr)
				}
				observed["ready"], observed["resources"] = ready, journal.Resources
				observed["guardian"], observed["core"], observed["watchdog"] = journal.Owner, journal.Core, watchdogIdentity
				watchdog, err := linuxprocess.Open(watchdogIdentity)
				if err != nil {
					t.Fatal(err)
				}
				defer watchdog.Close()
				switch scenario {
				case "stop":
					fixture.command(t, "stop")
					fixture.expect(t, "stopped")
					fixture.wait(t, true, true)
				case "eof":
					fixture.command(t, "eof")
					fixture.expect(t, "closed")
					fixture.wait(t, false, true)
				case "client-killed":
					if err = fixture.client.Process.Kill(); err != nil {
						t.Fatal(err)
					}
					fixture.wait(t, false, false)
				case "core-killed":
					core, err := linuxprocess.Open(journal.Core)
					if err != nil {
						t.Fatal(err)
					}
					err = core.Signal(unix.SIGKILL)
					_ = core.Close()
					if err != nil {
						t.Fatal(err)
					}
					fixture.command(t, "expect-eof")
					fixture.expect(t, "lost")
					fixture.wait(t, false, true)
				case "watchdog-killed":
					if err = watchdog.Signal(unix.SIGKILL); err != nil {
						t.Fatal(err)
					}
					fixture.command(t, "expect-eof")
					fixture.expect(t, "lost")
					fixture.wait(t, false, true)
				case "guardian-killed":
					if err = fixture.guardian.Process.Kill(); err != nil {
						t.Fatal(err)
					}
					fixture.command(t, "expect-eof")
					fixture.expect(t, "lost")
					fixture.wait(t, false, true)
				}
				if err = watchdog.Wait(ctx); err != nil {
					t.Fatal("independent watchdog remained after session cleanup", err)
				}
				if alive, err := linuxprocess.Alive(journal.Core); err != nil || alive {
					t.Fatal("permission session left a core alive", err)
				}
			}
			if _, err = os.Stat("/run/rainlink-tun/capture-recovery.json"); !errors.Is(err, os.ErrNotExist) {
				t.Fatal("permission session retained a recovered journal", err)
			}
			after, err := linuxnet.Read(ctx)
			observed["after"] = after
			if directory := os.Getenv("RAINLINK_TEST_NETWORK_EVIDENCE_DIR"); directory != "" && err == nil {
				data, encodeErr := json.MarshalIndent(observed, "", "  ")
				if encodeErr != nil {
					t.Fatal(encodeErr)
				}
				if writeErr := os.WriteFile(filepath.Join(directory, "permission-"+scenario+"-state.json"), append(data, '\n'), 0600); writeErr != nil {
					t.Fatal(writeErr)
				}
			}
			if err != nil || !reflect.DeepEqual(before, after) {
				t.Fatal("permission session failed to restore exact network state", err)
			}
		})
	}
}
