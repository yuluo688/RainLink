//go:build linux && !android

package securestore

import (
	"bytes"
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	"golang.org/x/sys/unix"
)

func testKeyService(t *testing.T, run secretCommand) *linuxKeyService {
	t.Helper()
	dir := filepath.Join(t.TempDir(), "keys")
	return &linuxKeyService{run: run, directory: func() (string, error) { return dir, nil }}
}

func TestLinuxKeyCreationSerialized(t *testing.T) {
	var saved []byte
	stores := 0
	var serviceMu sync.Mutex
	service := testKeyService(t, func(_ context.Context, path string, args []string, input []byte) ([]byte, bool, error) {
		serviceMu.Lock()
		defer serviceMu.Unlock()
		if path != secretToolPath {
			t.Error("untrusted command path")
		}
		attributes := []string{"application", "dev.rainlink.RainLink", "purpose", "credential-master-v1"}
		if args[0] == "search" {
			if !reflect.DeepEqual(args, append([]string{"search", "--all"}, attributes...)) || len(input) != 0 || len(saved) != 0 {
				t.Error("invalid absence confirmation")
			}
			return nil, false, nil
		}
		if args[0] == "lookup" {
			if !reflect.DeepEqual(args[1:], attributes) || len(input) != 0 {
				t.Error("invalid lookup attributes")
			}
			return bytes.Clone(saved), len(saved) == 0, nil
		}
		if !reflect.DeepEqual(args, append([]string{"store", "--label=RainLink credential key"}, attributes...)) {
			t.Error("secret found in arguments or invalid store attributes")
		}
		decoded, err := base64.StdEncoding.DecodeString(string(input))
		if err != nil || len(decoded) != keyBytes {
			t.Errorf("invalid stdin key: %v", err)
		}
		saved = bytes.Clone(input)
		stores++
		return nil, false, nil
	})
	const count = 12
	keys := make(chan []byte, count)
	errorsCh := make(chan error, count)
	var workers sync.WaitGroup
	for range count {
		workers.Go(func() {
			key, err := service.Key(t.Context(), true)
			if err != nil {
				errorsCh <- err
				return
			}
			keys <- key
		})
	}
	workers.Wait()
	close(keys)
	close(errorsCh)
	for err := range errorsCh {
		t.Error(err)
	}
	if len(keys) != count || stores != 1 {
		t.Fatalf("creation was not serialized: keys=%d stores=%d", len(keys), stores)
	}
	expected, err := base64.StdEncoding.DecodeString(string(saved))
	if err != nil {
		t.Fatal(err)
	}
	for key := range keys {
		if !bytes.Equal(key, expected) {
			t.Error("concurrent clients received different keys")
		}
	}
}

func TestLinuxKeyFailures(t *testing.T) {
	for _, scenario := range []string{"missing", "locked", "locked-silent", "search-failed", "malformed", "wrong-length", "store-failed", "store-missing", "readback-missing", "readback-different", "cancelled"} {
		t.Run(scenario, func(t *testing.T) {
			lookups, stores := 0, 0
			service := testKeyService(t, func(ctx context.Context, _ string, args []string, _ []byte) ([]byte, bool, error) {
				if args[0] == "search" {
					if scenario == "locked-silent" {
						return []byte("[/locked/item]\nlabel = RainLink credential key"), false, nil
					}
					if scenario == "search-failed" {
						return nil, false, errors.New("search service failed")
					}
					return nil, false, nil
				}
				if args[0] == "store" {
					stores++
					if scenario == "store-failed" {
						return nil, false, errors.New("service locked")
					}
					return nil, scenario == "store-missing", nil
				}
				lookups++
				switch scenario {
				case "locked":
					return nil, false, errors.New("keyring is locked")
				case "malformed":
					return []byte("invalid!"), false, nil
				case "wrong-length":
					return []byte(base64.StdEncoding.EncodeToString([]byte{1})), false, nil
				case "readback-different":
					if lookups > 1 {
						return []byte(base64.StdEncoding.EncodeToString(make([]byte, 32))), false, nil
					}
				case "cancelled":
					<-ctx.Done()
					return nil, false, ctx.Err()
				}
				return nil, true, nil
			})
			ctx, cancel := context.WithTimeout(t.Context(), 80*time.Millisecond)
			defer cancel()
			_, err := service.Key(ctx, scenario != "missing")
			expected := ErrUnavailable
			if scenario == "missing" {
				expected = ErrMissingKey
			}
			if !errors.Is(err, expected) {
				t.Fatalf("wrong failure: %v", err)
			}
			if scenario == "cancelled" && !errors.Is(err, context.DeadlineExceeded) {
				t.Fatal("lost deadline")
			}
			if scenario == "missing" && stores != 0 {
				t.Fatal("reading a missing key created a replacement")
			}
			if (scenario == "locked-silent" || scenario == "search-failed") && stores != 0 {
				t.Fatal("unreadable existing key was replaced")
			}
		})
	}
}

