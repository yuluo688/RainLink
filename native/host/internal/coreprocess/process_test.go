package coreprocess

import (
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"testing"
)

func TestCancelledStartCannotLaunchEvenPrivilegedCore(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	for _, tun := range []bool{false, true} {
		process, err := Start(ctx, "must-not-launch.exe", nil, io.Discard, io.Discard, tun)
		if process != nil || !errors.Is(err, context.Canceled) {
			t.Fatal("cancelled operation attempted launch", tun, err)
		}
	}
}

func TestUntrustedCoreCannotAdvertiseTUNCapability(t *testing.T) {
	path := filepath.Join(t.TempDir(), "sing-box.exe")
	if Trusted(path) {
		t.Fatal("missing core trusted")
	}
	if err := os.WriteFile(path, []byte("not the locked network core"), 0600); err != nil {
		t.Fatal(err)
	}
	if Trusted(path) {
		t.Fatal("unrecognized executable trusted for elevation")
	}
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	if TrustedFile(file) || TrustedFile(nil) {
		t.Fatal("unrecognized file descriptor was trusted")
	}
	if err = file.Close(); err != nil {
		t.Fatal(err)
	}
	if TrustedFile(file) {
		t.Fatal("closed executable descriptor was trusted")
	}
}

func TestLockedCoreMatchesCurrentPlatform(t *testing.T) {
	path := os.Getenv("RAINLINK_TEST_CORE_PATH")
	if path == "" {
		t.Skip("set RAINLINK_TEST_CORE_PATH to verify the real platform-specific locked binary")
	}
	if !Trusted(path) {
		t.Fatal("bundled core does not match this platform's locked SHA256")
	}
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	if _, err = file.Seek(10, io.SeekStart); err != nil {
		t.Fatal(err)
	}
	if !TrustedFile(file) {
		t.Fatal("locked executable descriptor was rejected")
	}
	if offset, err := file.Seek(0, io.SeekCurrent); err != nil || offset != 0 {
		t.Fatal("hashing did not reset the inherited file offset", err)
	}
}
