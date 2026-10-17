//go:build linux && !android

package session

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"rainlink.local/host/internal/linuxipc"
	"rainlink.local/host/internal/linuxprocess"
	"rainlink.local/host/internal/linuxtun"
)

// Synthetic IPC checks cover ordering and compatibility; real root core output
// is separately verified through the ordinary Manager and Secret Service.
func TestIsolatedLinuxTUNLoggedClientReceipts(t *testing.T) {
	requireIsolatedTUNClient(t)
	for _, scenario := range []string{"success", "start-rejected", "invalid-start-log", "invalid-live-log", "missing-stop", "old-helper"} {
		t.Run(scenario, func(t *testing.T) {
			directory, err := os.MkdirTemp("/run", "rainlink-logged-receipt-")
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
			if err := listener.SetDeadline(time.Now().Add(3 * time.Second)); err != nil {
				t.Fatal(err)
			}
			ctx, cancel := context.WithTimeout(t.Context(), 4*time.Second)
			defer cancel()
			serverDone := make(chan error, 1)
			go func() {
				serverDone <- func() error {
					connection, err := listener.AcceptUnix()
					if err != nil {
						return err
					}
					defer connection.Close()
					codec := linuxipc.NewCodec(connection)
					readCommand := func(method string, id int) error {
						raw, err := codec.Read(ctx)
						if err != nil {
							return err
						}
						command, err := linuxipc.ParseCommand(raw)
						clear(raw)
						clear(command.Payload)
						if err != nil || command.Method != method || command.ID != id {
							return errors.New("ordered logged command required")
						}
						return nil
					}
					if err := readCommand(permissionLogHello, 1); err != nil {
						return err
					}
					if scenario == "old-helper" {
						// A v1 helper that lacks opt-in closes before start. The
						// client must not silently run without diagnostic support.
						return nil
					}
					identity, alive, err := linuxprocess.ReadIdentity(os.Getpid())
					if err != nil || !alive {
						return errors.New("fixture identity missing")
					}
					if err := codec.Write(ctx, linuxipc.Reply{Version: linuxipc.ProtocolVersion, ID: 1, Result: identity}); err != nil {
						return err
					}
					if err := readCommand("start", 2); err != nil {
						return err
					}
					logs := newLogBuffer()
					var cursor int64
					writeLog := func(message string, invalid bool) error {
						logs.append("info", "core", message)
						event, err := permissionLogEvent(logs.read(logs.id, cursor))
						if err != nil {
							return err
						}
						if invalid {
							event.Batch.Entries[0].Source = "untrusted-source"
						}
						cursor = event.Batch.Cursor
						return codec.Write(ctx, event)
					}
					if err := writeLog("startup fixture-private-password", scenario == "invalid-start-log"); err != nil {
						return err
					}
					if scenario == "invalid-start-log" {
						return nil
					}
					if scenario == "start-rejected" {
						return codec.Write(ctx, linuxipc.Reply{Version: linuxipc.ProtocolVersion, ID: 2, Error: "permission_denied"})
					}
					started := LinuxTUNStart{Snapshot: Snapshot{Phase: "connected", SessionID: "logged-fixture", TUN: true, TUNInterface: "rl-abcdefgh", ProxyPort: 22001}, APIPort: 22002, APISecret: "fixture-api-secret-only",
						Resources: linuxtun.Specification{Name: "rl-abcdefgh", Table: 100001, Priority: 16000}}
					if err := codec.Write(ctx, linuxipc.Reply{Version: linuxipc.ProtocolVersion, ID: 2, Result: started}); err != nil {
						return err
					}
					if err := writeLog("runtime fixture-api-secret-only", scenario == "invalid-live-log"); err != nil {
						return err
					}
					if scenario == "invalid-live-log" {
						return nil
					}
					if err := readCommand("stop", 3); err != nil {
						return err
					}
					if err := writeLog("final core output", false); err != nil {
						return err
					}
					if scenario == "missing-stop" {
						return nil
					}
					return codec.Write(ctx, linuxipc.Reply{Version: linuxipc.ProtocolVersion, ID: 3, Result: map[string]bool{"stopped": true}})
				}()
			}()
			node := mobileNode("logged-fixture", "http")
			request := MobileRequest{Node: &node, Mode: "global", TUN: true, Secrets: map[string]MobileCredentials{node.Credential: {Password: "fixture-private-password"}}}
			hostLogs := newLogBuffer()
			client, err := dialLinuxTUNClientWithLogs(ctx, path, request, hostLogs)
			switch scenario {
			case "old-helper":
				requireTUNFailure(t, err, "tun_service_handshake_failed")
				var uncertain *linuxTUNUnconfirmedStart
				if errors.As(err, &uncertain) {
					t.Fatal("failed negotiation was reported as an attempted start")
				}
			case "start-rejected":
				requireTUNFailure(t, err, "tun_permission_denied")
			case "invalid-start-log":
				requireTUNFailure(t, err, "tun_service_invalid_reply")
			default:
				if err != nil {
					t.Fatal(err)
				}
				defer client.close()
				if scenario == "invalid-live-log" {
					select {
					case <-client.done:
					case <-ctx.Done():
						t.Fatal("invalid live event was not rejected")
					}
					requireTUNFailure(t, client.stop(ctx), "tun_service_invalid_reply")
				} else if scenario == "missing-stop" {
					requireTUNFailure(t, client.stop(ctx), "tun_service_lost")
				} else {
					var group sync.WaitGroup
					for range 8 {
						group.Add(1)
						go func() {
							defer group.Done()
							if err := client.stop(ctx); err != nil {
								t.Error("logs broke concurrent stop confirmation", err)
							}
						}()
					}
					group.Wait()
				}
			}
			if err := <-serverDone; err != nil {
				t.Fatal("synthetic logged server failed", err)
			}
			messages := collectPermissionLogMessages(hostLogs)
			if scenario == "success" && len(messages) != 3 || scenario == "start-rejected" && len(messages) != 1 {
				t.Fatal("startup/live/terminal diagnostics were not delivered")
			}
			encoded, err := json.Marshal(messages)
			if err != nil || strings.Contains(string(encoded), "fixture-private-password") || strings.Contains(string(encoded), "fixture-api-secret-only") {
				t.Fatal("private credentials entered ordinary host logs")
			}
		})
	}
}
