//go:build linux && !android

package linuxproxy

import (
	"bytes"
	"context"
	"errors"
	"maps"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"rainlink.local/host/internal/privatefs"
	"rainlink.local/host/internal/securestore"
)

type testKeys struct{}

func (testKeys) Key(context.Context, bool) ([]byte, error) {
	return bytes.Repeat([]byte{0x73}, 32), nil
}

type lockableKeys struct{ locked bool }

func (k *lockableKeys) Key(ctx context.Context, create bool) ([]byte, error) {
	if k.locked {
		return nil, securestore.ErrUnavailable
	}
	return (testKeys{}).Key(ctx, create)
}

type fakeBackend struct {
	data      values
	available bool
	writes    int
	write     func(context.Context, values) error
	snapshot  func(context.Context) (values, error)
}

func (*fakeBackend) ID() string               { return "gnome" }
func (*fakeBackend) Settings() []setting      { return settings }
func (*fakeBackend) Owned(port int) values    { return ownedValues(port) }
func (*fakeBackend) Binding() (string, error) { return strings.Repeat("a", 64), nil }

func (f *fakeBackend) Available(ctx context.Context) bool { return ctx.Err() == nil && f.available }
func (f *fakeBackend) Snapshot(ctx context.Context) (values, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if f.snapshot != nil {
		return f.snapshot(ctx)
	}
	return maps.Clone(f.data), nil
}
func (f *fakeBackend) Write(ctx context.Context, v values) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	f.writes++
	if f.write != nil {
		return f.write(ctx, v)
	}
	f.data = maps.Clone(v)
	return nil
}

func fixture(t *testing.T) (*Controller, *fakeBackend, values) {
	t.Helper()
	before := ownedValues(3128)
	before["/mode"] = "'auto'"
	before["/autoconfig-url"] = "'https://example.test/proxy.pac?fixture-secret'"
	before["http/use-authentication"] = "true"
	before["http/authentication-user"] = "'fixture-user'"
	before["http/authentication-password"] = "'fixture-secret'"
	fake := &fakeBackend{data: maps.Clone(before), available: true}
	return &Controller{directory: filepath.Join(t.TempDir(), "proxy"), backend: fake, store: securestore.Store{Keys: testKeys{}}}, fake, before
}

func TestProxyApplyEncryptedJournalAndRestore(t *testing.T) {
	c, fake, before := fixture(t)
	if err := c.Apply(t.Context(), 7891); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(fake.data, ownedValues(7891)) {
		t.Fatal("proxy settings were not committed")
	}
	data, err := os.ReadFile(filepath.Join(c.directory, journalName))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.HasPrefix(data, []byte("rls1.")) || bytes.Contains(data, []byte("fixture-secret")) {
		t.Fatal("recovery journal contains plaintext credentials")
	}
	if err = c.Restore(t.Context()); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(fake.data, before) {
		t.Fatal("original proxy values were not restored")
	}
	if _, err = os.Stat(filepath.Join(c.directory, journalName)); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("completed recovery journal not retired: %v", err)
	}
	if err = c.Restore(t.Context()); err != nil {
		t.Fatal("restore is not idempotent", err)
	}
}

func TestProxyRejectsOversizedRecoveryBeforeChangingSettings(t *testing.T) {
	c, fake, before := fixture(t)
	before["http/authentication-password"] = strings.Repeat("\\", maxSettingBytes)
	fake.data = maps.Clone(before)
	if err := c.Apply(t.Context(), 7891); err == nil {
		t.Fatal("proxy captured without capacity for its complete restoration")
	}
	if fake.writes != 0 || !reflect.DeepEqual(fake.data, before) {
		t.Fatal("oversized recovery changed the user's settings")
	}
	if _, err := os.Stat(filepath.Join(c.directory, journalName)); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("oversized recovery created a lease", err)
	}
}

func TestProxyRecoveryRespectsLaterOwnersAndBypassEdits(t *testing.T) {
	for _, change := range []string{"bypass-only", "new-client", "crash-before-write", "partial-apply"} {
		t.Run(change, func(t *testing.T) {
			c, fake, before := fixture(t)
			if err := c.Apply(t.Context(), 7891); err != nil {
				t.Fatal(err)
			}
			if change == "crash-before-write" || change == "partial-apply" {
				if err := c.withLock(t.Context(), func(dir *privatefs.Directory) error {
					record, err := c.read(t.Context(), dir)
					if err != nil {
						return err
					}
					record.Applied = false
					return c.write(t.Context(), dir, record, false)
				}); err != nil {
					t.Fatal(err)
				}
				fake.data = maps.Clone(before)
				if change == "partial-apply" {
					fake.data["http/host"] = "'127.0.0.1'"
					fake.data["http/port"] = "7891"
				}
			}
			if change == "bypass-only" {
				fake.data["/ignore-hosts"] = "['example.test']"
			}
			if change == "new-client" {
				fake.data = ownedValues(9988)
				fake.data["http/host"] = "'other-client.test'"
			}
			expected := maps.Clone(before)
			if change == "bypass-only" {
				expected["/ignore-hosts"] = "['example.test']"
			}
			if change == "new-client" {
				expected = maps.Clone(fake.data)
			}
			if err := c.Restore(t.Context()); err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(fake.data, expected) {
				t.Fatalf("recovery overwrote an unrelated owner or stranded an endpoint: %v", change)
			}
		})
	}
}

