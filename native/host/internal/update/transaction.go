package update

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// MarkerName blocks another ordinary launch during file replacement.
const MarkerName = ".rainlink-updating"

// Request contains only local paths and release metadata, never subscriptions.
type Request struct {
	Target  string `json:"target"`
	Support string `json:"support"`
	Archive string `json:"archive"`
	SHA256  string `json:"sha256"`
	Version string `json:"version"`
	Parent  uint32 `json:"parent"`
}

// HealthRequest authenticates the single candidate process launched by updater.
type HealthRequest struct {
	Token      string `json:"token"`
	Version    string `json:"version"`
	Executable string `json:"executable"`
	Support    string `json:"support"`
}

// Runtime owns only the process it launches. Stop must wait for its exit before
// returning, otherwise a database or executable cannot be safely rolled back.
type Runtime interface {
	StartAndVerify(context.Context, string, string, HealthRequest) error
	Stop() error
	StartPrevious(string) error
}

// Outcome is a sanitized persistent receipt for the next application launch.
type Outcome struct {
	Status  string `json:"status"`
	Version string `json:"version"`
}

// Transaction owns staging paths created by Prepare. It never deletes target
// recursively: all mutations are restricted to manifest-managed root entries.
type Transaction struct {
	request      Request
	work         string
	stage        string
	backup       string
	dataBackup   string
	marker       string
	health       string
	token        string
	previous     Manifest
	next         Manifest
	movedOld     []string
	movedNew     []string
	dataFiles    []string
	dataSaved    bool
	dataManifest []BundleFile
	phase        string
	rename       func(string, string) error
}

func canonicalDirectory(name string) (string, error) {
	if !filepath.IsAbs(name) {
		return "", errors.New("directory must be absolute")
	}
	name = filepath.Clean(name)
	if name == filepath.VolumeName(name)+string(filepath.Separator) {
		return "", errors.New("volume root cannot be an installation")
	}
	for current := name; current != filepath.Dir(current); current = filepath.Dir(current) {
		info, err := os.Lstat(current)
		if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
			return "", errors.New("directory is missing or linked")
		}
		if err := noReparse(current); err != nil {
			return "", err
		}
	}
	return name, nil
}

func inside(parent, child string) bool {
	relative, err := filepath.Rel(parent, child)
	return err == nil && relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator))
}

func plainTree(root string) error {
	return filepath.WalkDir(root, func(name string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.Type()&os.ModeSymlink != 0 || !entry.IsDir() && !entry.Type().IsRegular() {
			return errors.New("installation contains linked or special files")
		}
		return noReparse(name)
	})
}

