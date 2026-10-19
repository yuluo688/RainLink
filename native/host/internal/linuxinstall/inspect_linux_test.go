//go:build linux && !android

package linuxinstall

import (
	"os"
	"path/filepath"
	"testing"

	assets "rainlink.local/host/packaging/linux"
)

func TestServiceInspectionPreservesFilesAndDetectsPartialAndDifferentVersions(t *testing.T) {
	root, _, _, _ := newFixture(t)
	host, core := root+"/bundle-host", root+"/bundle-core"
	if err := os.WriteFile(host, []byte("fixture host"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(core, []byte("fixture core"), 0755); err != nil {
		t.Fatal(err)
	}
	if current, count, err := inspectServiceFiles(t.Context(), root, host, core); err != nil || current || count != 0 {
		t.Fatal("missing files reported current", current, count, err)
	}
	for index, target := range targets {
		data := []byte("fixture host")
		if index == 1 {
			data = []byte("fixture core")
		}
		if index > 1 {
			var err error
			data, err = assets.Files.ReadFile(filepath.Base(target.path))
			if err != nil {
				t.Fatal(err)
			}
		}
		if err := os.WriteFile(root+target.path, data, os.FileMode(target.mode)); err != nil {
			t.Fatal(err)
		}
	}
	if current, count, err := inspectServiceFiles(t.Context(), root, host, core); err != nil || !current || count != len(targets) {
		t.Fatal("matching files were not current", current, count, err)
	}
	if err := os.WriteFile(host, []byte("new host version"), 0755); err != nil {
		t.Fatal(err)
	}
	if current, count, err := inspectServiceFiles(t.Context(), root, host, core); err != nil || current || count != len(targets) {
		t.Fatal("different release not detected", current, count, err)
	}
	if err := os.Remove(root + targets[4].path); err != nil {
		t.Fatal(err)
	}
	if current, count, err := inspectServiceFiles(t.Context(), root, host, core); err != nil || current || count != len(targets)-1 {
		t.Fatal("partial installation not detected", current, count, err)
	}
	// Inspection cannot replace or follow an administrator's redirected path.
	if err := os.Symlink(host, root+targets[4].path); err != nil {
		t.Fatal(err)
	}
	if _, _, err := inspectServiceFiles(t.Context(), root, host, core); err == nil {
		t.Fatal("linked installation file was accepted")
	}
	if data, err := os.ReadFile(host); err != nil || string(data) != "new host version" {
		t.Fatal("inspection changed input", err)
	}
}
