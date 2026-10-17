//go:build linux && !android

package linuxipc

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"rainlink.local/host/internal/linuxprocess"
)

func requireRootIPCNs(t *testing.T) {
	t.Helper()
	if os.Geteuid() != 0 || os.Getenv("RAINLINK_TEST_ROOT_TUN_NAMESPACE") != "isolated" {
		t.Skip("requires disposable root namespace")
	}
	namespace, err := os.Readlink("/proc/self/ns/net")
	parent := os.Getenv("RAINLINK_TEST_PARENT_NETNS")
	if err != nil || parent == "" || namespace == parent {
		t.Fatal("root IPC fixture is not isolated", err)
	}
}

func TestIsolatedRootExecutableRejectsWritableLinkedAndForeignFiles(t *testing.T) {
	requireRootIPCNs(t)
	directory, err := os.MkdirTemp("/run", "rainlink-trust-")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(directory)
	path := filepath.Join(directory, "executable")
	if err = os.WriteFile(path, []byte("#!/bin/sh\nexit 0\n"), 0755); err != nil {
		t.Fatal(err)
	}
	file, err := OpenRootExecutable(path)
	if err != nil {
		t.Fatal("root-owned fixture was rejected", err)
	}
	if err = file.Close(); err != nil {
		t.Fatal(err)
	}
	for _, mode := range []os.FileMode{0775, 0777, 0644} {
		if err = os.Chmod(path, mode); err != nil {
			t.Fatal(err)
		}
		if file, err = OpenRootExecutable(path); err == nil {
			file.Close()
			t.Fatal("writable or nonexecutable file was trusted")
		}
	}
	if err = os.Chmod(path, 0755); err != nil {
		t.Fatal(err)
	}
	if err = os.Chown(path, 65534, 65534); err != nil {
		t.Fatal(err)
	}
	if file, err = OpenRootExecutable(path); err == nil {
		file.Close()
		t.Fatal("foreign-owned executable was trusted")
	}
	if err = os.Chown(path, 0, 0); err != nil {
		t.Fatal(err)
	}
	if err = os.Chmod(directory, 0777); err != nil {
		t.Fatal(err)
	}
	if file, err = OpenRootExecutable(path); err == nil {
		file.Close()
		t.Fatal("writable ancestor was trusted")
	}
	if err = os.Chmod(directory, 0700); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(directory, "link")
	if err = os.Symlink(path, link); err != nil {
		t.Fatal(err)
	}
	for _, invalid := range []string{link, "relative", directory + "/../" + filepath.Base(directory) + "/executable", directory} {
		if file, err = OpenRootExecutable(invalid); err == nil {
			file.Close()
			t.Fatal("unsafe executable path was trusted")
		}
	}
}

func TestIsolatedRootAuthorizationUsesFixedArgumentsAndRechecksUID(t *testing.T) {
	requireRootIPCNs(t)
	const path = "/usr/bin/pkcheck"
	if _, err := os.Lstat(path); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("fixture must not replace a real system authorizer", err)
	}
	directory, err := os.MkdirTemp("/run", "rainlink-auth-")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(directory)
	script := "#!/bin/sh\nset -eu\n" +
		"[ -z \"${RAINLINK_SHOULD_NOT_LEAK-}\" ] || exit 2\n" +
		"printf '%s\\n' \"$@\" > " + directory + "/arguments\n" +
		"mode=$(cat " + directory + "/mode)\n" +
		"if [ \"$mode\" = wait ]; then : > " + directory + "/entered; exec /bin/sleep 10; fi\n" +
		"if [ \"$mode\" = drop ]; then : > " + directory + "/entered; while [ ! -e " + directory + "/continue ]; do /bin/sleep 0.01; done; exit 0; fi\n" +
		"exit \"$mode\"\n"
	if err = os.WriteFile(path, []byte(script), 0755); err != nil {
		t.Fatal(err)
	}
	defer os.Remove(path)
	t.Setenv("RAINLINK_SHOULD_NOT_LEAK", "fixture-environment")
	fixture := startPeerFixture(t, nil, false)
	peer, err := Inspect(fixture.connection)
	if err != nil {
		t.Fatal(err)
	}
	defer peer.Close()
	subject, err := peer.Subject()
	if err != nil {
		t.Fatal(err)
	}
	setMode := func(mode string) {
		t.Helper()
		if err := os.WriteFile(filepath.Join(directory, "mode"), []byte(mode), 0600); err != nil {
			t.Fatal(err)
		}
	}
	for _, trial := range []struct {
		mode     string
		expected error
	}{{"0", nil}, {"1", ErrPermissionDenied}, {"126", ErrPermissionDenied}, {"127", ErrAuthorizationUnavailable}, {"2", ErrAuthorizationUnavailable}} {
		setMode(trial.mode)
		err = AuthorizeTUN(t.Context(), peer)
		if !errors.Is(err, trial.expected) {
			t.Fatal("authorization result lost its category", trial.mode, err)
		}
	}
	arguments, err := os.ReadFile(filepath.Join(directory, "arguments"))
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(strings.Split(strings.TrimSpace(string(arguments)), "\n"), []string{"--action-id", TUNAction, "--process", subject, "--allow-user-interaction"}) {
		t.Fatal("authorization action or start-time-bound subject changed")
	}
	setMode("wait")
	ctx, cancel := context.WithTimeout(t.Context(), 500*time.Millisecond)
	err = AuthorizeTUN(ctx, peer)
	cancel()
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal("authorization did not cancel its child", err)
	}
	if err = os.Remove(filepath.Join(directory, "entered")); err != nil {
		t.Fatal("cancellation fixture never reached the authorizer", err)
	}
	setMode("drop")
	done := make(chan error, 1)
	go func() { done <- AuthorizeTUN(t.Context(), peer) }()
	deadline := time.Now().Add(time.Second)
	for {
		if _, err = os.Stat(filepath.Join(directory, "entered")); err == nil {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("authorization fixture did not start")
		}
		time.Sleep(5 * time.Millisecond)
	}
	if _, err = fixture.input.Write([]byte("drop\n")); err != nil {
		t.Fatal(err)
	}
	fixture.expect(t, "dropped")
	if err = os.WriteFile(filepath.Join(directory, "continue"), nil, 0600); err != nil {
		t.Fatal(err)
	}
	if err = <-done; !errors.Is(err, linuxprocess.ErrCredentialsChanged) {
		t.Fatal("approval accepted a changed UID", err)
	}
	fixture.exit(t)
}
