package update

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"strings"
)

// JournalName persists outside the staging tree, including during its cleanup.
const JournalName = ".rainlink-update.json"

const (
	phasePrepared    = "prepared"
	phaseSnapshot    = "snapshotted"
	phaseReplacing   = "replacing"
	phaseRollback    = "rolling-back"
	phaseAccepted    = "accepted"
	phaseCompleteOld = "complete-old"
	phaseCompleteNew = "complete-new"
)

type journal struct {
	Schema    int          `json:"schema"`
	Target    string       `json:"target"`
	Support   string       `json:"support"`
	Work      string       `json:"work"`
	Token     string       `json:"token"`
	Version   string       `json:"version"`
	Phase     string       `json:"phase"`
	Previous  Manifest     `json:"previous"`
	Next      Manifest     `json:"next"`
	DataSaved bool         `json:"dataSaved"`
	Data      []BundleFile `json:"data"`
}

func (transaction *Transaction) saveJournal(phase string, exclusive bool) error {
	state := journal{Schema: 1, Target: transaction.request.Target,
		Support: transaction.request.Support, Work: transaction.work,
		Token: transaction.token, Version: transaction.request.Version, Phase: phase,
		Previous: transaction.previous, Next: transaction.next,
		DataSaved: transaction.dataSaved, Data: transaction.dataManifest}
	if err := writeJSON(filepath.Join(state.Target, JournalName), state, exclusive); err != nil {
		return fmt.Errorf("persist update journal: %w", err)
	}
	transaction.phase = phase
	return nil
}

