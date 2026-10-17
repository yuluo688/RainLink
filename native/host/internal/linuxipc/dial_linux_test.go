//go:build linux && !android

package linuxipc

import (
	"context"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestIsolatedRootSocketRejectsLinkedWritableAndForeignPaths(t *testing.T) {
	requireRootIPCNs(t)
	directory, err := os.MkdirTemp("/run", "rainlink-socket-")
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
	if err = os.Chmod(path, 0666); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(t.Context(), time.Second)
	defer cancel()
	connection, peer, err := DialRootService(ctx, path)
	if err != nil {
		t.Fatal("trusted root socket rejected", err)
	}
	if peer.UID() != 0 || peer.Check() != nil {
		t.Fatal("root endpoint was not authenticated")
	}
	if err = connection.Close(); err != nil {
		t.Fatal(err)
	}
	if err = peer.Close(); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(directory, "link")
	if err = os.Symlink(path, link); err != nil {
		t.Fatal(err)
	}
	file := filepath.Join(directory, "regular")
	if err = os.WriteFile(file, []byte("not a socket"), 0600); err != nil {
		t.Fatal(err)
	}
	parentLink := filepath.Join(directory, "parent-link")
	if err = os.Symlink(directory, parentLink); err != nil {
		t.Fatal(err)
	}
	for _, invalid := range []string{link, file, directory, "relative", directory + "/../" + filepath.Base(directory) + "/service.sock", filepath.Join(parentLink, "service.sock")} {
		if connection, peer, err := DialRootService(ctx, invalid); err == nil {
			connection.Close()
			peer.Close()
			t.Fatal("unsafe socket path was trusted", invalid)
		}
	}
	for _, mutation := range []struct {
		name           string
		apply, restore func() error
	}{
		{"foreign socket", func() error { return os.Chown(path, 65534, 65534) }, func() error { return os.Chown(path, 0, 0) }},
		{"writable ancestor", func() error { return os.Chmod(directory, 0777) }, func() error { return os.Chmod(directory, 0700) }},
		{"foreign ancestor", func() error { return os.Chown(directory, 65534, 65534) }, func() error { return os.Chown(directory, 0, 0) }},
	} {
		t.Run(mutation.name, func(t *testing.T) {
			if err := mutation.apply(); err != nil {
				t.Fatal(err)
			}
			defer func() {
				if err := mutation.restore(); err != nil {
					t.Error(err)
				}
			}()
			if connection, peer, err := DialRootService(ctx, path); err == nil {
				connection.Close()
				peer.Close()
				t.Fatal("untrusted socket was accepted")
			}
		})
	}
	cancelled, stop := context.WithCancel(t.Context())
	stop()
	if _, _, err = DialRootService(cancelled, path); err != context.Canceled {
		t.Fatal("cancelled dial changed error category", err)
	}
}
