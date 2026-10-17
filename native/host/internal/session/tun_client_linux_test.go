//go:build linux && !android

package session

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"rainlink.local/host/internal/linuxipc"
	"rainlink.local/host/internal/linuxnet"
	"rainlink.local/host/internal/linuxprocess"
	"rainlink.local/host/internal/linuxtun"
)

func requireIsolatedTUNClient(t *testing.T) {
	t.Helper()
	if os.Geteuid() != 0 || os.Getenv("RAINLINK_TEST_ROOT_TUN_NAMESPACE") != "isolated" {
		t.Skip("requires disposable root namespaces")
	}
	namespace, err := os.Readlink("/proc/self/ns/net")
	parent := os.Getenv("RAINLINK_TEST_PARENT_NETNS")
	if err != nil || parent == "" || namespace == parent {
		t.Fatal("native client fixture is not isolated", err)
	}
}

func requireTUNFailure(t *testing.T, err error, code string) {
	t.Helper()
	var failure *Failure
	if !errors.As(err, &failure) || failure.Code != code {
		t.Fatal("native client lost its failure category", err, code)
	}
}

func TestLinuxTUNClientRetainsDeadlineBeforeContextTimer(t *testing.T) {
	// This models the real deadline-versus-context publication race observed
	// during cancelled pkcheck; EOF must remain a separate failure category.
	requireTUNFailure(t, linuxTUNTransportFailure(context.Background(), context.DeadlineExceeded), "cancelled")
	requireTUNFailure(t, linuxTUNTransportFailure(context.Background(), net.ErrClosed), "tun_service_lost")
}