func readJournal(target string) (*Transaction, error) {
	name := filepath.Join(target, JournalName)
	if err := noReparse(name); err != nil {
		return nil, err
	}
	file, err := os.Open(name)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, 2*maxManifest+65537))
	if err != nil || len(data) > 2*maxManifest+65536 {
		return nil, errors.New("invalid journal size")
	}
	var state journal
	decoder := json.NewDecoder(strings.NewReader(string(data)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&state); err != nil {
		return nil, errors.New("invalid journal")
	}
	var extra any
	if decoder.Decode(&extra) != io.EOF || state.Schema != 1 ||
		!hashPattern.MatchString(state.Token) || state.Target != target ||
		!filepath.IsAbs(state.Work) || filepath.Dir(state.Work) != filepath.Dir(target) ||
		!strings.HasPrefix(filepath.Base(state.Work), ".rainlink-update-") ||
		state.Work != filepath.Clean(state.Work) {
		return nil, errors.New("invalid journal binding")
	}
	switch state.Phase {
	case phasePrepared, phaseSnapshot, phaseReplacing, phaseRollback, phaseAccepted, phaseCompleteOld, phaseCompleteNew:
	default:
		return nil, errors.New("unknown journal phase")
	}
	support, err := canonicalDirectory(state.Support)
	if err != nil || inside(target, support) || inside(support, target) {
		return nil, errors.New("invalid journal data directory")
	}
	if state.Work == target || inside(state.Work, support) || inside(support, state.Work) {
		return nil, errors.New("journal staging overlaps protected directories")
	}
	if present, err := exists(state.Work); err != nil {
		return nil, err
	} else if present {
		if _, err := canonicalDirectory(state.Work); err != nil {
			return nil, err
		}
	}
	for _, manifest := range []Manifest{state.Previous, state.Next} {
		encoded, err := json.Marshal(manifest)
		if err != nil {
			return nil, err
		}
		if _, err := parseManifest(encoded); err != nil {
			return nil, err
		}
	}
	if state.Previous.Schema != state.Next.Schema {
		return nil, errors.New("journal layouts differ")
	}
	if state.Previous.Schema == 2 && bootstrapFile(state.Previous) != bootstrapFile(state.Next) {
		return nil, errors.New("journal changes the recovery entry")
	}
	if state.Version != state.Next.Version && strings.TrimPrefix(state.Version, "v") != strings.TrimPrefix(state.Next.Version, "v") {
		return nil, errors.New("journal release differs")
	}
	if state.Phase != phasePrepared && state.Phase != phaseCompleteOld && !state.DataSaved {
		return nil, errors.New("journal snapshot missing")
	}
	seen := map[string]bool{}
	for _, entry := range state.Data {
		valid := false
		for _, name := range databaseFiles {
			valid = valid || entry.Path == name
		}
		if !valid || seen[entry.Path] || entry.Bytes < 0 || entry.Bytes > 2<<30 || !hashPattern.MatchString(entry.SHA256) {
			return nil, errors.New("invalid journal database snapshot")
		}
		seen[entry.Path] = true
	}
	transaction := &Transaction{request: Request{Target: target, Support: support, Version: state.Version},
		work: state.Work, stage: filepath.Join(state.Work, "staged"), backup: filepath.Join(state.Work, "previous"),
		health: filepath.Join(state.Work, "health"), marker: filepath.Join(target, MarkerName),
		token: state.Token, phase: state.Phase, previous: state.Previous, next: state.Next,
		dataSaved: state.DataSaved, dataManifest: state.Data, rename: os.Rename,
		dataBackup: filepath.Join(support, "update-backup-"+state.Token)}
	for _, entry := range state.Data {
		transaction.dataFiles = append(transaction.dataFiles, entry.Path)
	}
	if info, err := os.Lstat(transaction.marker); err == nil {
		if !info.Mode().IsRegular() || noReparse(transaction.marker) != nil {
			return nil, errors.New("invalid update marker")
		}
		marker, err := os.ReadFile(transaction.marker)
		var binding struct{ Token, Work string }
		if err != nil || len(marker) > 8192 || json.Unmarshal(marker, &binding) != nil || binding.Token != state.Token || binding.Work != state.Work {
			return nil, errors.New("update marker and journal differ")
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	return transaction, nil
}

func inspectFile(ctx context.Context, name string) (BundleFile, error) {
	if err := noReparse(name); err != nil {
		return BundleFile{}, err
	}
	file, err := os.Open(name)
	if err != nil {
		return BundleFile{}, err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil || !info.Mode().IsRegular() {
		return BundleFile{}, errors.New("invalid managed file")
	}
	hash := sha256.New()
	count, err := io.Copy(hash, &contextReader{ctx: ctx, reader: file})
	if err != nil || count != info.Size() {
		return BundleFile{}, errors.Join(errors.New("read managed file"), err)
	}
	return BundleFile{Path: filepath.Base(name), Bytes: count, SHA256: hex.EncodeToString(hash.Sum(nil))}, nil
}

func verifyFile(ctx context.Context, name string, expected BundleFile) error {
	actual, err := inspectFile(ctx, name)
	if err != nil {
		return err
	}
	if actual.Bytes != expected.Bytes || actual.SHA256 != expected.SHA256 {
		return errors.New("managed file digest differs")
	}
	return nil
}

func verifyRoot(ctx context.Context, directory, name string, manifest Manifest) error {
	if err := plainTree(filepath.Join(directory, name)); err != nil {
		return err
	}
	if name == ManifestName {
		actual, err := loadManifest(directory)
		if err != nil {
			return err
		}
		if !reflect.DeepEqual(actual, manifest) {
			return errors.New("installed manifest differs")
		}
		return nil
	}
	found := false
	for _, entry := range manifest.Files {
		root := strings.SplitN(entry.Path, "/", 2)[0]
		if strings.EqualFold(root, name) {
			found = true
			if err := verifyFile(ctx, filepath.Join(directory, filepath.FromSlash(entry.Path)), entry); err != nil {
				return err
			}
		}
	}
	if !found {
		return errors.New("unknown managed root")
	}
	return nil
}

func verifyInstallation(ctx context.Context, directory string, manifest Manifest) error {
	for _, name := range roots(manifest) {
		if err := verifyRoot(ctx, directory, name, manifest); err != nil {
			return fmt.Errorf("verify managed runtime: %w", err)
		}
	}
	return nil
}

func exists(name string) (bool, error) {
	_, err := os.Lstat(name)
	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	return err == nil, err
}

// restoreRuntime infers each atomic rename from verified source/destination
// files. Recovery remains valid if the process dies before recording a move.
func (transaction *Transaction) restoreRuntime(ctx context.Context) error {
	if transaction.previous.Schema == 2 {
		if err := verifyRoot(ctx, transaction.request.Target, "rainlink.exe", transaction.previous); err != nil {
			return err
		}
	}
	previous := map[string]bool{}
	for _, name := range replacementRoots(transaction.previous) {
		previous[strings.ToLower(name)] = true
	}
	for _, name := range replacementRoots(transaction.next) {
		target := filepath.Join(transaction.request.Target, name)
		staged := filepath.Join(transaction.stage, name)
		backup := filepath.Join(transaction.backup, name)
		inTarget, err := exists(target)
		if err != nil {
			return err
		}
		inStage, err := exists(staged)
		if err != nil {
			return err
		}
		inBackup, err := exists(backup)
		if err != nil {
			return err
		}
		if previous[strings.ToLower(name)] && !inBackup {
			// The old root was never moved, or a previous recovery restored it.
			if err := verifyRoot(ctx, transaction.request.Target, name, transaction.previous); err != nil {
				return err
			}
			continue
		}
		if inTarget {
			if inStage {
				return errors.New("recovery target conflicts with staged root")
			}
			if err := verifyRoot(ctx, transaction.request.Target, name, transaction.next); err != nil {
				return err
			}
			if err := transaction.rename(target, staged); err != nil {
				return fmt.Errorf("deactivate interrupted root: %w", err)
			}
		} else if !inStage {
			return errors.New("new runtime root is missing")
		}
	}
	for _, name := range replacementRoots(transaction.previous) {
		backup := filepath.Join(transaction.backup, name)
		target := filepath.Join(transaction.request.Target, name)
		inBackup, err := exists(backup)
		if err != nil {
			return err
		}
		if !inBackup {
			if err := verifyRoot(ctx, transaction.request.Target, name, transaction.previous); err != nil {
				return err
			}
			continue
		}
		if present, err := exists(target); err != nil || present {
			return errors.New("previous runtime destination is occupied")
		}
		if err := verifyRoot(ctx, transaction.backup, name, transaction.previous); err != nil {
			return err
		}
		if err := transaction.rename(backup, target); err != nil {
			return fmt.Errorf("restore interrupted root: %w", err)
		}
	}
	return verifyInstallation(ctx, transaction.request.Target, transaction.previous)
}

// Recover reconciles a durable transaction. The caller must hold the platform
// update lock and establish that no runtime process can still use these files.
// It never starts a program, kills a process, or accesses a network endpoint.
func Recover(ctx context.Context, target string) (Outcome, bool, error) {
	target, err := canonicalDirectory(target)
	if err != nil {
		return Outcome{}, false, err
	}
	present, err := exists(filepath.Join(target, JournalName))
	if err != nil {
		return Outcome{}, false, err
	}
	if !present {
		if marker, err := exists(filepath.Join(target, MarkerName)); err != nil || marker {
			return Outcome{}, false, errors.New("update journal is missing")
		}
		return Outcome{}, false, nil
	}
	transaction, err := readJournal(target)
	if err != nil {
		return Outcome{}, true, err
	}
	outcome := Outcome{Status: "interrupted-restored", Version: transaction.request.Version}
	if transaction.phase == phaseAccepted || transaction.phase == phaseCompleteNew {
		if err := verifyInstallation(ctx, target, transaction.next); err != nil {
			return outcome, true, err
		}
		outcome.Status = "installed"
		if err := transaction.receipt(outcome); err != nil {
			return outcome, true, err
		}
		return outcome, true, transaction.cleanCompleted(true)
	}
	if transaction.phase != phasePrepared && transaction.phase != phaseCompleteOld {
		if err := transaction.validateDataBackup(ctx); err != nil {
			return outcome, true, err
		}
		if err := transaction.saveJournal(phaseRollback, false); err != nil {
			return outcome, true, err
		}
		if err := transaction.restoreRuntime(ctx); err != nil {
			return outcome, true, err
		}
		if err := transaction.restoreData(ctx); err != nil {
			return outcome, true, err
		}
	} else if err := verifyInstallation(ctx, target, transaction.previous); err != nil {
		return outcome, true, err
	}
	if err := transaction.receipt(outcome); err != nil {
		return outcome, true, err
	}
	return outcome, true, transaction.cleanCompleted(false)
}

func (transaction *Transaction) validateDataBackup(ctx context.Context) error {
	if !transaction.dataSaved {
		return errors.New("database snapshot was not committed")
	}
	if _, err := canonicalDirectory(transaction.dataBackup); err != nil {
		return err
	}
	for _, entry := range transaction.dataManifest {
		if err := verifyFile(ctx, filepath.Join(transaction.dataBackup, entry.Path), entry); err != nil {
			return fmt.Errorf("database backup differs: %w", err)
		}
	}
	return nil
}

func (transaction *Transaction) cleanCompleted(keepNew bool) error {
	phase := phaseCompleteOld
	if keepNew {
		phase = phaseCompleteNew
	}
	if err := transaction.saveJournal(phase, false); err != nil {
		return err
	}
	// These exact directories were created for the bound token. Validate their
	// ancestors and contents before recursive deletion, including during retries.
	for _, directory := range []string{transaction.dataBackup, transaction.work} {
		if directory == "" {
			continue
		}
		present, err := exists(directory)
		if err != nil {
			return err
		}
		if !present {
			continue
		}
		if _, err := canonicalDirectory(directory); err != nil {
			return err
		}
		if err := plainTree(directory); err != nil {
			return err
		}
		if err := os.RemoveAll(directory); err != nil {
			return err
		}
	}
	for _, name := range []string{transaction.marker, filepath.Join(transaction.request.Target, JournalName)} {
		if err := os.Remove(name); err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
	}
	return nil
}