// Prepare validates the full bundle while the application is still available.
// A non-writable installation fails here, before disconnecting any connection.
func Prepare(ctx context.Context, request Request) (prepared *Transaction, prepareErr error) {
	target, err := canonicalDirectory(request.Target)
	if err != nil {
		return nil, err
	}
	support, err := canonicalDirectory(request.Support)
	if err != nil || inside(target, support) || inside(support, target) {
		return nil, errors.New("invalid user data location")
	}
	request.Target, request.Support = target, support
	previous, err := loadManifest(target)
	if err != nil {
		return nil, err
	}
	for _, name := range roots(previous) {
		if err := plainTree(filepath.Join(target, name)); err != nil {
			return nil, fmt.Errorf("inspect installed runtime: %w", err)
		}
	}
	if err := verifyInstallation(ctx, target, previous); err != nil {
		return nil, err
	}
	work, err := os.MkdirTemp(filepath.Dir(target), ".rainlink-update-")
	if err != nil {
		return nil, fmt.Errorf("create installation staging: %w", err)
	}
	transaction := &Transaction{request: request, work: work, stage: filepath.Join(work, "staged"),
		backup: filepath.Join(work, "previous"), marker: filepath.Join(target, MarkerName),
		health: filepath.Join(work, "health"), previous: previous, rename: os.Rename}
	success := false
	defer func() {
		if !success {
			// This directory was just created by this call and contains no user
			// data. Do not erase another transaction's marker on prepare errors.
			prepareErr = errors.Join(prepareErr, os.RemoveAll(work))
		}
	}()
	for _, directory := range []string{transaction.stage, transaction.backup, transaction.health} {
		if err := os.Mkdir(directory, 0700); err != nil {
			return nil, fmt.Errorf("create transaction directory: %w", err)
		}
	}
	next, err := Extract(ctx, request.Archive, request.SHA256, request.Version, transaction.stage)
	if err != nil {
		return nil, err
	}
	transaction.next = next
	if previous.Schema != next.Schema {
		return nil, errors.New("bundle layout requires a full manual upgrade")
	}
	if previous.Schema == 2 && bootstrapFile(previous) != bootstrapFile(next) {
		// The recovery entry must remain executable throughout replacement,
		// including when it is itself performing recovery. Its small, stable
		// binary is upgraded only by a complete installer/manual replacement.
		return nil, errors.New("launcher change requires a full manual upgrade")
	}
	oldRoots := map[string]bool{}
	for _, name := range roots(previous) {
		oldRoots[strings.ToLower(name)] = true
	}
	for _, name := range roots(next) {
		if !oldRoots[strings.ToLower(name)] {
			if _, err := os.Lstat(filepath.Join(target, name)); !errors.Is(err, os.ErrNotExist) {
				return nil, errors.New("new runtime conflicts with unmanaged file")
			}
		}
	}
	random := make([]byte, 32)
	if _, err := rand.Read(random); err != nil {
		return nil, fmt.Errorf("create update token: %w", err)
	}
	transaction.token = hex.EncodeToString(random)
	transaction.dataBackup = filepath.Join(support, "update-backup-"+transaction.token)
	health := HealthRequest{Token: transaction.token, Version: request.Version,
		Executable: filepath.Join(target, runtimeExecutable(next)), Support: support}
	if err := writeJSON(filepath.Join(transaction.health, "request.json"), health, true); err != nil {
		return nil, err
	}
	if err := transaction.saveJournal(phasePrepared, true); err != nil {
		return nil, err
	}
	if err := writeJSON(transaction.marker, map[string]string{"token": transaction.token, "work": work}, true); err != nil {
		return nil, errors.Join(fmt.Errorf("installation is busy or not writable: %w", err),
			os.Remove(filepath.Join(target, JournalName)))
	}
	success = true
	return transaction, nil
}

func writeJSON(name string, value any, exclusive bool) error {
	data, err := json.Marshal(value)
	if err != nil {
		return fmt.Errorf("encode update state: %w", err)
	}
	if present, err := exists(name); err != nil {
		return err
	} else if present {
		if exclusive {
			return os.ErrExist
		}
		if err := noReparse(name); err != nil {
			return err
		}
	}
	file, err := os.CreateTemp(filepath.Dir(name), ".rainlink-state-")
	if err != nil {
		return fmt.Errorf("create update state: %w", err)
	}
	temporary := file.Name()
	defer os.Remove(temporary)
	_, writeErr := file.Write(data)
	syncErr := file.Sync()
	closeErr := file.Close()
	if writeErr != nil || syncErr != nil || closeErr != nil {
		return errors.New("save update state")
	}
	return replaceStateFile(temporary, name, exclusive)
}

// Abort is legal before applying files; it clears only this preparation.
func (transaction *Transaction) Abort() error {
	if len(transaction.movedOld) != 0 || len(transaction.movedNew) != 0 {
		return errors.New("cannot discard applied transaction")
	}
	return transaction.cleanCompleted(false)
}

var databaseFiles = []string{"rainlink.sqlite", "rainlink.sqlite-wal", "rainlink.sqlite-shm", "rainlink.sqlite-journal"}

