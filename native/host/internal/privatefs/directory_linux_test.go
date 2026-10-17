//go:build linux && !android

package privatefs

import (
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"golang.org/x/sys/unix"
)

func openFixture(t *testing.T) (*Directory, string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "private")
	dir, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := dir.Close(); err != nil {
			t.Error(err)
		}
	})
	return dir, path
}

func TestDurableWriteExclusiveReplacementAndLimit(t *testing.T) {
	dir, path := openFixture(t)
	if err := dir.Write("record", []byte("before"), true); err != nil {
		t.Fatal(err)
	}
	if err := dir.Write("record", []byte("must-not-replace"), true); !errors.Is(err, os.ErrExist) {
		t.Fatal("exclusive write replaced an existing journal", err)
	}
	data, err := dir.Read("record", 6)
	if err != nil || string(data) != "before" {
		t.Fatalf("exclusive write damaged existing journal: %v", err)
	}
	if data, err = dir.Read("record", 5); err == nil || data != nil {
		t.Fatal("oversize read returned data")
	}
	if err = dir.Write("record", bytes.Repeat([]byte("x"), 8192), false); err != nil {
		t.Fatal(err)
	}
	data, err = dir.Read("record", 8192)
	if err != nil || len(data) != 8192 {
		t.Fatalf("replacement was not installed whole: %v", err)
	}
	entries, err := os.ReadDir(path)
	if err != nil || len(entries) != 1 || entries[0].Name() != "record" {
		t.Fatalf("temporary files were not retired: %v", err)
	}
	info, err := os.Stat(filepath.Join(path, "record"))
	if err != nil || info.Mode().Perm() != 0600 {
		t.Fatalf("unsafe file permissions: %v", err)
	}
	if err = dir.Remove("record"); err != nil {
		t.Fatal(err)
	}
	if _, err = dir.Read("record", 8); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("removed record can still be read", err)
	}
}

func TestUnsafeFilesAreRejectedWithoutFollowingLinks(t *testing.T) {
	for _, kind := range []string{"symlink", "hardlink", "public", "fifo"} {
		t.Run(kind, func(t *testing.T) {
			dir, path := openFixture(t)
			outside := filepath.Join(t.TempDir(), "outside")
			if err := os.WriteFile(outside, []byte("keep"), 0600); err != nil {
				t.Fatal(err)
			}
			file := filepath.Join(path, "record")
			var err error
			switch kind {
			case "symlink":
				err = os.Symlink(outside, file)
			case "hardlink":
				err = os.Link(outside, file)
			case "public":
				err = os.WriteFile(file, []byte("public"), 0600)
				if err == nil {
					err = os.Chmod(file, 0644)
				}
			case "fifo":
				err = unix.Mkfifo(file, 0600)
			}
			if err != nil {
				t.Fatal(err)
			}
			if _, err = dir.Read("record", 20); err == nil {
				t.Fatal("unsafe read accepted")
			}
			if release, err := dir.Lock(t.Context(), "record"); err == nil {
				_ = release()
				t.Fatal("unsafe lock accepted")
			}
			if err = dir.Write("record", []byte("no"), true); err == nil {
				t.Fatal("exclusive write replaced unsafe entry")
			}
			if err = dir.Write("record", []byte("safe replacement"), false); err != nil {
				t.Fatal(err)
			}
			data, err := os.ReadFile(outside)
			if err != nil || string(data) != "keep" {
				t.Fatalf("replacement followed a link: %v", err)
			}
		})
	}
}

func TestDirectoryPermissionsNamesAndDescriptorAnchor(t *testing.T) {
	dir, path := openFixture(t)
	for _, name := range []string{"", ".", "..", "../outside", "/absolute", "zero\x00byte"} {
		if err := dir.Write(name, []byte("x"), false); err == nil {
			t.Fatalf("invalid name accepted: %q", name)
		}
	}
	if _, err := Open("relative"); err == nil {
		t.Fatal("relative directory accepted")
	}
	if err := os.Chmod(path, 0755); err != nil {
		t.Fatal(err)
	}
	if other, err := Open(path); err == nil {
		_ = other.Close()
		t.Fatal("nonprivate directory accepted")
	}
	if err := os.Chmod(path, 0700); err != nil {
		t.Fatal(err)
	}
	moved := path + "-moved"
	if err := os.Rename(path, moved); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(t.TempDir(), path); err != nil {
		t.Fatal(err)
	}
	if other, err := Open(path); err == nil {
		_ = other.Close()
		t.Fatal("symlink directory accepted")
	}
	if err := dir.Write("anchored", []byte("safe"), true); err != nil {
		t.Fatal(err)
	}
	if data, err := os.ReadFile(filepath.Join(moved, "anchored")); err != nil || string(data) != "safe" {
		t.Fatalf("operation was not anchored to its descriptor: %v", err)
	}
}

func TestLockWaitCancellationAndRelease(t *testing.T) {
	dir, path := openFixture(t)
	other, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer other.Close()
	release, err := dir.Lock(t.Context(), "lease")
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(t.Context(), 60*time.Millisecond)
	defer cancel()
	if unexpected, err := other.Lock(ctx, "lease"); !errors.Is(err, context.DeadlineExceeded) {
		if unexpected != nil {
			_ = unexpected()
		}
		t.Fatalf("contended lock did not honor cancellation: %v", err)
	}
	if err = release(); err != nil {
		t.Fatal(err)
	}
	release, err = other.Lock(t.Context(), "lease")
	if err != nil {
		t.Fatal(err)
	}
	if err = release(); err != nil {
		t.Fatal(err)
	}
}