func TestProxyFailedApplyRollsBackAndFailedRecoveryRetainsJournal(t *testing.T) {
	for _, scenario := range []string{"before-write", "partial-write", "readback", "cancelled", "failed-rollback"} {
		t.Run(scenario, func(t *testing.T) {
			c, fake, before := fixture(t)
			ctx, cancel := context.WithCancel(t.Context())
			defer cancel()
			fake.write = func(_ context.Context, v values) error {
				if fake.writes > 1 {
					if scenario == "failed-rollback" {
						return errors.New("fixture rollback failed")
					}
					fake.data = maps.Clone(v)
					return nil
				}
				if scenario == "before-write" {
					return errors.New("fixture backend unavailable")
				}
				fake.data = maps.Clone(v)
				if scenario == "partial-write" {
					fake.data["/mode"] = before["/mode"]
					return errors.New("fixture interrupted commit")
				}
				if scenario == "readback" {
					fake.data["http/port"] = before["http/port"]
					return nil
				}
				if scenario == "cancelled" {
					cancel()
					return nil
				}
				return errors.New("fixture uncertain commit")
			}
			if err := c.Apply(ctx, 7891); err == nil {
				t.Fatal("failed apply reported success")
			}
			_, journalErr := os.Stat(filepath.Join(c.directory, journalName))
			if scenario == "failed-rollback" {
				if journalErr != nil {
					t.Fatal("failed recovery lost its journal")
				}
				fake.write = nil
				if err := c.Restore(t.Context()); err != nil {
					t.Fatal(err)
				}
			} else if !errors.Is(journalErr, os.ErrNotExist) {
				t.Fatalf("successful rollback kept an active lease: %v", journalErr)
			}
			if !reflect.DeepEqual(fake.data, before) {
				t.Fatal("rollback did not preserve the original settings")
			}
		})
	}
}

func TestProxyJournalRejectsTamperingAndLiveForeignOwner(t *testing.T) {
	for _, scenario := range []string{"ciphertext", "identity", "live-owner"} {
		t.Run(scenario, func(t *testing.T) {
			c, fake, _ := fixture(t)
			if err := c.Apply(t.Context(), 7891); err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(c.directory, journalName)
			switch scenario {
			case "ciphertext":
				data, err := os.ReadFile(path)
				if err != nil {
					t.Fatal(err)
				}
				data[len(data)-5] ^= 1
				if err = os.WriteFile(path, data, 0600); err != nil {
					t.Fatal(err)
				}
			case "identity":
				c.directory = filepath.Join(t.TempDir(), "different-state")
				if err := os.Mkdir(c.directory, 0700); err != nil {
					t.Fatal(err)
				}
				data, err := os.ReadFile(path)
				if err != nil {
					t.Fatal(err)
				}
				if err = os.WriteFile(filepath.Join(c.directory, journalName), data, 0600); err != nil {
					t.Fatal(err)
				}
			case "live-owner":
				identity, alive, err := processOwner(os.Getppid())
				if err != nil || !alive {
					t.Fatalf("test parent identity: %v", err)
				}
				if err := c.withLock(t.Context(), func(dir *privatefs.Directory) error {
					record, err := c.read(t.Context(), dir)
					if err != nil {
						return err
					}
					record.Owner = identity
					return c.write(t.Context(), dir, record, false)
				}); err != nil {
					t.Fatal(err)
				}
			}
			writes := fake.writes
			if err := c.Restore(t.Context()); err == nil {
				t.Fatal("unsafe recovery accepted")
			}
			if fake.writes != writes {
				t.Fatal("invalid recovery journal changed system settings")
			}
		})
	}
}

func TestInterruptedRestoreCanResumeAndPreservesALaterOwner(t *testing.T) {
	for _, laterOwner := range []bool{false, true} {
		t.Run(map[bool]string{false: "retry-partial-restore", true: "later-owner"}[laterOwner], func(t *testing.T) {
			c, fake, before := fixture(t)
			before["https/host"], before["https/port"] = "", ""
			fake.data = maps.Clone(before)
			if err := c.Apply(t.Context(), 7891); err != nil {
				t.Fatal(err)
			}
			fake.write = func(_ context.Context, target values) error {
				fake.data["/mode"] = target["/mode"]
				fake.data["https/host"] = target["https/host"]
				return errors.New("fixture interrupted during reset")
			}
			if err := c.Restore(t.Context()); err == nil {
				t.Fatal("partial restoration reported success")
			}
			if _, err := os.Stat(filepath.Join(c.directory, journalName)); err != nil {
				t.Fatal("interrupted restoration lost its durable destination", err)
			}
			fake.write = nil
			expected := before
			if laterOwner {
				fake.data["http/port"] = "9988"
				expected = maps.Clone(fake.data)
			}
			if err := c.Restore(t.Context()); err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(fake.data, expected) {
				t.Fatal("restoration stranded a partial reset or overwrote a later owner")
			}
		})
	}
}