func copyFile(ctx context.Context, source, destination string) error {
	info, err := os.Lstat(source)
	if err != nil || !info.Mode().IsRegular() || info.Size() > 2<<30 {
		return errors.New("invalid database snapshot source")
	}
	if err := noReparse(source); err != nil {
		return err
	}
	input, err := os.Open(source)
	if err != nil {
		return fmt.Errorf("open database snapshot: %w", err)
	}
	defer input.Close()
	output, err := os.OpenFile(destination, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return fmt.Errorf("create database snapshot: %w", err)
	}
	count, copyErr := io.Copy(output, &contextReader{ctx: ctx, reader: io.LimitReader(input, info.Size()+1)})
	syncErr := output.Sync()
	closeErr := output.Close()
	if copyErr != nil || syncErr != nil || closeErr != nil || count != info.Size() {
		return errors.Join(errors.New("copy database snapshot"), copyErr, syncErr, closeErr)
	}
	return nil
}

func (transaction *Transaction) snapshotData(ctx context.Context) error {
	if err := os.Mkdir(transaction.dataBackup, 0700); err != nil {
		return fmt.Errorf("create private data backup: %w", err)
	}
	for _, name := range databaseFiles {
		source := filepath.Join(transaction.request.Support, name)
		if _, err := os.Lstat(source); errors.Is(err, os.ErrNotExist) {
			continue
		} else if err != nil {
			return fmt.Errorf("inspect database: %w", err)
		}
		if err := copyFile(ctx, source, filepath.Join(transaction.dataBackup, name)); err != nil {
			return err
		}
		entry, err := inspectFile(ctx, filepath.Join(transaction.dataBackup, name))
		if err != nil {
			return err
		}
		transaction.dataManifest = append(transaction.dataManifest, entry)
		transaction.dataFiles = append(transaction.dataFiles, name)
	}
	transaction.dataSaved = true
	return transaction.saveJournal(phaseSnapshot, false)
}

func (transaction *Transaction) restoreData(ctx context.Context) error {
	if !transaction.dataSaved {
		return nil
	}
	if err := transaction.validateDataBackup(ctx); err != nil {
		return err
	}
	for _, name := range databaseFiles {
		if err := ctx.Err(); err != nil {
			return err
		}
		target := filepath.Join(transaction.request.Support, name)
		var expected *BundleFile
		for index := range transaction.dataManifest {
			if transaction.dataManifest[index].Path == name {
				expected = &transaction.dataManifest[index]
			}
		}
		if expected == nil {
			if present, err := exists(target); err != nil {
				return err
			} else if present {
				if err := noReparse(target); err != nil {
					return err
				}
				if err := os.Remove(target); err != nil {
					return fmt.Errorf("remove candidate database: %w", err)
				}
			}
			continue
		}
		temporary, err := os.CreateTemp(transaction.request.Support, "update-restore-"+transaction.token+"-")
		if err != nil {
			return err
		}
		temporaryName := temporary.Name()
		if err := temporary.Close(); err != nil {
			return err
		}
		if err := os.Remove(temporaryName); err != nil {
			return err
		}
		if err := copyFile(ctx, filepath.Join(transaction.dataBackup, name), temporaryName); err != nil {
			return errors.Join(err, os.Remove(temporaryName))
		}
		if err := replaceStateFile(temporaryName, target, false); err != nil {
			return errors.Join(err, os.Remove(temporaryName))
		}
	}
	return nil
}

func (transaction *Transaction) replace() error {
	if err := transaction.saveJournal(phaseReplacing, false); err != nil {
		return err
	}
	for _, name := range replacementRoots(transaction.previous) {
		if err := transaction.rename(filepath.Join(transaction.request.Target, name), filepath.Join(transaction.backup, name)); err != nil {
			return fmt.Errorf("back up installed entry: %w", err)
		}
		transaction.movedOld = append(transaction.movedOld, name)
	}
	for _, name := range replacementRoots(transaction.next) {
		if err := transaction.rename(filepath.Join(transaction.stage, name), filepath.Join(transaction.request.Target, name)); err != nil {
			return fmt.Errorf("activate new entry: %w", err)
		}
		transaction.movedNew = append(transaction.movedNew, name)
	}
	return nil
}

