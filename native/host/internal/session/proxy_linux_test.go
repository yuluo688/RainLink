//go:build linux && !android

package session

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"golang.org/x/sys/unix"
)

type linuxTestHost struct {
	t        *testing.T
	command  *exec.Cmd
	input    io.WriteCloser
	encoder  *json.Encoder
	decoder  *json.Decoder
	id       int
	finished bool
}

func newLinuxTestHost(t *testing.T, ctx context.Context, mode string) *linuxTestHost {
	t.Helper()
	path := os.Getenv("RAINLINK_TEST_HOST_PATH")
	if path == "" {
		t.Skip("set RAINLINK_TEST_HOST_PATH to run the bundled Linux host")
	}
	command := exec.CommandContext(ctx, path, mode)
	command.Stderr = io.Discard
	input, err := command.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	output, err := command.StdoutPipe()
	if err != nil {
		_ = input.Close()
		t.Fatal(err)
	}
	if err = command.Start(); err != nil {
		_ = input.Close()
		_ = output.Close()
		t.Fatal(err)
	}
	host := &linuxTestHost{t: t, command: command, input: input, encoder: json.NewEncoder(input), decoder: json.NewDecoder(output)}
	t.Cleanup(func() {
		if !host.finished {
			host.finish(true)
		}
	})
	return host
}

func (h *linuxTestHost) rpc(method string, payload, result any) *Failure {
	h.t.Helper()
	h.id++
	if err := h.encoder.Encode(map[string]any{"id": h.id, "method": method, "payload": payload}); err != nil {
		h.t.Fatal(err)
	}
	var reply struct {
		ID     int             `json:"id"`
		Result json.RawMessage `json:"result"`
		Error  *Failure        `json:"error"`
	}
	if err := h.decoder.Decode(&reply); err != nil {
		h.t.Fatal(err)
	}
	if reply.ID != h.id {
		h.t.Fatal("private reply identity mismatch")
	}
	if reply.Error == nil && result != nil {
		if err := json.Unmarshal(reply.Result, result); err != nil {
			h.t.Fatal(err)
		}
	}
	return reply.Error
}

func (h *linuxTestHost) finish(kill bool) {
	h.t.Helper()
	if h.finished {
		return
	}
	if kill {
		if err := h.command.Process.Kill(); err != nil && !errors.Is(err, os.ErrProcessDone) {
			h.t.Error(err)
		}
	}
	_ = h.input.Close()
	err := h.command.Wait()
	h.finished = true
	if !kill && err != nil {
		h.t.Fatalf("Linux EOF cleanup failed: %v", err)
	}
}

func dconfCommand(t *testing.T, input []byte, args ...string) []byte {
	t.Helper()
	return dconfCommandContext(t, t.Context(), input, args...)
}

func dconfCommandContext(t *testing.T, parent context.Context, input []byte, args ...string) []byte {
	t.Helper()
	ctx, cancel := context.WithTimeout(parent, 3*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, "/usr/bin/dconf", args...)
	command.Stdin = bytes.NewReader(input)
	output, err := command.Output()
	if err != nil {
		t.Fatalf("isolated dconf command failed: %v", err)
	}
	return output
}

func hostChild(t *testing.T, pid int, name string) int {
	t.Helper()
	paths, err := filepath.Glob(fmt.Sprintf("/proc/%d/task/*/children", pid))
	if err != nil {
		t.Fatal(err)
	}
	for _, path := range paths {
		data, err := os.ReadFile(path)
		if err != nil {
			continue // A Go OS thread may have ended during enumeration.
		}
		for _, value := range strings.Fields(string(data)) {
			child, err := strconv.Atoi(value)
			if err != nil {
				t.Fatal(err)
			}
			executable, err := os.Readlink("/proc/" + value + "/exe")
			if err == nil && filepath.Base(executable) == name {
				return child
			}
		}
	}
	t.Fatalf("host child %s was not running", name)
	return 0
}

func TestLinuxGNOMEHostCaptureAndCrashRecovery(t *testing.T) {
	if os.Getenv("RAINLINK_TEST_GNOME_PROXY") != "isolated" {
		t.Skip("requires an isolated session bus, dconf, keyring and XDG state")
	}
	requireCredentialStore(t)
	t.Setenv("XDG_CURRENT_DESKTOP", "GNOME")
	t.Setenv("GSETTINGS_BACKEND", "dconf")
	original := dconfCommand(t, nil, "dump", "/system/proxy/")
	t.Cleanup(func() {
		dconfCommandContext(t, context.Background(), nil, "reset", "-f", "/system/proxy/")
		if len(original) != 0 {
			dconfCommandContext(t, context.Background(), original, "load", "/system/proxy/")
		}
	})
	fixture := []byte("[/]\nmode='auto'\nautoconfig-url='https://example.test/fixture.pac'\nignore-hosts=['fixture.test']\nuse-same-proxy=true\nrainlink-unmanaged-fixture='keep'\n\n[http]\nhost='original.test'\nport=3128\nuse-authentication=true\nauthentication-user='fixture-user'\nauthentication-password='fixture-password'\n")
	dconfCommand(t, fixture, "load", "/system/proxy/")
	runLinuxCaptureScenarios(t, "GNOME", func(t *testing.T) []byte {
		return dconfCommand(t, nil, "dump", "/system/proxy/")
	}, func(t *testing.T, snapshot Snapshot) {
		for _, check := range []struct{ path, want string }{
			{"mode", "'manual'"}, {"http/host", "'127.0.0.1'"}, {"http/port", strconv.Itoa(snapshot.ProxyPort)},
			{"https/port", strconv.Itoa(snapshot.ProxyPort)}, {"socks/port", strconv.Itoa(snapshot.ProxyPort)},
		} {
			if got := strings.TrimSpace(string(dconfCommand(t, nil, "read", "/system/proxy/"+check.path))); got != check.want {
				t.Fatalf("system proxy readback mismatch: %s", check.path)
			}
		}
	})
}