func TestUnavailableKeyringRetainsRecoveryUntilItCanBeUnlocked(t *testing.T) {
	c, fake, before := fixture(t)
	keys := &lockableKeys{}
	c.store.Keys = keys
	if err := c.Apply(t.Context(), 7891); err != nil {
		t.Fatal(err)
	}
	keys.locked = true
	if err := c.Restore(t.Context()); !errors.Is(err, securestore.ErrUnavailable) {
		t.Fatal("locked keyring was reported as successful recovery", err)
	}
	if _, err := os.Stat(filepath.Join(c.directory, journalName)); err != nil {
		t.Fatal("keyring failure lost the encrypted journal", err)
	}
	if !reflect.DeepEqual(fake.data, ownedValues(7891)) {
		t.Fatal("unreadable journal changed system settings")
	}
	keys.locked = false
	if err := c.Restore(t.Context()); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(fake.data, before) {
		t.Fatal("unlocking did not allow recovery to resume")
	}
}

func TestGNOMESelectionAndUnavailableBackendDoNotChangeSettings(t *testing.T) {
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/fixture")
	for _, test := range []struct {
		desktop, backend string
		want             bool
	}{
		{"GNOME", "", true}, {"ubuntu:GNOME", "dconf", true}, {"KDE", "", false}, {"GNOME", "memory", false}, {"", "", false},
	} {
		t.Setenv("XDG_CURRENT_DESKTOP", test.desktop)
		t.Setenv("GSETTINGS_BACKEND", test.backend)
		if IsGNOME() != test.want {
			t.Errorf("desktop/backend accepted incorrectly: %s %s", test.desktop, test.backend)
		}
	}
	c, fake, before := fixture(t)
	fake.available = false
	if err := c.Apply(t.Context(), 7891); !errors.Is(err, ErrUnavailable) {
		t.Fatal(err)
	}
	if fake.writes != 0 || !reflect.DeepEqual(fake.data, before) {
		t.Fatal("unsupported desktop changed settings")
	}
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	if err := c.Apply(ctx, 7891); !errors.Is(err, context.Canceled) {
		t.Fatal("cancellation lost", err)
	}
}

func TestRealGNOMEProxyRoundTrip(t *testing.T) {
	if os.Getenv("RAINLINK_TEST_GNOME_PROXY") != "isolated" {
		t.Skip("requires a private D-Bus, dconf profile, keyring and XDG state")
	}
	t.Setenv("XDG_CURRENT_DESKTOP", "GNOME")
	c, err := New()
	if err != nil {
		t.Fatal(err)
	}
	if !Available(t.Context()) {
		t.Fatal("isolated GNOME settings are not writable")
	}
	before, err := c.backend.Snapshot(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer func() {
		if err := c.backend.Write(context.Background(), before); err != nil {
			t.Error(err)
		}
	}()
	if err = c.Apply(t.Context(), 49157); err != nil {
		t.Fatal(err)
	}
	t.Setenv("GSETTINGS_BACKEND", "memory")
	if err = c.Restore(t.Context()); err == nil {
		t.Fatal("process-local backend retired a persistent recovery journal")
	}
	if _, err = os.Stat(filepath.Join(c.directory, journalName)); err != nil {
		t.Fatal("failed recovery lost its journal", err)
	}
	t.Setenv("GSETTINGS_BACKEND", "dconf")
	config := os.Getenv("XDG_CONFIG_HOME")
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	if Available(t.Context()) {
		t.Fatal("mismatched service and client configuration directories accepted")
	}
	if err = c.Restore(t.Context()); err == nil {
		t.Fatal("mismatched configuration directory retired the recovery journal")
	}
	if _, err = os.Stat(filepath.Join(c.directory, journalName)); err != nil {
		t.Fatal("failed recovery lost its journal", err)
	}
	t.Setenv("XDG_CONFIG_HOME", config)
	actual, err := c.backend.Snapshot(t.Context())
	if err != nil || !reflect.DeepEqual(actual, ownedValues(49157)) {
		t.Fatalf("GNOME apply/readback mismatch: %v", err)
	}
	for _, item := range settings {
		output, err := run(t.Context(), gsettingsPath, []string{"get", item.schema(), item.key}, nil, maxSettingBytes)
		if err != nil || strings.TrimSpace(string(output)) != actual[item.id()] {
			t.Fatalf("effective GNOME schema value differs from the committed value: %s: %v", item.id(), err)
		}
	}
	data, err := os.ReadFile(filepath.Join(c.directory, journalName))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(data), "authentication") {
		t.Fatal("recovery record is not encrypted")
	}
	if err = c.Restore(t.Context()); err != nil {
		t.Fatal(err)
	}
	actual, err = c.backend.Snapshot(t.Context())
	if err != nil || !reflect.DeepEqual(actual, before) {
		t.Fatalf("GNOME original settings were not restored: %v", err)
	}
}