// These are synthetic IPC replies, not evidence of actual TUN forwarding.
func TestIsolatedLinuxTUNNativeClientRejectsInvalidReceipts(t *testing.T) {
	requireIsolatedTUNClient(t)
	started := LinuxTUNStart{Snapshot: Snapshot{Phase: "connected", SessionID: "fixture-session", TUN: true, TUNInterface: "rl-abcdefgh", ProxyPort: 22001}, APIPort: 22002, APISecret: "fixture-api-secret-only",
		Resources: linuxtun.Specification{Name: "rl-abcdefgh", Table: 100001, Priority: 16000}}
	for _, scenario := range []string{"wrong-start-id", "missing-start-result", "unconfirmed-start", "low-api-port", "unknown-start-field", "denied", "authorization-unavailable", "wrong-stop-id", "false-stop", "pending-recovery", "lost-service", "unsolicited-stop", "concurrent-stop", "stop-cancelled"} {
		t.Run(scenario, func(t *testing.T) {
			directory, err := os.MkdirTemp("/run", "rainlink-native-reply-")
			if err != nil {
				t.Fatal(err)
			}
			defer os.RemoveAll(directory)
			path := filepath.Join(directory, "service.sock")
			listener, err := net.ListenUnix("unix", &net.UnixAddr{Name: path, Net: "unix"})
			if err != nil {
				t.Fatal(err)
			}
			defer listener.Close()
			ctx, cancel := context.WithTimeout(t.Context(), 3*time.Second)
			defer cancel()
			if err = listener.SetDeadline(time.Now().Add(2 * time.Second)); err != nil {
				t.Fatal(err)
			}
			serverDone := make(chan error, 1)
			go func() {
				connection, err := listener.AcceptUnix()
				if err != nil {
					serverDone <- err
					return
				}
				defer connection.Close()
				codec := linuxipc.NewCodec(connection)
				hello, err := codec.Read(ctx)
				if err != nil {
					serverDone <- err
					return
				}
				command, err := linuxipc.ParseCommand(hello)
				clear(hello)
				identity, alive, identityErr := linuxprocess.ReadIdentity(os.Getpid())
				if err != nil || command.Method != "hello" || command.ID != 1 || identityErr != nil || !alive {
					serverDone <- errors.New("hello command or server identity missing")
					return
				}
				if err = codec.Write(ctx, linuxipc.Reply{Version: linuxipc.ProtocolVersion, ID: 1, Result: identity}); err != nil {
					serverDone <- err
					return
				}
				raw, err := codec.Read(ctx)
				if err != nil {
					serverDone <- err
					return
				}
				command, err = linuxipc.ParseCommand(raw)
				clear(raw)
				clear(command.Payload)
				if err != nil || command.Method != "start" || command.ID != 2 {
					serverDone <- errors.New("start command missing")
					return
				}
				value := started
				reply := linuxipc.Reply{Version: linuxipc.ProtocolVersion, ID: 2, Result: value}
				switch scenario {
				case "wrong-start-id":
					reply.ID = 1
				case "missing-start-result":
					reply.Result = nil
				case "unconfirmed-start":
					value.Snapshot.Phase = "connecting"
					reply.Result = value
				case "low-api-port":
					value.APIPort = 80
					reply.Result = value
				case "unknown-start-field":
					reply.Result = map[string]any{"unknown": "fixture"}
				case "denied":
					reply.Result = nil
					reply.Error = "permission_denied"
				case "authorization-unavailable":
					reply.Result = nil
					reply.Error = "authorization_unavailable"
				}
				if err = codec.Write(ctx, reply); err != nil {
					serverDone <- err
					return
				}
				switch scenario {
				case "wrong-start-id", "missing-start-result", "unconfirmed-start", "low-api-port", "unknown-start-field", "denied", "authorization-unavailable", "lost-service":
					serverDone <- nil
					return
				case "unsolicited-stop":
					serverDone <- codec.Write(ctx, linuxipc.Reply{Version: linuxipc.ProtocolVersion, ID: 3, Result: map[string]bool{"stopped": true}})
					return
				}
				raw, err = codec.Read(ctx)
				if err != nil {
					serverDone <- err
					return
				}
				command, err = linuxipc.ParseCommand(raw)
				clear(raw)
				if err != nil || command.Method != "stop" || command.ID != 3 {
					serverDone <- errors.New("one ordered stop command required")
					return
				}
				stop := linuxipc.Reply{Version: linuxipc.ProtocolVersion, ID: 3, Result: map[string]bool{"stopped": true}}
				switch scenario {
				case "wrong-stop-id":
					stop.ID = 2
				case "false-stop":
					stop.Result = map[string]bool{"stopped": false}
				case "pending-recovery":
					stop.Result = nil
					stop.Error = "recovery_pending"
				}
				serverDone <- codec.Write(ctx, stop)
			}()
			node := mobileNode("fixture", "http")
			request := MobileRequest{Node: &node, Mode: "global", TUN: true, Secrets: map[string]MobileCredentials{node.Credential: {}}}
			client, err := dialLinuxTUNClient(ctx, path, request)
			startCode := ""
			switch scenario {
			case "wrong-start-id", "missing-start-result", "unconfirmed-start", "low-api-port", "unknown-start-field":
				startCode = "tun_service_invalid_reply"
			case "denied":
				startCode = "tun_permission_denied"
			case "authorization-unavailable":
				startCode = "tun_authorization_unavailable"
			}
			if startCode != "" {
				requireTUNFailure(t, err, startCode)
			} else {
				if err != nil {
					t.Fatal(err)
				}
				defer client.close()
				if scenario == "lost-service" || scenario == "unsolicited-stop" {
					select {
					case <-client.done:
					case <-ctx.Done():
						t.Fatal("transport loss was not detected")
					}
					code := "tun_service_lost"
					if scenario == "unsolicited-stop" {
						code = "tun_service_invalid_reply"
					}
					requireTUNFailure(t, client.stop(ctx), code)
				} else if scenario == "concurrent-stop" {
					var group sync.WaitGroup
					results := make(chan error, 8)
					for range 8 {
						group.Add(1)
						go func() { defer group.Done(); results <- client.stop(ctx) }()
					}
					group.Wait()
					close(results)
					for err := range results {
						if err != nil {
							t.Fatal("concurrent stop lost confirmation", err)
						}
					}
				} else {
					if scenario == "stop-cancelled" {
						cancelled, stop := context.WithCancel(ctx)
						stop()
						if err := client.stop(cancelled); !errors.Is(err, context.Canceled) {
							t.Fatal("cancelled stop lost category", err)
						}
					}
					err = client.stop(ctx)
					switch scenario {
					case "wrong-stop-id":
						requireTUNFailure(t, err, "tun_service_invalid_reply")
					case "false-stop", "pending-recovery":
						requireTUNFailure(t, err, "tun_restore_failed")
					default:
						if err != nil {
							t.Fatal(err)
						}
					}
				}
			}
			if err = <-serverDone; err != nil {
				t.Fatal("synthetic IPC server failed", err)
			}
		})
	}
}

