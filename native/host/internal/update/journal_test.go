package update

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

var interrupted = errors.New("simulated process interruption")

func crashAfterRename(after int) func(string, string) error {
	moves := 0
	return func(from, to string) error {
		if err := os.Rename(from, to); err != nil {
			return err
		}
		moves++
		if moves == after {
			return interrupted
		}
		return nil
	}
}

func writeOriginalData(t *testing.T, support string) {
	t.Helper()
	for name, value := range map[string]string{"rainlink.sqlite": "original-database", "rainlink.sqlite-wal": "original-wal"} {
		if err := os.WriteFile(filepath.Join(support, name), []byte(value), 0600); err != nil {
			t.Fatal(err)
		}
	}
}

func assertOriginalData(t *testing.T, support string) {
	t.Helper()
	for name, value := range map[string]string{"rainlink.sqlite": "original-database", "rainlink.sqlite-wal": "original-wal"} {
		actual, err := os.ReadFile(filepath.Join(support, name))
		if err != nil || string(actual) != value {
			t.Fatalf("database snapshot differs: %s %v", name, err)
		}
	}
	if _, err := os.Stat(filepath.Join(support, "rainlink.sqlite-shm")); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("candidate-only SHM survived recovery")
	}
}

func TestRecoveryAfterEveryInterruptedRuntimeMove(t *testing.T) {
	count := 2 * len(replacementRoots(testManifest("0.2.0+1", bootstrapFiles("new"))))
	for at := 1; at <= count; at++ {
		t.Run(strings.Repeat("x", at), func(t *testing.T) {
			transaction, support := prepareBootstrapFixture(t)
			writeOriginalData(t, support)
			personal := filepath.Join(transaction.request.Target, "personal.txt")
			if err := os.WriteFile(personal, []byte("untouched"), 0600); err != nil {
				t.Fatal(err)
			}
			if err := transaction.snapshotData(context.Background()); err != nil {
				t.Fatal(err)
			}
			transaction.rename = crashAfterRename(at)
			if err := transaction.replace(); !errors.Is(err, interrupted) {
				t.Fatalf("expected interruption, got %v", err)
			}
			if err := verifyRoot(context.Background(), transaction.request.Target, "rainlink.exe", transaction.previous); err != nil {
				t.Fatal("recovery launcher disappeared during replacement")
			}
			for _, name := range databaseFiles[:3] {
				if err := os.WriteFile(filepath.Join(support, name), []byte("candidate"), 0600); err != nil {
					t.Fatal(err)
				}
			}
			result, found, err := Recover(context.Background(), transaction.request.Target)
			if err != nil || !found || result.Status != "interrupted-restored" {
				t.Fatalf("fresh recovery: %+v %v", result, err)
			}
			assertOriginalData(t, support)
			if err := verifyInstallation(context.Background(), transaction.request.Target, transaction.previous); err != nil {
				t.Fatal(err)
			}
			if contents, err := os.ReadFile(personal); err != nil || string(contents) != "untouched" {
				t.Fatal("unmanaged file changed")
			}
			if _, found, err := Recover(context.Background(), transaction.request.Target); err != nil || found {
				t.Fatal("finished recovery is not idempotent")
			}
		})
	}
}

type unreleasableRuntime struct{ fixtureRuntime }

func (*unreleasableRuntime) ReleaseCandidate() error { return errors.New("fixture job release failed") }

func TestDurableAcceptanceNeverRollsBackEvenIfFinalHandshakeFails(t *testing.T) {
	transaction, support := prepareBootstrapFixture(t)
	writeOriginalData(t, support)
	runtime := &unreleasableRuntime{fixtureRuntime{support: support}}
	outcome, err := transaction.Apply(context.Background(), runtime)
	if err == nil || outcome.Status != "recovery-required" || runtime.stops != 1 || runtime.old != 0 {
		t.Fatalf("uncertain final handshake misreported: %+v %v", outcome, err)
	}
	result, found, err := Recover(context.Background(), transaction.request.Target)
	if err != nil || !found || result.Status != "installed" {
		t.Fatalf("durable acceptance lost: %+v %v", result, err)
	}
	if err := verifyInstallation(context.Background(), transaction.request.Target, transaction.next); err != nil {
		t.Fatal(err)
	}
	if data, err := os.ReadFile(filepath.Join(support, "rainlink.sqlite")); err != nil || string(data) != "migrated-database" {
		t.Fatal("accepted database was downgraded")
	}
}

func TestCanceledRecoveryRetainsRecoverableBackup(t *testing.T) {
	transaction, support := prepareBootstrapFixture(t)
	writeOriginalData(t, support)
	if err := transaction.snapshotData(context.Background()); err != nil {
		t.Fatal(err)
	}
	if err := transaction.replace(); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, _, err := Recover(ctx, transaction.request.Target); !errors.Is(err, context.Canceled) {
		t.Fatalf("canceled recovery was not canceled: %v", err)
	}
	if _, _, err := Recover(context.Background(), transaction.request.Target); err != nil {
		t.Fatal(err)
	}
	assertOriginalData(t, support)
}