func (transaction *Transaction) rollback(ctx context.Context) error {
	if err := transaction.saveJournal(phaseRollback, false); err != nil {
		return err
	}
	for index := len(transaction.movedNew) - 1; index >= 0; index-- {
		name := transaction.movedNew[index]
		if err := transaction.rename(filepath.Join(transaction.request.Target, name), filepath.Join(transaction.stage, name)); err != nil {
			return fmt.Errorf("deactivate candidate entry: %w", err)
		}
	}
	for index := len(transaction.movedOld) - 1; index >= 0; index-- {
		name := transaction.movedOld[index]
		if err := transaction.rename(filepath.Join(transaction.backup, name), filepath.Join(transaction.request.Target, name)); err != nil {
			return fmt.Errorf("restore previous entry: %w", err)
		}
	}
	return transaction.restoreData(ctx)
}

// Apply must run only after the original process handle signals exit. Failure
// never erases backup evidence if stopping or rolling back the candidate fails.
func (transaction *Transaction) Apply(ctx context.Context, runtime Runtime) (Outcome, error) {
	outcome := Outcome{Status: "failed", Version: transaction.request.Version}
	if err := transaction.snapshotData(ctx); err != nil {
		cleanupErr := transaction.cleanup()
		receiptErr := transaction.receipt(outcome)
		launchErr := runtime.StartPrevious(filepath.Join(transaction.request.Target, "rainlink.exe"))
		return outcome, errors.Join(err, cleanupErr, receiptErr, launchErr)
	}
	cause := transaction.replace()
	if cause == nil {
		health := HealthRequest{Token: transaction.token, Version: transaction.request.Version,
			Executable: filepath.Join(transaction.request.Target, runtimeExecutable(transaction.next)), Support: transaction.request.Support}
		cause = runtime.StartAndVerify(ctx, health.Executable, transaction.health, health)
	}
	if cause == nil {
		cause = transaction.saveJournal(phaseAccepted, false)
		if cause == nil {
			// This durable commit is irreversible: recovery must keep the new
			// program and migrated data even if publishing acceptance or the
			// helper's final cleanup is interrupted.
			outcome.Status = "installed"
			if releasing, ok := runtime.(interface{ ReleaseCandidate() error }); ok {
				cause = releasing.ReleaseCandidate()
			}
			if cause == nil {
				cause = transaction.receipt(outcome)
			}
			if cause == nil {
				cause = writeJSON(filepath.Join(transaction.health, "accepted.json"),
					map[string]string{"token": transaction.token}, true)
			}
			if cause != nil {
				outcome.Status = "recovery-required"
				return outcome, errors.Join(cause, runtime.Stop(), transaction.receipt(outcome))
			}
			return outcome, transaction.cleanupAfterSuccess()
		}
	}
	if err := runtime.Stop(); err != nil {
		outcome.Status = "recovery-required"
		return outcome, errors.Join(cause, err, transaction.receipt(outcome))
	}
	// A canceled installation still needs a bounded opportunity to restore the
	// previous version, using its own lifetime rather than the canceled context.
	restoreContext, cancelRestore := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancelRestore()
	if err := transaction.rollback(restoreContext); err != nil {
		outcome.Status = "recovery-required"
		return outcome, errors.Join(cause, err, transaction.receipt(outcome))
	}
	outcome.Status = "rolled-back"
	receiptErr := transaction.receipt(outcome)
	cleanupErr := transaction.cleanup()
	if cleanupErr != nil {
		return outcome, errors.Join(cause, receiptErr, cleanupErr)
	}
	launchErr := runtime.StartPrevious(filepath.Join(transaction.request.Target, "rainlink.exe"))
	return outcome, errors.Join(cause, receiptErr, launchErr)
}

func (transaction *Transaction) receipt(outcome Outcome) error {
	return writeJSON(filepath.Join(transaction.request.Support, "update-result.json"), outcome, false)
}

func (transaction *Transaction) cleanup() error {
	return transaction.cleanCompleted(false)
}

func (transaction *Transaction) cleanupAfterSuccess() error {
	// Keep the tiny health acknowledgment until the candidate confirms seeing
	// it. Main removes it; the helper can then remove its own staging tree.
	return nil
}

// Finish removes successful backups only after the candidate consumed its
// acknowledgment; a timeout leaves these recoverable files in place.
func (transaction *Transaction) Finish() error {
	return transaction.cleanCompleted(true)
}