func TestLinuxKeyLockSecurityAndCancellation(t *testing.T) {
	for _, scenario := range []string{"public-directory", "directory-symlink", "file-symlink", "public-file", "hard-link", "fifo", "cancelled"} {
		t.Run(scenario, func(t *testing.T) {
			root := t.TempDir()
			dir := filepath.Join(root, "keys")
			if err := os.Mkdir(dir, 0700); err != nil {
				t.Fatal(err)
			}
			file := filepath.Join(dir, "credential-key.lock")
			switch scenario {
			case "public-directory":
				if err := os.Chmod(dir, 0755); err != nil {
					t.Fatal(err)
				}
			case "directory-symlink":
				dir = filepath.Join(root, "linked")
				if err := os.Symlink(filepath.Join(root, "keys"), dir); err != nil {
					t.Fatal(err)
				}
			case "file-symlink":
				if err := os.Symlink(filepath.Join(root, "outside"), file); err != nil {
					t.Fatal(err)
				}
			case "public-file":
				if err := os.WriteFile(file, nil, 0644); err != nil {
					t.Fatal(err)
				}
			case "hard-link":
				outside := filepath.Join(root, "outside")
				if err := os.WriteFile(outside, nil, 0600); err != nil {
					t.Fatal(err)
				}
				if err := os.Link(outside, file); err != nil {
					t.Fatal(err)
				}
			case "fifo":
				if err := unix.Mkfifo(file, 0600); err != nil {
					t.Fatal(err)
				}
			case "cancelled":
				release, err := acquireKeyLock(t.Context(), dir)
				if err != nil {
					t.Fatal(err)
				}
				defer func() {
					if err := release(); err != nil {
						t.Error(err)
					}
				}()
			}
			ctx, cancel := context.WithTimeout(t.Context(), 80*time.Millisecond)
			defer cancel()
			release, err := acquireKeyLock(ctx, dir)
			if err == nil {
				_ = release()
				t.Fatal("unsafe or blocked key lock accepted")
			}
			if scenario == "cancelled" && !errors.Is(err, context.DeadlineExceeded) {
				t.Fatalf("lost lock cancellation: %v", err)
			}
		})
	}
}

func TestKeyLockDirectory(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", "/tmp/rainlink-state-fixture")
	dir, err := keyLockDirectory()
	if err != nil || dir != "/tmp/rainlink-state-fixture/RainLink/keys" {
		t.Fatalf("XDG directory: %s %v", dir, err)
	}
	t.Setenv("XDG_STATE_HOME", "relative")
	if _, err := keyLockDirectory(); err == nil {
		t.Fatal("relative XDG directory accepted")
	}
	t.Setenv("XDG_STATE_HOME", "")
	t.Setenv("HOME", "/tmp/rainlink-home-fixture")
	dir, err = keyLockDirectory()
	if err != nil || dir != "/tmp/rainlink-home-fixture/.local/state/RainLink/keys" {
		t.Fatalf("home directory: %s %v", dir, err)
	}
}

func TestKeyLockAcrossProcesses(t *testing.T) {
	if directory := os.Getenv("RAINLINK_KEY_LOCK_HELPER"); directory != "" {
		ctx, cancel := context.WithTimeout(t.Context(), 100*time.Millisecond)
		defer cancel()
		release, err := acquireKeyLock(ctx, directory)
		if release != nil {
			_ = release()
		}
		if !errors.Is(err, context.DeadlineExceeded) {
			t.Fatalf("cross-process lock was not held: %v", err)
		}
		return
	}
	directory := filepath.Join(t.TempDir(), "keys")
	release, err := acquireKeyLock(t.Context(), directory)
	if err != nil {
		t.Fatal(err)
	}
	defer func() {
		if err := release(); err != nil {
			t.Error(err)
		}
	}()
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	command := exec.CommandContext(t.Context(), executable, "-test.run=^TestKeyLockAcrossProcesses$", "-test.timeout=5s")
	command.Env = append(os.Environ(), "RAINLINK_KEY_LOCK_HELPER="+directory)
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("lock subprocess: %v %s", err, output)
	}
}

func TestBoundedOutputReaderFromCannotBypassLimit(t *testing.T) {
	output := &boundedOutput{limit: 8}
	if _, err := io.Copy(output, strings.NewReader(strings.Repeat("x", 64<<10))); err == nil || !output.overflow || output.buffer.Len() > output.limit {
		t.Fatal("io.Copy bypassed bounded writer")
	}
}

