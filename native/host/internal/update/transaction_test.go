package update

import (
	"archive/zip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

func testFiles(label string) map[string][]byte {
	result := map[string][]byte{}
	for _, name := range []string{"rainlink.exe", "rainlink-host.exe", "rainlink-updater.exe", "sing-box.exe", "flutter_windows.dll", "data/app.so"} {
		result[name] = []byte(label + "-" + name)
	}
	return result
}

func testManifest(version string, files map[string][]byte) Manifest {
	manifest := Manifest{Schema: 1, Product: "RainLink", Platform: "windows-x64", Version: version}
	if _, present := files["rainlink-ui.exe"]; present {
		manifest.Schema = 2
	}
	for name, data := range files {
		hash := sha256.Sum256(data)
		manifest.Files = append(manifest.Files, BundleFile{Path: name, Bytes: int64(len(data)), SHA256: hex.EncodeToString(hash[:])})
	}
	sort.Slice(manifest.Files, func(i, j int) bool { return manifest.Files[i].Path < manifest.Files[j].Path })
	return manifest
}

func bootstrapFiles(label string) map[string][]byte {
	files := testFiles(label)
	files["rainlink.exe"] = []byte("stable-recovery-launcher")
	files["rainlink-ui.exe"] = []byte(label + "-rainlink-ui.exe")
	return files
}

func prepareBootstrapFixture(t *testing.T) (*Transaction, string) {
	t.Helper()
	archive, hash := writeBundle(t, "0.2.0+1", bootstrapFiles("new"), nil)
	support := t.TempDir()
	transaction, err := Prepare(context.Background(), Request{
		Target: installFixture(t, bootstrapFiles("old")), Support: support,
		Archive: archive, SHA256: hash, Version: "v0.2.0+1"})
	if err != nil {
		t.Fatal(err)
	}
	return transaction, support
}

func TestBootstrapMustRemainIdenticalAcrossOnlineUpdates(t *testing.T) {
	files := bootstrapFiles("new")
	files["rainlink.exe"] = []byte("different-launcher-requires-manual-upgrade")
	archive, hash := writeBundle(t, "0.2.0+1", files, nil)
	target := installFixture(t, bootstrapFiles("old"))
	if _, err := Prepare(context.Background(), Request{
		Target: target, Support: t.TempDir(), Archive: archive, SHA256: hash, Version: "0.2.0+1"}); err == nil {
		t.Fatal("online update replaced the only recovery entry")
	}
	if err := verifyInstallation(context.Background(), target, testManifest("0.1.0+1", bootstrapFiles("old"))); err != nil {
		t.Fatal("rejected preparation changed the installation")
	}
}

func writeBundle(t *testing.T, version string, files map[string][]byte, alter func(*zip.Writer) error) (string, string) {
	t.Helper()
	archive := filepath.Join(t.TempDir(), "bundle.zip")
	output, err := os.Create(archive)
	if err != nil {
		t.Fatal(err)
	}
	writer := zip.NewWriter(output)
	manifest := testManifest(version, files)
	data, err := json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	all := map[string][]byte{ManifestName: data}
	for name, contents := range files {
		all[name] = contents
	}
	for name, contents := range all {
		stream, err := writer.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := stream.Write(contents); err != nil {
			t.Fatal(err)
		}
	}
	if alter != nil {
		if err := alter(writer); err != nil {
			t.Fatal(err)
		}
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	if err := output.Close(); err != nil {
		t.Fatal(err)
	}
	contents, err := os.ReadFile(archive)
	if err != nil {
		t.Fatal(err)
	}
	hash := sha256.Sum256(contents)
	return archive, hex.EncodeToString(hash[:])
}

func installFixture(t *testing.T, files map[string][]byte) string {
	t.Helper()
	target := filepath.Join(t.TempDir(), "RainLink")
	for name, contents := range files {
		file := filepath.Join(target, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(file), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(file, contents, 0600); err != nil {
			t.Fatal(err)
		}
	}
	if err := writeJSON(filepath.Join(target, ManifestName), testManifest("0.1.0+1", files), true); err != nil {
		t.Fatal(err)
	}
	return target
}

func prepareFixture(t *testing.T) (*Transaction, string) {
	t.Helper()
	archive, hash := writeBundle(t, "0.2.0+1", testFiles("new"), nil)
	support := t.TempDir()
	transaction, err := Prepare(context.Background(), Request{
		Target: installFixture(t, testFiles("old")), Support: support,
		Archive: archive, SHA256: hash, Version: "v0.2.0+1"})
	if err != nil {
		t.Fatal(err)
	}
	return transaction, support
}

func TestUnsafeBundlePathsAndLimits(t *testing.T) {
	for _, name := range []string{"../evil.exe", "/rainlink.exe", "C:/rainlink.exe", "data\\evil",
		"data/file:stream", "data/NUL.txt", "data/file.", "data/COM1", "data/LPT0.txt",
		"data/x/../../outside", "data/x\nfoo", "data//file", "rainlink.sqlite"} {
		if validPath(name) {
			t.Errorf("accepted unsafe path %q", name)
		}
	}
	for _, name := range []string{"rainlink.exe", "sqlite3.dll", "native_assets.yaml", "data/flutter_assets/assets/icons/back.svg"} {
		if !validPath(name) {
			t.Errorf("rejected valid path %q", name)
		}
	}
	for _, scenario := range []string{"extra", "case-duplicate", "symlink", "directory", "traversal"} {
		t.Run(scenario, func(t *testing.T) {
			archive, hash := writeBundle(t, "0.2.0+1", testFiles("new"), func(writer *zip.Writer) error {
				header := &zip.FileHeader{Name: "unknown.dll"}
				switch scenario {
				case "case-duplicate":
					header.Name = "RAINLINK.EXE"
				case "symlink":
					header.SetMode(os.ModeSymlink | 0600)
				case "directory":
					header.Name = "data/"
					header.SetMode(os.ModeDir | 0700)
				case "traversal":
					header.Name = "../outside.dll"
				}
				stream, err := writer.CreateHeader(header)
				if err == nil && scenario != "directory" {
					_, err = stream.Write([]byte("evil"))
				}
				return err
			})
			if _, err := Extract(context.Background(), archive, hash, "0.2.0+1", t.TempDir()); err == nil {
				t.Fatal("unsafe archive accepted")
			}
		})
	}
}

func TestDigestVersionManifestAndCancellation(t *testing.T) {
	files := testFiles("new")
	archive, hash := writeBundle(t, "0.2.0+1", files, nil)
	for _, test := range []struct{ hash, version string }{
		{strings.Repeat("0", 64), "0.2.0+1"}, {hash, "0.3.0"}, {"", "0.2.0+1"},
	} {
		if _, err := Extract(context.Background(), archive, test.hash, test.version, t.TempDir()); err == nil {
			t.Fatal("invalid bundle accepted")
		}
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := Extract(ctx, archive, hash, "0.2.0+1", t.TempDir()); !errors.Is(err, context.Canceled) {
		t.Fatalf("expected cancellation, got %v", err)
	}
	manifest := testManifest("0.2.0+1", files)
	manifest.Files[0].Bytes = maxExpanded + 1
	data, err := json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := parseManifest(data); err == nil {
		t.Fatal("expanded size limit ignored")
	}
}

type fixtureRuntime struct {
	support string
	fail    bool
	stopErr error
	stops   int
	old     int
}

func (runtime *fixtureRuntime) StartAndVerify(_ context.Context, _, _ string, _ HealthRequest) error {
	if err := os.WriteFile(filepath.Join(runtime.support, "rainlink.sqlite"), []byte("migrated-database"), 0600); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(runtime.support, "rainlink.sqlite-wal"), []byte("new-wal"), 0600); err != nil {
		return err
	}
	if runtime.fail {
		return errors.New("fixture new process failed")
	}
	return nil
}
func (runtime *fixtureRuntime) Stop() error                { runtime.stops++; return runtime.stopErr }
func (runtime *fixtureRuntime) StartPrevious(string) error { runtime.old++; return nil }

func TestSuccessfulTransactionPreservesUnmanagedFiles(t *testing.T) {
	transaction, support := prepareFixture(t)
	unmanaged := filepath.Join(transaction.request.Target, "personal.txt")
	if err := os.WriteFile(unmanaged, []byte("keep me"), 0600); err != nil {
		t.Fatal(err)
	}
	runtime := &fixtureRuntime{support: support}
	outcome, err := transaction.Apply(context.Background(), runtime)
	if err != nil || outcome.Status != "installed" || runtime.stops != 0 || runtime.old != 0 {
		t.Fatalf("install failed: %v %+v", err, outcome)
	}
	if contents, err := os.ReadFile(filepath.Join(transaction.request.Target, "rainlink.exe")); err != nil || string(contents) != "new-rainlink.exe" {
		t.Fatal("new runtime was not installed")
	}
	if _, err := os.Stat(unmanaged); err != nil {
		t.Fatal("unmanaged file was removed")
	}
	if _, err := os.Stat(transaction.marker); err != nil {
		t.Fatal("startup must remain guarded until the candidate consumes its acknowledgment")
	}
	if err := transaction.Finish(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(transaction.marker); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("ordinary startup remains blocked after completion")
	}
	if _, err := os.Stat(transaction.work); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("successful staging leaked")
	}
}

func TestFailedStartupRestoresProgramsAndDatabaseWAL(t *testing.T) {
	transaction, support := prepareFixture(t)
	for name, content := range map[string]string{"rainlink.sqlite": "original-database", "rainlink.sqlite-wal": "original-wal"} {
		if err := os.WriteFile(filepath.Join(support, name), []byte(content), 0600); err != nil {
			t.Fatal(err)
		}
	}
	runtime := &fixtureRuntime{support: support, fail: true}
	outcome, err := transaction.Apply(context.Background(), runtime)
	if err == nil || outcome.Status != "rolled-back" || runtime.stops != 1 || runtime.old != 1 {
		t.Fatalf("rollback missing: %v %+v", err, outcome)
	}
	for name, expected := range map[string]string{"rainlink.sqlite": "original-database", "rainlink.sqlite-wal": "original-wal"} {
		actual, err := os.ReadFile(filepath.Join(support, name))
		if err != nil || string(actual) != expected {
			t.Fatalf("did not restore %s", name)
		}
	}
	actual, err := os.ReadFile(filepath.Join(transaction.request.Target, "rainlink.exe"))
	if err != nil || string(actual) != "old-rainlink.exe" {
		t.Fatal("original executable not restored")
	}
	if _, err := os.Stat(transaction.work); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("rolled back staging leaked")
	}
}

func TestMidReplacementFailureRestoresEveryOldEntry(t *testing.T) {
	transaction, support := prepareFixture(t)
	realRename := transaction.rename
	failed := false
	transaction.rename = func(source, destination string) error {
		if !failed && strings.HasPrefix(source, transaction.stage) && filepath.Base(source) == "rainlink.exe" {
			failed = true
			return errors.New("fixture disk write failed")
		}
		return realRename(source, destination)
	}
	runtime := &fixtureRuntime{support: support}
	outcome, err := transaction.Apply(context.Background(), runtime)
	if err == nil || outcome.Status != "rolled-back" || !failed || runtime.old != 1 {
		t.Fatalf("replacement rollback failed: %v %+v", err, outcome)
	}
	for name, expected := range testFiles("old") {
		contents, err := os.ReadFile(filepath.Join(transaction.request.Target, filepath.FromSlash(name)))
		if err != nil || string(contents) != string(expected) {
			t.Fatalf("original entry missing: %s", name)
		}
	}
}

func TestFailedCandidateStopRetainsBackupAndBlocksOrdinaryStartup(t *testing.T) {
	transaction, support := prepareFixture(t)
	runtime := &fixtureRuntime{support: support, fail: true, stopErr: errors.New("fixture wait failure")}
	outcome, err := transaction.Apply(context.Background(), runtime)
	if err == nil || outcome.Status != "recovery-required" || runtime.old != 0 {
		t.Fatal("unconfirmed stop must not overwrite a live database")
	}
	if _, err := os.Stat(filepath.Join(transaction.backup, "rainlink.exe")); err != nil {
		t.Fatal("recoverable original was erased")
	}
	if _, err := os.Stat(transaction.marker); err != nil {
		t.Fatal("unsafe ordinary launch was allowed")
	}
	// Test cleanup is restricted to paths produced by this fixture transaction.
	if err := os.RemoveAll(transaction.work); err != nil {
		t.Fatal(err)
	}
	if err := os.RemoveAll(transaction.dataBackup); err != nil {
		t.Fatal(err)
	}
}

func TestAbortAndConflictingPreparations(t *testing.T) {
	transaction, _ := prepareFixture(t)
	if _, err := Prepare(context.Background(), transaction.request); err == nil {
		t.Fatal("second preparation should not overwrite the active marker")
	}
	if _, err := os.Stat(transaction.marker); err != nil {
		t.Fatal("failed second preparation erased first marker")
	}
	if err := transaction.Abort(); err != nil {
		t.Fatal(err)
	}
	actual, err := os.ReadFile(filepath.Join(transaction.request.Target, "rainlink.exe"))
	if err != nil || string(actual) != "old-rainlink.exe" {
		t.Fatal("abort touched installed program")
	}
}
