//go:build linux && !android

package linuxproxy

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"rainlink.local/host/internal/privatefs"
)

type alternateBackend struct {
	*fakeBackend
	id      string
	binding string
}

func (b alternateBackend) ID() string { return b.id }
func (b alternateBackend) Binding() (string, error) {
	return b.binding, nil
}

func TestRecordedDesktopAndLegacyGNOMERecovery(t *testing.T) {
	for _, legacy := range []bool{false, true} {
		t.Run(map[bool]string{false: "recorded-desktop", true: "legacy-v1"}[legacy], func(t *testing.T) {
			c, original, before := fixture(t)
			if err := c.Apply(t.Context(), 7891); err != nil {
				t.Fatal(err)
			}
			if legacy {
				if err := c.withLock(t.Context(), func(dir *privatefs.Directory) error {
					record, err := c.read(t.Context(), dir)
					if err != nil {
						return err
					}
					record.Version, record.Backend, record.Binding = 1, "", ""
					return c.write(t.Context(), dir, record, false)
				}); err != nil {
					t.Fatal(err)
				}
			}
			other := alternateBackend{&fakeBackend{data: ownedValues(9988), available: true}, "kde", strings.Repeat("b", 64)}
			c.backends = map[string]backend{"gnome": original, "kde": other}
			c.backend = other
			if err := c.Restore(t.Context()); err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(original.data, before) || other.writes != 0 {
				t.Fatal("desktop change restored the wrong backend or lost legacy settings")
			}
		})
	}
}

func TestChangedConfigurationBindingRetainsJournal(t *testing.T) {
	c, fake, _ := fixture(t)
	if err := c.Apply(t.Context(), 7891); err != nil {
		t.Fatal(err)
	}
	c.backend = alternateBackend{fake, "gnome", strings.Repeat("b", 64)}
	writes := fake.writes
	if err := c.Restore(t.Context()); err == nil || fake.writes != writes {
		t.Fatal("different configuration location was written or reported recovered")
	}
	if _, err := os.Stat(filepath.Join(c.directory, journalName)); err != nil {
		t.Fatal("configuration mismatch discarded the recovery journal", err)
	}
	c.backend = fake
	if err := c.Restore(t.Context()); err != nil {
		t.Fatal(err)
	}
}

func requireKDE(t *testing.T) string {
	t.Helper()
	if os.Getenv("RAINLINK_TEST_KDE_PROXY") != "isolated" {
		t.Skip("requires a disposable KDE configuration, D-Bus and keyring")
	}
	if os.Geteuid() == 0 {
		t.Fatal("run desktop tests as an unprivileged user")
	}
	// Native go test places the test binary in its own temporary build folder.
	// Install the explicitly selected QA helper there, without a production
	// environment override for executable discovery.
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	helper := filepath.Join(filepath.Dir(executable), "rainlink-kde-proxy")
	if _, err = os.Lstat(helper); errors.Is(err, os.ErrNotExist) {
		data, readErr := os.ReadFile(os.Getenv("RAINLINK_TEST_KDE_HELPER_PATH"))
		if readErr != nil {
			t.Fatal("set RAINLINK_TEST_KDE_HELPER_PATH to the built QA helper", readErr)
		}
		if err = os.WriteFile(helper, data, 0700); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("XDG_CURRENT_DESKTOP", "KDE")
	root, err := configRoot()
	if err != nil {
		t.Fatal(err)
	}
	return filepath.Join(root, "kioslaverc")
}

const kdeFixture = "[Proxy Settings]\nProxyType=2\nhttpProxy=http://fixture-user:fixture-secret@original.test:3128\nProxy Config Script=https://example.test/fixture.pac?fixture-secret\nNoProxyFor=fixture.test\nReversedException=1\nUnmanaged=keep\\svalue\n\n[Other Settings]\nPreserve=original\n"

func seedKDE(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0600); err != nil {
		t.Fatal(err)
	}
}

func resolveKDE(t *testing.T, target string) string {
	t.Helper()
	path := os.Getenv("RAINLINK_TEST_PROXY_RESOLVER")
	if path == "" {
		t.Fatal("the independent libproxy resolver is required for KDE acceptance")
	}
	command := exec.CommandContext(t.Context(), path, target)
	command.Env = append(os.Environ(), "PX_CONFIG_ORDER=config-kde")
	output, err := command.Output()
	if err != nil {
		t.Fatal("libproxy failed to resolve the effective desktop proxy", err)
	}
	return strings.TrimSpace(string(output))
}

func readKDEEntry(t *testing.T, group, key string) string {
	t.Helper()
	output, err := exec.CommandContext(t.Context(), "/usr/bin/kreadconfig6", "--file", "kioslaverc", "--group", group, "--key", key).Output()
	if err != nil {
		t.Fatal("independent KConfig entry read failed", err)
	}
	return strings.TrimSuffix(string(output), "\n")
}