func TestRunSecretCommand(t *testing.T) {
	// Real subprocesses exercise exec's copy goroutines, pipe limits and killing.
	for _, test := range []struct {
		name, script, verb string
		missing, fail      bool
	}{
		{"stdin-only", "[ \"$#\" -eq 1 ] || exit 7; cat", "lookup", false, false},
		{"missing", "exit 1", "lookup", true, false},
		{"failed-store", "exit 1", "store", false, true},
		{"locked", "echo 'private diagnostic' >&2; exit 1", "lookup", false, true},
		{"stdout-limit", "head -c 65536 /dev/zero", "lookup", false, true},
		{"stderr-limit", "head -c 65536 /dev/zero >&2", "lookup", false, true},
		{"timeout", "exec sleep 10", "lookup", false, true},
	} {
		t.Run(test.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "service")
			if err := os.WriteFile(path, []byte("#!/bin/sh\n"+test.script+"\n"), 0700); err != nil {
				t.Fatal(err)
			}
			ctx, cancel := context.WithTimeout(t.Context(), 250*time.Millisecond)
			defer cancel()
			output, missing, err := runSecretCommand(ctx, path, []string{test.verb}, []byte("stdin-fixture-key"))
			if (err != nil) != test.fail || missing != test.missing {
				t.Fatalf("missing=%v error=%v", missing, err)
			}
			if err != nil && strings.Contains(err.Error(), "private diagnostic") {
				t.Fatal("private diagnostic exposed")
			}
			if test.name == "stdin-only" && string(output) != "stdin-fixture-key" {
				t.Fatal("key not delivered via stdin")
			}
			if test.name == "timeout" && !errors.Is(err, context.DeadlineExceeded) {
				t.Fatalf("deadline lost: %v", err)
			}
		})
	}
	if _, missing, err := runSecretCommand(t.Context(), filepath.Join(t.TempDir(), "absent-service"), []string{"lookup"}, nil); err == nil || missing {
		t.Fatal("missing executable treated as missing key")
	}
}

func TestLinuxSecretServiceIntegration(t *testing.T) {
	if os.Getenv("RAINLINK_TEST_SECRET_SERVICE") != "isolated" {
		t.Skip("requires a disposable, unlocked Secret Service and isolated HOME/XDG_STATE_HOME")
	}
	store := NewLinuxStore()
	var previous string
	for i := range 2 {
		record, err := store.Seal(t.Context(), []byte("disposable-fixture-password"), "keyring-fixture")
		if err != nil {
			t.Fatal(err)
		}
		if record == previous {
			t.Fatal("reused nonce")
		}
		plain, err := store.Unseal(t.Context(), record, "keyring-fixture")
		if err != nil || string(plain) != "disposable-fixture-password" {
			t.Fatalf("real keyring roundtrip %d: %v", i, err)
		}
		previous = record
	}
	if _, _, err := runSecretCommand(t.Context(), secretToolPath, []string{"clear", "application", "dev.rainlink.RainLink", "purpose", "credential-master-v1"}, nil); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Unseal(t.Context(), previous, "keyring-fixture"); !errors.Is(err, ErrMissingKey) {
		t.Fatalf("lost real key was recreated on read: %v", err)
	}
	if _, missing, err := runSecretCommand(t.Context(), secretToolPath, []string{"lookup", "application", "dev.rainlink.RainLink", "purpose", "credential-master-v1"}, nil); err != nil || !missing {
		t.Fatalf("read changed missing key: missing=%v error=%v", missing, err)
	}
	if _, err := store.Seal(t.Context(), []byte("replacement-fixture"), "keyring-fixture"); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Unseal(t.Context(), previous, "keyring-fixture"); !errors.Is(err, ErrInvalidRecord) {
		t.Fatalf("old record accepted after a new key was created: %v", err)
	}
	fmt.Println("isolated Secret Service roundtrip passed")
}

func TestLinuxLockedSecretService(t *testing.T) {
	if os.Getenv("RAINLINK_TEST_SECRET_SERVICE_LOCKED") != "isolated" {
		t.Skip("run only after explicitly locking a disposable Secret Service")
	}
	for _, create := range []bool{false, true} {
		ctx, cancel := context.WithTimeout(t.Context(), 2*time.Second)
		key, err := NewLinuxStore().Keys.Key(ctx, create)
		cancel()
		clear(key)
		if !errors.Is(err, ErrUnavailable) && !errors.Is(err, context.DeadlineExceeded) {
			t.Fatalf("locked keyring was treated as absent or usable (create=%v): %v", create, err)
		}
	}
}
