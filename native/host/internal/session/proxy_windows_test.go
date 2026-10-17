package session

import (
	"os"
	"reflect"
	"testing"

	"golang.org/x/sys/windows/registry"
)

func TestSystemProxyRestoresExactOriginalValues(t *testing.T) {
	if os.Getenv("RAINLINK_TEST_SYSTEM_PROXY") != "1" {
		t.Skip("explicit opt-in required for the real Windows proxy round trip")
	}
	key, err := registry.OpenKey(registry.CURRENT_USER, internetKey, registry.QUERY_VALUE|registry.SET_VALUE)
	if err != nil {
		t.Fatal(err)
	}
	defer key.Close()
	before, err := registrySnapshot(key)
	if err != nil {
		t.Fatal(err)
	}
	directory := t.TempDir()
	defer func() {
		if err := restoreProxy(directory); err != nil {
			t.Error("proxy restoration failed")
		}
	}()
	if err = applyProxy(t.Context(), directory, 49157); err != nil {
		t.Fatal(err)
	}
	active, err := registrySnapshot(key)
	if err != nil {
		t.Fatal(err)
	}
	if reflect.DeepEqual(active, before) {
		t.Fatal("proxy settings were not applied")
	}
	if err = restoreProxy(directory); err != nil {
		t.Fatal(err)
	}
	after, err := registrySnapshot(key)
	if err != nil || !reflect.DeepEqual(after, before) {
		t.Fatal("original proxy values were not restored exactly")
	}
}

func TestBypassEditDoesNotLeaveDeadProxyConfigured(t *testing.T) {
	if os.Getenv("RAINLINK_TEST_SYSTEM_PROXY") != "1" {
		t.Skip("explicit opt-in required")
	}
	key, err := registry.OpenKey(registry.CURRENT_USER, internetKey, registry.QUERY_VALUE|registry.SET_VALUE)
	if err != nil {
		t.Fatal(err)
	}
	defer key.Close()
	before, err := registrySnapshot(key)
	if err != nil {
		t.Fatal(err)
	}
	defer func() {
		if err := writeRegistry(key, before); err != nil {
			t.Error(err)
		}
	}()
	directory := t.TempDir()
	defer restoreProxy(directory)
	if err = applyProxy(t.Context(), directory, 49157); err != nil {
		t.Fatal(err)
	}
	if err = key.SetStringValue("ProxyOverride", "example.test"); err != nil {
		t.Fatal(err)
	}
	if err = restoreProxy(directory); err != nil {
		t.Fatal(err)
	}
	after, err := registrySnapshot(key)
	if err != nil {
		t.Fatal(err)
	}
	want := make(map[string]registryValue)
	for name, value := range before {
		want[name] = value
	}
	want["ProxyOverride"] = stringValue("example.test")
	if !reflect.DeepEqual(after, want) {
		t.Fatal("bypass edit prevented restoration of the owned proxy endpoint")
	}
}

func TestRecoveryPreservesAnotherClientsLaterProxy(t *testing.T) {
	if os.Getenv("RAINLINK_TEST_SYSTEM_PROXY") != "1" {
		t.Skip("explicit opt-in required")
	}
	key, err := registry.OpenKey(registry.CURRENT_USER, internetKey, registry.QUERY_VALUE|registry.SET_VALUE)
	if err != nil {
		t.Fatal(err)
	}
	defer key.Close()
	before, err := registrySnapshot(key)
	if err != nil {
		t.Fatal(err)
	}
	defer func() {
		if err := writeRegistry(key, before); err != nil {
			t.Error("restore test baseline failed")
		}
	}()
	directory := t.TempDir()
	defer restoreProxy(directory)
	if err = applyProxy(t.Context(), directory, 49157); err != nil {
		t.Fatal(err)
	}
	if err = key.SetStringValue("ProxyServer", "127.0.0.1:49158"); err != nil {
		t.Fatal(err)
	}
	if err = restoreProxy(directory); err != nil {
		t.Fatal(err)
	}
	actual, _, err := key.GetStringValue("ProxyServer")
	if err != nil || actual != "127.0.0.1:49158" {
		t.Fatal("recovery overwrote another client's setting")
	}
}