func TestRealKDEProxyRoundTripAndConsumer(t *testing.T) {
	path := requireKDE(t)
	seedKDE(t, path, kdeFixture)
	c, err := New()
	if err != nil {
		t.Fatal(err)
	}
	if !Available(t.Context()) {
		t.Fatal("isolated KDE configuration is not available")
	}
	before, err := c.backend.Snapshot(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	if before["/httpProxy"] != "v:http://fixture-user:fixture-secret@original.test:3128" || before["/httpsProxy"] != "" {
		t.Fatal("snapshot lost credentials or unset entries")
	}
	if err = c.Apply(t.Context(), 49157); err != nil {
		t.Fatal(err)
	}
	for target, want := range map[string]string{
		"https://example.test": "http://127.0.0.1:49157", "http://example.test": "http://127.0.0.1:49157",
		"ftp://example.test": "http://127.0.0.1:49157", "socks://example.test": "socks://127.0.0.1:49157", "http://localhost": "direct://",
	} {
		if actual := resolveKDE(t, target); actual != want {
			t.Fatalf("effective consumer proxy differs for %s: %s", target, actual)
		}
	}
	data, err := os.ReadFile(filepath.Join(c.directory, journalName))
	if err != nil || bytes.Contains(data, []byte("fixture-secret")) || !bytes.HasPrefix(data, []byte("rls1.")) {
		t.Fatal("KDE recovery record is missing or exposes credentials", err)
	}
	// Recovery must follow the journal after a desktop change.
	t.Setenv("XDG_CURRENT_DESKTOP", "RainLink-Unsupported")
	recovery, err := New()
	if err != nil {
		t.Fatal(err)
	}
	if err = recovery.Restore(t.Context()); err != nil {
		t.Fatal(err)
	}
	after, err := c.backends["kde"].Snapshot(t.Context())
	if err != nil || !reflect.DeepEqual(before, after) {
		t.Fatal("KDE credentials, PAC or unset fields were not restored", err)
	}
	if readKDEEntry(t, "Proxy Settings", "Unmanaged") != "keep value" || readKDEEntry(t, "Other Settings", "Preserve") != "original" {
		t.Fatal("KDE writes lost unrelated setting values")
	}
}

func TestRealKDEInitiallyMissingConfiguration(t *testing.T) {
	path := requireKDE(t)
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		t.Fatal(err)
	}
	if !Available(t.Context()) {
		t.Fatal("missing local overrides prevented KDE capture")
	}
	if _, err := os.Stat(path); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("availability check created a proxy configuration", err)
	}
	c, err := New()
	if err != nil {
		t.Fatal(err)
	}
	if err = c.Apply(t.Context(), 49157); err != nil {
		t.Fatal(err)
	}
	if err = c.Restore(t.Context()); err != nil {
		t.Fatal(err)
	}
	actual, err := c.backend.Snapshot(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	for _, value := range actual {
		if value != "" {
			t.Fatal("restoring a missing configuration left local proxy overrides")
		}
	}
	if resolveKDE(t, "https://example.test") != "direct://" {
		t.Fatal("consumer still used the stopped local listener")
	}
}

func TestRealKDEDefaultsAndChangeNotification(t *testing.T) {
	path := requireKDE(t)
	defaults := t.TempDir()
	t.Setenv("XDG_CONFIG_DIRS", defaults)
	seedKDE(t, filepath.Join(defaults, "kioslaverc"), "[Proxy Settings]\nProxyType=0\nhttpProxy=http://default.test:3128\n")
	seedKDE(t, path, "[Other Settings]\nPreserve=original\n")
	c, err := New()
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()
	monitor := exec.CommandContext(ctx, "/usr/bin/dbus-monitor", "--session", "type='signal',interface='org.kde.kconfig.notify',member='ConfigChanged',path='/kioslaverc'")
	output, err := monitor.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err = monitor.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { cancel(); _ = monitor.Wait() }()
	ready, notified, done := make(chan struct{}), make(chan struct{}), make(chan struct{})
	go func() {
		defer close(done)
		scanner := bufio.NewScanner(output)
		for scanner.Scan() {
			line := scanner.Text()
			if strings.Contains(line, "member=NameAcquired") {
				select {
				case <-ready:
				default:
					close(ready)
				}
			}
			if strings.Contains(line, "member=ConfigChanged") {
				select {
				case <-notified:
				default:
					close(notified)
				}
			}
		}
	}()
	select {
	case <-ready:
	case <-ctx.Done():
		t.Fatal("D-Bus notification monitor did not start")
	}
	if err = c.Apply(t.Context(), 49157); err != nil {
		t.Fatal(err)
	}
	select {
	case <-notified:
	case <-ctx.Done():
		t.Fatal("KConfig change notification was not delivered")
	}
	if readKDEEntry(t, "Proxy Settings", "httpProxy") != "http://127.0.0.1:49157" {
		t.Fatal("system default prevented the new local proxy override")
	}
	if err = c.Restore(t.Context()); err != nil {
		t.Fatal(err)
	}
	local, err := c.backend.Snapshot(t.Context())
	if err != nil || local["/httpProxy"] != "" || readKDEEntry(t, "Proxy Settings", "httpProxy") != "http://default.test:3128" {
		t.Fatal("restoration installed a default as a persistent local value", err)
	}
	seedKDE(t, filepath.Join(defaults, "kioslaverc"), "[Proxy Settings]\nProxyType[$i]=0\n")
	if Available(t.Context()) || !errors.Is(c.Apply(t.Context(), 49157), ErrUnavailable) {
		t.Fatal("immutable system defaults were overridden")
	}
	cancel()
	<-done
}

