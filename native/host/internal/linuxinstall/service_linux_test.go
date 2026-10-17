//go:build linux && !android

package linuxinstall

import (
	"strings"
	"testing"
)

func TestSystemdStateRefusesOverridesMasksAndTransitionalUnits(t *testing.T) {
	good := "LoadState=loaded\nActiveState=active\nUnitFileState=enabled\nFragmentPath=/usr/lib/systemd/system/rainlink-tun.socket\nDropInPaths=\n"
	if state, err := parseUnit([]byte(good), socketUnit); err != nil || !state.loaded || !state.active || !state.enabled {
		t.Fatal(state, err)
	}
	for _, bad := range []string{
		strings.ReplaceAll(good, "DropInPaths=", "DropInPaths=/etc/systemd/system/rainlink-tun.socket.d/local.conf"),
		strings.ReplaceAll(good, "LoadState=loaded", "LoadState=masked"),
		strings.ReplaceAll(good, "/usr/lib/systemd/system/", "/etc/systemd/system/"),
		strings.ReplaceAll(good, "ActiveState=active", "ActiveState=activating"),
		strings.ReplaceAll(good, "UnitFileState=enabled", "UnitFileState=enabled-runtime"),
		good + "ActiveState=inactive\n",
		strings.ReplaceAll(good, "DropInPaths=\n", ""),
	} {
		if _, err := parseUnit([]byte(bad), socketUnit); err == nil {
			t.Fatal("unexpected unit accepted", bad)
		}
	}
	absent := "LoadState=not-found\nActiveState=inactive\nUnitFileState=\nFragmentPath=\nDropInPaths=\n"
	if state, err := parseUnit([]byte(absent), socketUnit); err != nil || state.loaded {
		t.Fatal(state, err)
	}
	instance := strings.ReplaceAll(strings.ReplaceAll(good, socketUnit, templateUnit), "UnitFileState=enabled", "UnitFileState=static")
	if state, err := parseUnitForStop([]byte(instance), "rainlink-tun@1-local.service", true); err != nil || !state.active {
		t.Fatal("valid instance not accepted", state, err)
	}
	transition := strings.ReplaceAll(good, "ActiveState=active", "ActiveState=deactivating")
	if state, err := parseUnitForStop([]byte(transition), socketUnit, true); err != nil || !state.active {
		t.Fatal("stop could not handle interrupted transition", state, err)
	}
}

func TestSystemdInstanceNamesAreBoundedAndCannotSelectOtherServices(t *testing.T) {
	if names, err := instances([]byte("rainlink-tun@1-123-local.service loaded active running RainLink\n")); err != nil || len(names) != 1 {
		t.Fatal(names, err)
	}
	for _, name := range []string{"rainlink-tun@.service", "other.service", "--now", "rainlink-tun@/../../.service", "rainlink-tun@$(id).service", "rainlink-tun@a\nother.service"} {
		if validInstance(name) {
			t.Fatal("unsafe instance accepted", name)
		}
	}
	if _, err := instances([]byte("other.service loaded active running\n")); err == nil {
		t.Fatal("other service selected")
	}
	var buffer boundedOutput
	if _, err := buffer.Write(make([]byte, 65<<10)); err == nil {
		t.Fatal("unbounded output accepted")
	}
}
