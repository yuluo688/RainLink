//go:build linux && !android

package linuxipc

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"

	"rainlink.local/host/internal/linuxprocess"
)

// This subprocess never receives real credentials or touches global services.
func TestIPCPeerChild(t *testing.T) {
	if os.Getenv("RAINLINK_IPC_TEST_CHILD") != "1" {
		return
	}
	connection, err := net.DialUnix("unix", nil, &net.UnixAddr{Name: os.Getenv("RAINLINK_IPC_TEST_SOCKET"), Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close()
	if os.Getenv("RAINLINK_IPC_TEST_ROOT_SERVICE") == "1" {
		peer, err := InspectRootService(connection)
		if err != nil {
			t.Fatal("ordinary client could not authenticate root service", err)
		}
		defer peer.Close()
		if err = peer.RequireRoot(); err != nil {
			t.Fatal(err)
		}
	}
	fmt.Println("connected")
	commands := bufio.NewScanner(os.Stdin)
	for commands.Scan() {
		switch commands.Text() {
		case "drop":
			if err = syscall.Setresgid(65534, 65534, 65534); err == nil {
				err = syscall.Setresuid(65534, 65534, 65534)
			}
			if err != nil {
				t.Fatal("fixture UID drop failed", err)
			}
			fmt.Println("dropped")
		case "exit":
			return
		default:
			t.Fatal("invalid fixture command")
		}
	}
	if err := commands.Err(); err != nil {
		t.Fatal(err)
	}
}

type peerFixture struct {
	connection *net.UnixConn
	child      *exec.Cmd
	input      io.WriteCloser
	output     *bufio.Reader
	reaped     bool
}

func startPeerFixture(t *testing.T, childUID *uint32, rootService bool) *peerFixture {
	t.Helper()
	directory, err := os.MkdirTemp("", "rainlink-ipc-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := os.RemoveAll(directory); err != nil {
			t.Error(err)
		}
	})
	if err = os.Chmod(directory, 0755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(directory, "peer.sock")
	listener, err := net.ListenUnix("unix", &net.UnixAddr{Name: path, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	if childUID != nil {
		if err = os.Chmod(path, 0666); err != nil {
			t.Fatal(err)
		}
	}
	if err = listener.SetDeadline(time.Now().Add(3 * time.Second)); err != nil {
		t.Fatal(err)
	}
	child := exec.Command(os.Args[0], "-test.run=^TestIPCPeerChild$", "-test.timeout=8s")
	child.Env = append(os.Environ(), "RAINLINK_IPC_TEST_CHILD=1", "RAINLINK_IPC_TEST_SOCKET="+path)
	if rootService {
		child.Env = append(child.Env, "RAINLINK_IPC_TEST_ROOT_SERVICE=1")
	}
	if childUID != nil {
		child.SysProcAttr = &syscall.SysProcAttr{Credential: &syscall.Credential{Uid: *childUID, Gid: *childUID}}
	}
	input, err := child.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	stdout, err := child.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	child.Stderr = os.Stderr
	if err = child.Start(); err != nil {
		t.Fatal(err)
	}
	fixture := &peerFixture{child: child, input: input, output: bufio.NewReader(stdout)}
	t.Cleanup(func() {
		_ = input.Close()
		if fixture.connection != nil {
			_ = fixture.connection.Close()
		}
		if !fixture.reaped {
			_ = child.Process.Kill()
			_ = child.Wait()
		}
	})
	fixture.connection, err = listener.AcceptUnix()
	if err != nil {
		t.Fatal(err)
	}
	fixture.expect(t, "connected")
	return fixture
}

func (fixture *peerFixture) expect(t *testing.T, want string) {
	t.Helper()
	line, err := fixture.output.ReadString('\n')
	if err != nil || strings.TrimSpace(line) != want {
		t.Fatal("peer fixture did not reach stage", want, line, err)
	}
}

func (fixture *peerFixture) exit(t *testing.T) {
	t.Helper()
	if _, err := io.WriteString(fixture.input, "exit\n"); err != nil {
		t.Fatal(err)
	}
	err := fixture.child.Wait()
	fixture.reaped = true
	if err != nil {
		t.Fatal(err)
	}
}

func TestPeerUsesKernelIdentityAndRevokesExitedCreator(t *testing.T) {
	fixture := startPeerFixture(t, nil, false)
	peer, err := Inspect(fixture.connection)
	if err != nil {
		t.Fatal(err)
	}
	defer peer.Close()
	if peer.UID() != uint32(os.Geteuid()) || peer.Identity().PID != fixture.child.Process.Pid {
		t.Fatal("kernel identity did not match the actual creator")
	}
	subject, err := peer.Subject()
	want := strconv.Itoa(fixture.child.Process.Pid) + "," + strconv.FormatUint(peer.Identity().Start, 10) + "," + strconv.Itoa(os.Geteuid())
	if err != nil || subject != want {
		t.Fatal("polkit subject lost start time or UID", err)
	}
	if os.Geteuid() != 0 {
		if err = peer.RequireRoot(); err == nil {
			t.Fatal("ordinary peer impersonated root")
		}
		if fake, err := InspectRootService(fixture.connection); err == nil {
			_ = fake.Close()
			t.Fatal("ordinary service impersonated root")
		}
	}
	ctx, cancel := context.WithTimeout(t.Context(), 15*time.Millisecond)
	err = peer.Wait(ctx)
	cancel()
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal("live peer wait ignored deadline", err)
	}
	fixture.exit(t)
	ctx, cancel = context.WithTimeout(t.Context(), time.Second)
	defer cancel()
	if err = peer.Wait(ctx); err != nil {
		t.Fatal("creator exit was not observed", err)
	}
	if err = peer.Check(); !errors.Is(err, linuxprocess.ErrNotAlive) {
		t.Fatal("exited creator remained authorized", err)
	}
	if other, err := Inspect(fixture.connection); err == nil {
		_ = other.Close()
		t.Fatal("socket with dead creator was accepted")
	}
	if err = peer.Close(); err != nil {
		t.Fatal(err)
	}
	if err = peer.Close(); err != nil {
		t.Fatal(err)
	}
	if err = peer.Check(); !errors.Is(err, os.ErrClosed) {
		t.Fatal("closed peer accepted", err)
	}
	if err = peer.Wait(t.Context()); !errors.Is(err, os.ErrClosed) {
		t.Fatal(err)
	}
}

func TestPeerRejectsMissingDatagramAndUninspectedEndpoints(t *testing.T) {
	if _, err := Inspect(nil); err == nil {
		t.Fatal("missing connection accepted")
	}
	if err := (*Peer)(nil).Check(); err == nil {
		t.Fatal("uninspected peer accepted")
	}
	if err := (*Peer)(nil).Wait(t.Context()); err == nil {
		t.Fatal("uninspected peer waited")
	}
	if err := (*Peer)(nil).Close(); err != nil {
		t.Fatal(err)
	}
	connection, err := net.ListenUnixgram("unixgram", &net.UnixAddr{Name: filepath.Join(t.TempDir(), "datagram"), Net: "unixgram"})
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close()
	if _, err = Inspect(connection); err == nil {
		t.Fatal("datagram endpoint accepted as permission stream")
	}
}

func TestIsolatedRootPeerCredentialsDropAndServiceAuthentication(t *testing.T) {
	if os.Geteuid() != 0 || os.Getenv("RAINLINK_TEST_ROOT_TUN_NAMESPACE") != "isolated" {
		t.Skip("requires disposable root namespace")
	}
	current, err := os.Readlink("/proc/self/ns/net")
	if err != nil || current == os.Getenv("RAINLINK_TEST_PARENT_NETNS") || os.Getenv("RAINLINK_TEST_PARENT_NETNS") == "" {
		t.Fatal("root credential fixture is not isolated", err)
	}
	t.Run("ordinary-client-authenticates-root-service", func(t *testing.T) {
		uid := uint32(65534)
		fixture := startPeerFixture(t, &uid, true)
		peer, err := Inspect(fixture.connection)
		if err != nil {
			t.Fatal(err)
		}
		defer peer.Close()
		if peer.UID() != uid {
			t.Fatal("payload could replace the kernel UID")
		}
		fixture.exit(t)
	})
	t.Run("connected-root-client-drops-all-uids", func(t *testing.T) {
		fixture := startPeerFixture(t, nil, false)
		peer, err := Inspect(fixture.connection)
		if err != nil {
			t.Fatal(err)
		}
		defer peer.Close()
		if err = peer.RequireRoot(); err != nil {
			t.Fatal(err)
		}
		if _, err = io.WriteString(fixture.input, "drop\n"); err != nil {
			t.Fatal(err)
		}
		fixture.expect(t, "dropped")
		if err = peer.Check(); !errors.Is(err, linuxprocess.ErrCredentialsChanged) {
			t.Fatal("static SO_PEERCRED authorized a process after dropping UID", err)
		}
		if _, err = peer.Subject(); err == nil {
			t.Fatal("changed UID retained an authorization subject")
		}
		fixture.exit(t)
	})
}
