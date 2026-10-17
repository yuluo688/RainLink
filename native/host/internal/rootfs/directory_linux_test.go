//go:build linux && !android

package rootfs

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"golang.org/x/sys/unix"
)

func rootDirectory(t *testing.T) string {
	t.Helper()
	if os.Geteuid() != 0 {
		t.Skip("requires disposable root fixture")
	}
	path, err := os.MkdirTemp("/run", "rainlink-rootfs-test-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := os.RemoveAll(path); err != nil {
			t.Error(err)
		}
	})
	return path
}

func TestRootDirectoryRefusesLinksWritableAncestorsAndForeignOwners(t *testing.T) {
	root := rootDirectory(t)
	path := filepath.Join(root, "public", "private")
	directory, err := Open(path, true, 0700)
	if err != nil {
		t.Fatal(err)
	}
	if err = directory.Close(); err != nil {
		t.Fatal(err)
	}
	if err = os.Symlink(filepath.Join(root, "public"), filepath.Join(root, "redirect")); err != nil {
		t.Fatal(err)
	}
	if d, err := Open(filepath.Join(root, "redirect", "private"), false, 0700); err == nil {
		_ = d.Close()
		t.Fatal("followed directory symlink")
	}
	for _, mode := range []os.FileMode{0775, 0777} {
		if err = os.Chmod(filepath.Join(root, "public"), mode); err != nil {
			t.Fatal(err)
		}
		if d, err := Open(path, false, 0700); err == nil {
			_ = d.Close()
			t.Fatal("accepted writable ancestor")
		}
	}
	if err = os.Chmod(filepath.Join(root, "public"), 0755); err != nil {
		t.Fatal(err)
	}
	if err = os.Chown(filepath.Join(root, "public"), 65534, 65534); err != nil {
		t.Fatal(err)
	}
	if d, err := Open(path, false, 0700); err == nil {
		_ = d.Close()
		t.Fatal("accepted foreign owner")
	}
}

func TestRootFilesAtomicReplaceLimitsAndPinnedDirectory(t *testing.T) {
	root := rootDirectory(t)
	path := filepath.Join(root, "pinned")
	directory, err := Open(path, true, 0755)
	if err != nil {
		t.Fatal(err)
	}
	defer directory.Close()
	if err = directory.Replace(t.Context(), "managed", strings.NewReader("previous"), 16, 0755); err != nil {
		t.Fatal(err)
	}
	if err = directory.Replace(t.Context(), "managed", strings.NewReader(strings.Repeat("x", 17)), 16, 0755); err == nil {
		t.Fatal("unbounded source accepted")
	}
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	if err = directory.Replace(ctx, "managed", strings.NewReader("cancelled"), 16, 0755); !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(path, "managed"))
	if err != nil || string(data) != "previous" {
		t.Fatal("failed write changed destination", err)
	}
	if err = os.Rename(path, path+"-original"); err != nil {
		t.Fatal(err)
	}
	if err = os.Mkdir(path, 0755); err != nil {
		t.Fatal(err)
	}
	if err = directory.Replace(t.Context(), "managed", strings.NewReader("updated"), 16, 0755); err != nil {
		t.Fatal(err)
	}
	if _, err = os.Stat(filepath.Join(path, "managed")); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("reopened mutable directory path", err)
	}
	data, err = os.ReadFile(filepath.Join(path+"-original", "managed"))
	if err != nil || string(data) != "updated" {
		t.Fatal(err)
	}
	file, err := directory.OpenFile("managed")
	if err != nil {
		t.Fatal(err)
	}
	digest, err := Inspect(t.Context(), file, 16)
	_ = file.Close()
	if err != nil || digest.Size != 7 || digest.Mode != 0755 || len(digest.SHA256) != 64 {
		t.Fatal(digest, err)
	}
	if err = directory.Remove("managed"); err != nil {
		t.Fatal(err)
	}
	if err = directory.Remove("managed"); err != nil {
		t.Fatal(err)
	}
}

func TestRootFilesRefuseSymlinkHardlinkSpecialAndUnsafeMode(t *testing.T) {
	path := rootDirectory(t)
	directory, err := Open(path, false, 0700)
	if err != nil {
		t.Fatal(err)
	}
	defer directory.Close()
	if err = os.WriteFile(filepath.Join(path, "original"), []byte("preserve"), 0600); err != nil {
		t.Fatal(err)
	}
	if err = os.Symlink("original", filepath.Join(path, "symlink")); err != nil {
		t.Fatal(err)
	}
	if err = os.Link(filepath.Join(path, "original"), filepath.Join(path, "hardlink")); err != nil {
		t.Fatal(err)
	}
	if err = unix.Mkfifo(filepath.Join(path, "fifo"), 0600); err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(filepath.Join(path, "writable"), []byte("preserve"), 0600); err != nil {
		t.Fatal(err)
	}
	if err = os.Chmod(filepath.Join(path, "writable"), 0666); err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(filepath.Join(path, "setuid"), []byte("preserve"), 0600); err != nil {
		t.Fatal(err)
	}
	if err = os.Chmod(filepath.Join(path, "setuid"), 0755|os.ModeSetuid); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"../outside", "symlink", "hardlink", "fifo", "writable", "setuid"} {
		if f, err := directory.OpenFile(name); err == nil {
			_ = f.Close()
			t.Fatal("unsafe file opened", name)
		}
		if err = directory.Remove(name); err == nil {
			t.Fatal("unsafe file removed", name)
		}
		if err = directory.Replace(t.Context(), name, strings.NewReader("replace"), 32, 0644); err == nil {
			t.Fatal("unsafe file replaced", name)
		}
	}
	data, err := os.ReadFile(filepath.Join(path, "original"))
	if err != nil || string(data) != "preserve" {
		t.Fatal(err)
	}
}