func TestLinuxTUNNativeLifecycleClientFixture(t *testing.T) {
	if os.Getenv("RAINLINK_PERMISSION_CLIENT_FIXTURE") != "1" {
		t.Skip("ordinary native client subprocess only")
	}
	if os.Geteuid() != 65534 {
		t.Fatal("native lifecycle client must be an ordinary user")
	}
	ctx, cancel := context.WithTimeout(t.Context(), 15*time.Second)
	defer cancel()
	scenario := os.Getenv("RAINLINK_NATIVE_CLIENT_SCENARIO")
	var startup context.Context
	var finishStartup context.CancelFunc
	if scenario == "cancel-start" {
		startup, finishStartup = context.WithTimeout(ctx, 200*time.Millisecond)
	} else {
		startup, finishStartup = context.WithCancel(ctx)
	}
	defer finishStartup()
	node := mobileNode("native-lifecycle", "http")
	node.Server, node.Port = "192.0.2.1", 9
	request := MobileRequest{Node: &node, Mode: "global", TUN: true, Secrets: map[string]MobileCredentials{node.Credential: {}}}
	client, err := dialLinuxTUNClient(startup, os.Getenv("RAINLINK_PERMISSION_SOCKET"), request)
	if scenario == "cancel-start" {
		requireTUNFailure(t, err, "cancelled")
		fmt.Println("cancelled")
		return
	}
	if scenario == "permission-denied" {
		requireTUNFailure(t, err, "tun_permission_denied")
		fmt.Println("denied")
		return
	}
	if err != nil {
		t.Fatal(err)
	}
	defer client.close()
	finishStartup()
	fmt.Println("connected")
	commands := bufio.NewScanner(os.Stdin)
	if !commands.Scan() {
		t.Fatal("native lifecycle command missing", commands.Err())
	}
	switch commands.Text() {
	case "stop":
		if err = client.stop(ctx); err != nil {
			t.Fatal(err)
		}
		fmt.Println("stopped")
	case "eof":
		client.close()
		requireTUNFailure(t, client.stop(ctx), "tun_service_lost")
		fmt.Println("closed")
	case "lost":
		select {
		case <-client.done:
		case <-ctx.Done():
			t.Fatal("lost service was not detected")
		}
		requireTUNFailure(t, client.stop(ctx), "tun_service_lost")
		fmt.Println("lost")
	case "timeout":
		stop, stopCancel := context.WithTimeout(ctx, 100*time.Millisecond)
		err = client.stop(stop)
		stopCancel()
		requireTUNFailure(t, err, "tun_restore_failed")
		if !errors.Is(err, context.DeadlineExceeded) {
			t.Fatal("stop timeout lost its deadline", err)
		}
		fmt.Println("timeout")
	default:
		t.Fatal("invalid native lifecycle command")
	}
}