func kdeProxySnapshot(t *testing.T) map[string]string {
	t.Helper()
	host := os.Getenv("RAINLINK_TEST_HOST_PATH")
	request, err := json.Marshal(map[string]any{"version": 1, "operation": "snapshot", "configRoot": os.Getenv("XDG_CONFIG_HOME")})
	if err != nil {
		t.Fatal(err)
	}
	command := exec.CommandContext(t.Context(), filepath.Join(filepath.Dir(host), "rainlink-kde-proxy"))
	command.Stdin = bytes.NewReader(request)
	output, err := command.Output()
	if err != nil {
		t.Fatal("isolated KDE configuration read failed", err)
	}
	var response struct {
		Values map[string]string `json:"values"`
	}
	if err = json.Unmarshal(output, &response); err != nil || len(response.Values) != 8 {
		t.Fatal("KDE configuration response is incomplete", err)
	}
	return response.Values
}

func TestLinuxKDEHostCaptureAndCrashRecovery(t *testing.T) {
	if os.Getenv("RAINLINK_TEST_KDE_PROXY") != "isolated" {
		t.Skip("requires a disposable KDE configuration, D-Bus and keyring")
	}
	requireCredentialStore(t)
	t.Setenv("XDG_CURRENT_DESKTOP", "KDE")
	path := filepath.Join(os.Getenv("XDG_CONFIG_HOME"), "kioslaverc")
	fixture := []byte("[Proxy Settings]\nProxyType=2\nhttpProxy=http://fixture-user:fixture-password@original.test:3128\nProxy Config Script=https://example.test/fixture.pac\nNoProxyFor=fixture.test\nReversedException=1\n\n[Other Settings]\nPreserve=original\n")
	if err := os.WriteFile(path, fixture, 0600); err != nil {
		t.Fatal(err)
	}
	readSettings := func(t *testing.T) []byte {
		encoded, err := json.Marshal(kdeProxySnapshot(t))
		if err != nil {
			t.Fatal(err)
		}
		return encoded
	}
	runLinuxCaptureScenarios(t, "KDE", readSettings, func(t *testing.T, snapshot Snapshot) {
		actual := kdeProxySnapshot(t)
		http := fmt.Sprintf("v:http://127.0.0.1:%d", snapshot.ProxyPort)
		if actual["/ProxyType"] != "v:1" || actual["/httpProxy"] != http || actual["/httpsProxy"] != http || actual["/ftpProxy"] != http || actual["/socksProxy"] != fmt.Sprintf("v:socks://127.0.0.1:%d", snapshot.ProxyPort) {
			t.Fatal("KDE system proxy did not use the actual core listener")
		}
	})
	output, err := exec.CommandContext(t.Context(), "/usr/bin/kreadconfig6", "--file", "kioslaverc", "--group", "Other Settings", "--key", "Preserve").Output()
	if err != nil || strings.TrimSpace(string(output)) != "original" {
		t.Fatal("host recovery lost unrelated KDE settings", err)
	}
}