func TestRealKDERecoveryRespectsLaterChanges(t *testing.T) {
	path := requireKDE(t)
	for _, scenario := range []string{"bypass-only", "new-owner", "changed-location", "read-only-retry"} {
		t.Run(scenario, func(t *testing.T) {
			seedKDE(t, path, kdeFixture)
			c, err := New()
			if err != nil {
				t.Fatal(err)
			}
			before, err := c.backend.Snapshot(t.Context())
			if err != nil {
				t.Fatal(err)
			}
			if err = c.Apply(t.Context(), 49157); err != nil {
				t.Fatal(err)
			}
			expected := maps.Clone(before)
			switch scenario {
			case "bypass-only", "new-owner":
				current, err := c.backend.Snapshot(t.Context())
				if err != nil {
					t.Fatal(err)
				}
				if scenario == "bypass-only" {
					current["/NoProxyFor"], expected["/NoProxyFor"] = "v:edited.test", "v:edited.test"
				} else {
					current["/httpProxy"] = "v:http://other.test:9988"
					expected = maps.Clone(current)
				}
				if err = c.backend.Write(t.Context(), current); err != nil {
					t.Fatal(err)
				}
			case "changed-location":
				original := os.Getenv("XDG_CONFIG_HOME")
				t.Setenv("XDG_CONFIG_HOME", t.TempDir())
				if err = c.Restore(t.Context()); err == nil {
					t.Fatal("changed configuration directory reported restored")
				}
				t.Setenv("XDG_CONFIG_HOME", original)
			case "read-only-retry":
				if err = os.Chmod(path, 0400); err != nil {
					t.Fatal(err)
				}
				if err = c.Restore(t.Context()); err == nil {
					t.Fatal("unwritable proxy configuration reported restored")
				}
				if _, err = os.Stat(filepath.Join(c.directory, journalName)); err != nil {
					t.Fatal("failed restoration discarded its journal", err)
				}
				if err = os.Chmod(path, 0600); err != nil {
					t.Fatal(err)
				}
			}
			if err = c.Restore(t.Context()); err != nil {
				t.Fatal(err)
			}
			after, err := c.backend.Snapshot(t.Context())
			if err != nil || !reflect.DeepEqual(expected, after) {
				t.Fatal("KDE recovery lost user edits or an interrupted destination", err)
			}
		})
	}
}

func TestRealKDERejectsUnsupportedOrLockedConfiguration(t *testing.T) {
	path := requireKDE(t)
	for _, content := range []string{
		"[Proxy Settings][$i]\nProxyType=0\n", "[Proxy Settings]\nProxyType[$i]=0\n",
		"[Proxy Settings]\nhttpProxy[$e]=http://$HOST:3128\n", "[Proxy Settings]\nhttpProxy[zh_CN]=http://fixture.test:3128\n",
		"[Proxy Settings]\nhttpProxy[$d]\n",
	} {
		seedKDE(t, path, content)
		c, err := New()
		if err != nil {
			t.Fatal(err)
		}
		if Available(t.Context()) || !errors.Is(c.Apply(t.Context(), 49157), ErrUnavailable) {
			t.Fatal("unsupported or immutable configuration accepted")
		}
		after, err := os.ReadFile(path)
		if err != nil || string(after) != content {
			t.Fatal("rejected configuration was modified", err)
		}
	}
	seedKDE(t, path, kdeFixture)
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	if _, err := (kdeBackend{}).Snapshot(ctx); !errors.Is(err, context.Canceled) {
		t.Fatal("KDE cancellation was lost", err)
	}
}