func TestIsolatedLinuxTUNNativeClientLifecycle(t *testing.T) {
	requireIsolatedTUNClient(t)
	const pkcheck = "/usr/bin/pkcheck"
	if _, err := os.Lstat(pkcheck); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("fixture must not replace the system authorizer", err)
	}
	defer os.Remove(pkcheck)
	for _, scenario := range []string{"stop", "eof", "guardian-killed", "stop-timeout", "permission-denied", "cancel-start"} {
		t.Run(scenario, func(t *testing.T) {
			t.Setenv("RAINLINK_NATIVE_CLIENT_SCENARIO", scenario)
			authorizer := "#!/bin/sh\nexit 0\n"
			if scenario == "permission-denied" {
				authorizer = "#!/bin/sh\nexit 1\n"
			}
			if scenario == "cancel-start" {
				authorizer = "#!/bin/sh\nexec /bin/sleep 10\n"
			}
			if err := os.WriteFile(pkcheck, []byte(authorizer), 0755); err != nil {
				t.Fatal(err)
			}
			ctx, cancel := context.WithTimeout(t.Context(), 8*time.Second)
			defer cancel()
			before, err := linuxnet.Read(ctx)
			if err != nil {
				t.Fatal(err)
			}
			fixture := startTUNPermissionClientFixture(t, false, "TestLinuxTUNNativeLifecycleClientFixture")
			var core linuxprocess.Identity
			observed := map[string]any{"scenario": scenario, "before": before}
			switch scenario {
			case "permission-denied":
				fixture.expect(t, "denied")
				fixture.wait(t, true, true)
			case "cancel-start":
				fixture.expect(t, "cancelled")
				fixture.wait(t, true, true)
			default:
				fixture.expect(t, "connected")
				var journal struct {
					Core      linuxprocess.Identity  `json:"core"`
					Resources linuxtun.Specification `json:"resources"`
				}
				data, err := os.ReadFile("/run/rainlink-tun/capture-recovery.json")
				if err != nil || json.Unmarshal(data, &journal) != nil || !journal.Core.Valid() {
					t.Fatal("native client has no leased core", err)
				}
				core = journal.Core
				observed["core"], observed["resources"] = core, journal.Resources
				if err = confirmManagedTUN(ctx, journal.Resources); err != nil {
					t.Fatal(err)
				}
				observed["ready"], err = linuxnet.Read(ctx)
				if err != nil {
					t.Fatal(err)
				}
				watchdog, err := linuxprocess.Open(permissionWatchdog(t, fixture.guardian.Process.Pid))
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
				case "guardian-killed":
					if err = fixture.guardian.Process.Kill(); err != nil {
						t.Fatal(err)
					}
					fixture.command(t, "lost")
					fixture.expect(t, "lost")
					fixture.wait(t, false, true)
				case "stop-timeout":
					if err = fixture.guardian.Process.Signal(syscall.SIGSTOP); err != nil {
						t.Fatal(err)
					}
					fixture.command(t, "timeout")
					fixture.expect(t, "timeout")
					if err = fixture.guardian.Process.Signal(syscall.SIGCONT); err != nil {
						t.Fatal(err)
					}
					fixture.wait(t, false, true)
				}
				if err = watchdog.Wait(ctx); err != nil {
					t.Fatal("native client left its watchdog alive", err)
				}
				if alive, err := linuxprocess.Alive(core); err != nil || alive {
					t.Fatal("native client left its core alive", err)
				}
			}
			if _, err = os.Stat("/run/rainlink-tun/capture-recovery.json"); !errors.Is(err, os.ErrNotExist) {
				t.Fatal("native client retained a recovery journal", err)
			}
			after, err := linuxnet.Read(ctx)
			observed["after"] = after
			if err != nil || !reflect.DeepEqual(before, after) {
				t.Fatal("native client did not restore the exact network", err)
			}
			if directory := os.Getenv("RAINLINK_TEST_NETWORK_EVIDENCE_DIR"); directory != "" {
				data, err := json.MarshalIndent(observed, "", "  ")
				if err != nil {
					t.Fatal(err)
				}
				if err = os.WriteFile(filepath.Join(directory, "native-"+strings.ReplaceAll(scenario, "/", "-")+"-state.json"), append(data, '\n'), 0600); err != nil {
					t.Fatal(err)
				}
			}
		})
	}
}