func runLinuxCaptureScenarios(t *testing.T, desktop string, readSettings func(*testing.T) []byte, verifyCaptured func(*testing.T, Snapshot)) {
	t.Helper()
	baseline := readSettings(t)
	for _, scenario := range []string{"toggle-disconnect", "eof", "kill-host", "kill-core", "watcher-restart"} {
		t.Run(scenario, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(t.Context(), 30*time.Second)
			defer cancel()
			host := newLinuxTestHost(t, ctx, "serve")
			if failure := host.rpc("hello", map[string]any{}, nil); failure != nil {
				t.Fatal(failure)
			}
			node := chainProxyFixture(t, "linux-node", &chainRecorder{}, false)
			var snapshot Snapshot
			capture := scenario != "toggle-disconnect"
			if failure := host.rpc("connect", map[string]any{"node": node, "mode": "global", "systemProxy": capture}, &snapshot); failure != nil || snapshot.Phase != "connected" || snapshot.SystemProxy != capture {
				t.Fatalf("%s host did not connect: %v", desktop, failure)
			}
			if !capture {
				if actual := readSettings(t); !bytes.Equal(actual, baseline) {
					t.Fatal("local-only connection changed system settings")
				}
				if failure := host.rpc("capture", map[string]bool{"enabled": true}, nil); failure != nil {
					t.Fatal(failure)
				}
			}
			verifyCaptured(t, snapshot)
			origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { _, _ = io.WriteString(w, "linux-origin") }))
			defer origin.Close()
			proxy, _ := url.Parse(fmt.Sprintf("http://127.0.0.1:%d", snapshot.ProxyPort))
			if desktop == "KDE" {
				resolver := os.Getenv("RAINLINK_TEST_PROXY_RESOLVER")
				if resolver == "" {
					t.Fatal("independent libproxy resolver is required")
				}
				output, err := exec.CommandContext(t.Context(), resolver, "http://rainlink-origin.test").Output()
				if err != nil {
					t.Fatal("KDE consumer could not select the proxy", err)
				}
				resolved := strings.TrimSpace(string(output))
				if resolved != proxy.String() {
					t.Fatal("KDE consumer resolved a different core listener")
				}
				proxy, err = url.Parse(resolved)
				if err != nil {
					t.Fatal(err)
				}
			}
			client := &http.Client{Timeout: time.Second, Transport: &http.Transport{Proxy: http.ProxyURL(proxy), DisableKeepAlives: true}}
			defer client.CloseIdleConnections()
			response, err := client.Get(origin.URL)
			if err != nil {
				t.Fatal("actual desktop proxy listener did not transfer", err)
			}
			body, err := io.ReadAll(response.Body)
			_ = response.Body.Close()
			if err != nil || string(body) != "linux-origin" {
				t.Fatal("actual desktop proxy transfer failed", err)
			}
			if scenario == "toggle-disconnect" {
				otherDesktop := "GNOME"
				if desktop == "GNOME" {
					otherDesktop = "KDE"
				}
				t.Setenv("XDG_CURRENT_DESKTOP", otherDesktop)
				peer := newLinuxTestHost(t, ctx, "serve")
				if failure := peer.rpc("hello", map[string]any{}, nil); failure == nil || failure.Code != "proxy_recovery_failed" {
					t.Fatal("another live host stole the user-wide proxy lease")
				}
				peer.finish(true)
				t.Setenv("XDG_CURRENT_DESKTOP", desktop)
				probe := newLinuxTestHost(t, ctx, "serve-test")
				if failure := probe.rpc("hello", map[string]any{}, nil); failure != nil {
					t.Fatal("isolated probe interfered with the live lease", failure)
				}
				probe.finish(false)
				verifyCaptured(t, snapshot)
				if failure := host.rpc("capture", map[string]bool{"enabled": false}, nil); failure != nil {
					t.Fatal(failure)
				}
				if actual := readSettings(t); !bytes.Equal(actual, baseline) {
					t.Fatal("capture off did not restore the exact settings and unset keys")
				}
				if failure := host.rpc("capture", map[string]bool{"enabled": true}, nil); failure != nil {
					t.Fatal(failure)
				}
				if failure := host.rpc("disconnect", map[string]any{}, nil); failure != nil {
					t.Fatal(failure)
				}
			}
			if scenario == "watcher-restart" {
				watcher := hostChild(t, host.command.Process.Pid, "rainlink-host")
				if err := unix.Kill(watcher, unix.SIGKILL); err != nil {
					t.Fatal(err)
				}
				for _, enabled := range []bool{false, true} {
					if failure := host.rpc("capture", map[string]bool{"enabled": enabled}, nil); failure != nil {
						t.Fatal("watcher restart failed", failure)
					}
				}
				if replacement := hostChild(t, host.command.Process.Pid, "rainlink-host"); replacement == watcher {
					t.Fatal("dead watcher was reused")
				}
			}
			if scenario == "kill-core" {
				core := hostChild(t, host.command.Process.Pid, "sing-box")
				if err := unix.Kill(core, unix.SIGKILL); err != nil {
					t.Fatal(err)
				}
			} else {
				host.finish(scenario == "kill-host")
			}
			deadline := time.Now().Add(8 * time.Second)
			for {
				actual := readSettings(t)
				journal := filepath.Join(os.Getenv("XDG_STATE_HOME"), "RainLink", "system-proxy", "gnome-proxy-recovery.bin")
				_, journalErr := os.Stat(journal)
				if bytes.Equal(actual, baseline) && errors.Is(journalErr, os.ErrNotExist) {
					break
				}
				if time.Now().After(deadline) {
					t.Fatal("normal/crash cleanup did not restore the original settings and retire the lease")
				}
				time.Sleep(40 * time.Millisecond)
			}
			if scenario == "kill-core" {
				var stopped Snapshot
				if failure := host.rpc("snapshot", map[string]any{}, &stopped); failure != nil || stopped.Phase == "connected" {
					t.Fatalf("core exit was not published: %v", failure)
				}
				host.finish(false)
			}
			listener, err := net.Listen("tcp4", net.JoinHostPort("127.0.0.1", strconv.Itoa(snapshot.ProxyPort)))
			if err != nil {
				t.Fatal("core listener survived cleanup", err)
			}
			_ = listener.Close()
		})
	}
}