func TestRecoveryCanResumeInterruptedRecovery(t *testing.T) {
	count := 2 * len(replacementRoots(testManifest("0.2.0+1", bootstrapFiles("new"))))
	for at := 1; at <= count; at++ {
		transaction, support := prepareBootstrapFixture(t)
		writeOriginalData(t, support)
		if err := transaction.snapshotData(context.Background()); err != nil {
			t.Fatal(err)
		}
		if err := transaction.replace(); err != nil {
			t.Fatal(err)
		}
		loaded, err := readJournal(transaction.request.Target)
		if err != nil {
			t.Fatal(err)
		}
		if err := loaded.saveJournal(phaseRollback, false); err != nil {
			t.Fatal(err)
		}
		loaded.rename = crashAfterRename(at)
		if err := loaded.restoreRuntime(context.Background()); !errors.Is(err, interrupted) {
			t.Fatalf("expected recovery interruption %d: %v", at, err)
		}
		if _, found, err := Recover(context.Background(), transaction.request.Target); err != nil || !found {
			t.Fatalf("resume recovery %d: %v", at, err)
		}
		assertOriginalData(t, support)
	}
}

func TestAcceptedVersionRetainsMigratedDataOnHelperInterruption(t *testing.T) {
	transaction, support := prepareBootstrapFixture(t)
	writeOriginalData(t, support)
	if err := transaction.snapshotData(context.Background()); err != nil {
		t.Fatal(err)
	}
	if err := transaction.replace(); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(support, "rainlink.sqlite"), []byte("migrated-and-in-use"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := transaction.saveJournal(phaseAccepted, false); err != nil {
		t.Fatal(err)
	}
	result, found, err := Recover(context.Background(), transaction.request.Target)
	if err != nil || !found || result.Status != "installed" {
		t.Fatalf("accepted recovery: %+v %v", result, err)
	}
	if data, err := os.ReadFile(filepath.Join(support, "rainlink.sqlite")); err != nil || string(data) != "migrated-and-in-use" {
		t.Fatal("committed data was rolled back")
	}
	if err := verifyInstallation(context.Background(), transaction.request.Target, transaction.next); err != nil {
		t.Fatal(err)
	}
}

func TestPreparedAndCompletedCleanupRecovery(t *testing.T) {
	for _, phase := range []string{phasePrepared, phaseCompleteOld, phaseCompleteNew} {
		transaction, support := prepareBootstrapFixture(t)
		writeOriginalData(t, support)
		if phase == phaseCompleteNew {
			if err := transaction.snapshotData(context.Background()); err != nil {
				t.Fatal(err)
			}
			if err := transaction.replace(); err != nil {
				t.Fatal(err)
			}
		}
		if err := transaction.saveJournal(phase, false); err != nil {
			t.Fatal(err)
		}
		if phase != phasePrepared {
			// Cleanup had already removed staging when its process stopped.
			if err := os.RemoveAll(transaction.work); err != nil {
				t.Fatal(err)
			}
		}
		if _, found, err := Recover(context.Background(), transaction.request.Target); err != nil || !found {
			t.Fatalf("phase %s: %v", phase, err)
		}
		assertOriginalData(t, support)
	}
}

func TestRecoveryRejectsCorruptBackupBeforeMutatingProgramOrDatabase(t *testing.T) {
	transaction, support := prepareBootstrapFixture(t)
	writeOriginalData(t, support)
	if err := transaction.snapshotData(context.Background()); err != nil {
		t.Fatal(err)
	}
	if err := transaction.replace(); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(transaction.dataBackup, "rainlink.sqlite"), []byte("corrupt"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, found, err := Recover(context.Background(), transaction.request.Target); err == nil || !found {
		t.Fatal("corrupt backup was accepted")
	}
	if err := verifyInstallation(context.Background(), transaction.request.Target, transaction.next); err != nil {
		t.Fatal("runtime mutated before backup verification")
	}
	assertOriginalData(t, support)
}

func TestJournalRejectsPathAndIdentityTampering(t *testing.T) {
	for _, field := range []string{"work", "target", "token", "phase", "data"} {
		transaction, _ := prepareBootstrapFixture(t)
		name := filepath.Join(transaction.request.Target, JournalName)
		data, err := os.ReadFile(name)
		if err != nil {
			t.Fatal(err)
		}
		var state map[string]any
		if err := json.Unmarshal(data, &state); err != nil {
			t.Fatal(err)
		}
		switch field {
		case "work":
			state[field] = filepath.Dir(transaction.work)
		case "target":
			state[field] = filepath.Dir(transaction.request.Target)
		case "token":
			state[field] = "wrong"
		case "phase":
			state[field] = "unknown"
		case "data":
			state[field] = []any{map[string]any{"path": "../personal.sqlite", "bytes": 0, "sha256": strings.Repeat("0", 64)}}
		}
		if err := writeJSON(name, state, false); err != nil {
			t.Fatal(err)
		}
		if _, found, err := Recover(context.Background(), transaction.request.Target); err == nil || !found {
			t.Fatalf("tampered %s accepted", field)
		}
		if err := verifyInstallation(context.Background(), transaction.request.Target, transaction.previous); err != nil {
			t.Fatal("tampered state mutated runtime")
		}
	}
}
