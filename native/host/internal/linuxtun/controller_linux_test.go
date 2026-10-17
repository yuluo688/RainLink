//go:build linux && !android

package linuxtun

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"golang.org/x/sys/unix"
	"rainlink.local/host/internal/linuxnet"
	"rainlink.local/host/internal/linuxprocess"
	"rainlink.local/host/internal/privatefs"
)

type fakeNetwork struct {
	state       linuxnet.State
	readError   error
	deleteError error
	deletions   int
	keepRules   bool
	onRead      func()
}

func (network *fakeNetwork) read(ctx context.Context) (linuxnet.State, error) {
	if network.onRead != nil {
		network.onRead()
	}
	if err := ctx.Err(); err != nil {
		return linuxnet.State{}, err
	}
	return network.state, network.readError
}

func (network *fakeNetwork) deleteRule(ctx context.Context, rule linuxnet.Rule) (bool, error) {
	if err := ctx.Err(); err != nil {
		return false, err
	}
	network.deletions++
	if network.deleteError != nil {
		return false, network.deleteError
	}
	for index, current := range network.state.Rules {
		same, err := linuxnet.SameRule(rule, current)
		if err != nil {
			return false, err
		}
		if same {
			if !network.keepRules {
				network.state.Rules = append(network.state.Rules[:index], network.state.Rules[index+1:]...)
			}
			return true, nil
		}
	}
	return false, nil
}

func testController(t *testing.T) (*Controller, *fakeNetwork) {
	t.Helper()
	network := &fakeNetwork{}
	return &Controller{directory: filepath.Join(t.TempDir(), "state"), network: network}, network
}

func acquire(t *testing.T, controller *Controller) *Lease {
	t.Helper()
	lease, err := controller.Acquire(t.Context(), "rl-unit")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if !lease.closed {
			_ = lease.Close()
		}
	})
	return lease
}

func coreChild(t *testing.T) *exec.Cmd {
	t.Helper()
	child := exec.Command("/bin/sleep", "30")
	if err := child.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if child.ProcessState == nil {
			_ = child.Process.Kill()
			_ = child.Wait()
		}
	})
	return child
}

func stopChild(t *testing.T, child *exec.Cmd) {
	t.Helper()
	if err := child.Process.Kill(); err != nil {
		t.Fatal(err)
	}
	_ = child.Wait()
}

func TestControllerRequiresPermissionHelper(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("ordinary-user permission boundary")
	}
	if _, err := New(); err == nil {
		t.Fatal("ordinary GUI process could create the root controller")
	}
}

func TestServiceExitSkipsOtherLiveSessionWithoutClaimingIdle(t *testing.T) {
	controller, network := testController(t)
	lease := acquire(t, controller)
	path := filepath.Join(controller.directory, journalName)
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if skipped, err := controller.RecoverAfterServiceExit(t.Context()); err != nil || !skipped {
		t.Fatal("probe exit did not skip active owner", skipped, err)
	}
	if err := controller.Recover(t.Context()); !errors.Is(err, ErrOwned) {
		t.Fatal("strict install recovery stopped enforcing ownership", err)
	}
	if err := controller.ConfirmIdle(t.Context()); !errors.Is(err, ErrOwned) {
		t.Fatal("active owner was reported idle", err)
	}
	if err := lease.Close(); !errors.Is(err, ErrPending) {
		t.Fatal(err)
	}
	if skipped, err := controller.RecoverAfterServiceExit(t.Context()); err != nil || !skipped {
		t.Fatal("live journal owner was not preserved", skipped, err)
	}
	after, err := os.ReadFile(path)
	if err != nil || !bytes.Equal(before, after) || network.deletions != 0 {
		t.Fatal("probe exit changed another session", err)
	}
	if err := os.WriteFile(path, []byte("invalid"), 0600); err != nil {
		t.Fatal(err)
	}
	if skipped, err := controller.RecoverAfterServiceExit(t.Context()); err == nil || skipped {
		t.Fatal("invalid journal was hidden as a skipped owner", skipped, err)
	}
}

func TestIdleConfirmationNeverRecoversOrDiscardsPendingJournal(t *testing.T) {
	controller, network := testController(t)
	if err := controller.ConfirmIdle(t.Context()); err != nil {
		t.Fatal("unused controller should confirm idle", err)
	}
	lease := acquire(t, controller)
	if err := controller.ConfirmIdle(t.Context()); !errors.Is(err, ErrOwned) {
		t.Fatal("a live lease must not report idle", err)
	}
	path := filepath.Join(controller.directory, journalName)
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := lease.Close(); !errors.Is(err, ErrPending) {
		t.Fatal(err)
	}
	if err := controller.ConfirmIdle(t.Context()); !errors.Is(err, ErrPending) {
		t.Fatal("an unlocked pending journal must not report idle", err)
	}
	after, err := os.ReadFile(path)
	if err != nil || !bytes.Equal(before, after) || network.deletions != 0 {
		t.Fatal("read-only confirmation mutated recovery or the network", err)
	}
	if err = os.WriteFile(path, []byte("invalid-fixture-journal"), 0600); err != nil {
		t.Fatal(err)
	}
	if err = controller.ConfirmIdle(t.Context()); err == nil {
		t.Fatal("invalid recovery state must not report idle")
	}
}

func TestLeaseJournalWriteFailureAndCancelledBind(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("requires ordinary-user filesystem permissions")
	}
	controller, network := testController(t)
	network.onRead = func() {
		if err := os.Chmod(controller.directory, 0500); err != nil {
			t.Error(err)
		}
	}
	t.Cleanup(func() { _ = os.Chmod(controller.directory, 0700) })
	if lease, err := controller.Acquire(t.Context(), "rl-unit"); err == nil || lease != nil {
		t.Fatal("failed intent write returned a usable lease", err)
	}
	if _, err := os.Stat(filepath.Join(controller.directory, journalName)); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("failed intent write left a journal", err)
	}
	if err := os.Chmod(controller.directory, 0700); err != nil {
		t.Fatal(err)
	}
	network.onRead = nil
	lease := acquire(t, controller)
	child := coreChild(t)
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	if err := lease.BindCore(ctx, child.Process.Pid); !errors.Is(err, context.Canceled) {
		t.Fatal("cancelled bind succeeded", err)
	}
	record, err := readJournal(lease.directory)
	if err != nil || record.Core != nil {
		t.Fatal("cancelled bind changed durable ownership", err)
	}
	if err = os.Chmod(controller.directory, 0500); err != nil {
		t.Fatal(err)
	}
	if err = lease.BindCore(t.Context(), child.Process.Pid); err == nil {
		t.Fatal("failed binding write was reported as durable")
	}
	record, err = readJournal(lease.directory)
	if err != nil || record.Core != nil {
		t.Fatal("failed binding write replaced prepared intent", err)
	}
	if err = os.Chmod(controller.directory, 0700); err != nil {
		t.Fatal(err)
	}
	stopChild(t, child)
	if err = lease.Restore(t.Context()); err != nil {
		t.Fatal("failed binding could not retire prepared intent", err)
	}
	if err = lease.Close(); err != nil {
		t.Fatal(err)
	}
	if network.deletions != 0 {
		t.Fatal("core without a committed binding changed network resources")
	}
}

func TestLeasePreparedIntentCancellationAndExclusiveLock(t *testing.T) {
	controller, network := testController(t)
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	if _, err := controller.Acquire(ctx, "rl-unit"); !errors.Is(err, context.Canceled) {
		t.Fatal("cancelled acquire succeeded", err)
	}
	ctx, cancel = context.WithCancel(t.Context())
	defer cancel()
	network.onRead = cancel
	if _, err := controller.Acquire(ctx, "rl-unit"); !errors.Is(err, context.Canceled) {
		t.Fatal("cancel during observation succeeded", err)
	}
	network.onRead = nil
	lease := acquire(t, controller)
	if _, err := controller.Acquire(t.Context(), "rl-other"); !errors.Is(err, ErrOwned) {
		t.Fatal("simultaneous lease accepted", err)
	}
	if err := controller.Recover(t.Context()); !errors.Is(err, ErrOwned) {
		t.Fatal("recovery entered an active lease", err)
	}
	// Even an identical later network object must be preserved: this intent
	// never released configuration to a core.
	network.state.Rules, _ = lease.Specification().ExpectedRules()
	before := append([]linuxnet.Rule(nil), network.state.Rules...)
	if err := lease.Restore(t.Context()); err != nil {
		t.Fatal(err)
	}
	if network.deletions != 0 || !reflect.DeepEqual(before, network.state.Rules) {
		t.Fatal("prepared intent deleted network state")
	}
	if err := lease.Restore(t.Context()); err != nil {
		t.Fatal("restore is not idempotent", err)
	}
	if err := lease.Close(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(controller.directory, journalName)); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("restored journal retained", err)
	}
}

func TestLeaseStopsLiveCoreAndRetriesIncompleteRecovery(t *testing.T) {
	controller, network := testController(t)
	lease := acquire(t, controller)
	if err := lease.BindCore(t.Context(), os.Getpid()); err == nil {
		t.Fatal("guardian bound as its own core")
	}
	child := coreChild(t)
	if err := lease.BindCore(t.Context(), child.Process.Pid); err != nil {
		t.Fatal(err)
	}
	if err := lease.BindCore(t.Context(), child.Process.Pid); err == nil {
		t.Fatal("core rebound")
	}
	if err := lease.Restore(t.Context()); !errors.Is(err, ErrCoreAlive) || network.deletions != 0 {
		t.Fatal("live core allowed policy cleanup", err)
	}
	stopChild(t, child)
	network.state.Rules, _ = lease.Specification().ExpectedRules()
	foreign := network.state.Rules[0]
	foreign.Table++
	foreign.Attributes = append([]linuxnet.Attribute(nil), foreign.Attributes...)
	foreign.Attributes[1] = integerAttribute(unix.FRA_TABLE, foreign.Table)
	network.state.Rules = append(network.state.Rules, foreign)
	network.state.Routes = []linuxnet.Route{{Table: lease.Specification().Table, Protocol: 99}}
	network.state.Links = []linuxnet.Link{{Name: lease.Specification().Name}}
	if err := lease.Restore(t.Context()); !errors.Is(err, ErrPending) || network.deletions != 0 {
		t.Fatal("reused interface permitted cleanup", err)
	}
	network.state.Links = nil
	network.deleteError = linuxnet.ErrAmbiguousRule
	if err := lease.Restore(t.Context()); !errors.Is(err, linuxnet.ErrAmbiguousRule) {
		t.Fatal("ambiguous failure swallowed", err)
	}
	if _, err := os.Stat(filepath.Join(controller.directory, journalName)); err != nil {
		t.Fatal("failed recovery retired journal", err)
	}
	network.deleteError = nil
	network.keepRules = true
	if err := lease.Restore(t.Context()); !errors.Is(err, ErrPending) {
		t.Fatal("unverified deletion became success", err)
	}
	network.keepRules = false
	if err := lease.Restore(t.Context()); err != nil {
		t.Fatal("retry failed", err)
	}
	if len(network.state.Rules) != 1 || len(network.state.Routes) != 1 {
		t.Fatal("foreign rule or route deleted")
	}
	if same, err := linuxnet.SameRule(foreign, network.state.Rules[0]); err != nil || !same {
		t.Fatal("foreign identity changed", err)
	}
	if err := lease.Close(); err != nil {
		t.Fatal(err)
	}
}

func TestLeasePendingCloseAndChangedOwnership(t *testing.T) {
	controller, network := testController(t)
	lease := acquire(t, controller)
	record := *lease.record
	record.Nonce = strings.Repeat("1", 32)
	if err := writeJournal(lease.directory, &record, false); err != nil {
		t.Fatal(err)
	}
	if err := lease.Restore(t.Context()); err == nil {
		t.Fatal("changed nonce authorized recovery")
	}
	if err := lease.Close(); !errors.Is(err, ErrPending) {
		t.Fatal("pending cleanup became successful close", err)
	}
	if err := lease.Close(); err != nil {
		t.Fatal("repeated close failed", err)
	}
	if err := controller.Recover(t.Context()); !errors.Is(err, ErrOwned) {
		t.Fatal("live journal owner was ignored", err)
	}
	if network.deletions != 0 {
		t.Fatal("changed ownership deleted rules")
	}
}

func testRecord(t *testing.T) journal {
	t.Helper()
	owner, alive, err := linuxprocess.ReadIdentity(os.Getpid())
	if err != nil || !alive {
		t.Fatal(err)
	}
	namespace, err := linuxprocess.NetworkNamespace(os.Getpid())
	if err != nil {
		t.Fatal(err)
	}
	return journal{Version: journalVersion, Nonce: strings.Repeat("a", 32), Namespace: namespace, Owner: owner,
		Resources: Specification{Name: "rl-unit", Table: tablePoolStart, Priority: priorityPoolStart}}
}

func TestRecoveryChecksOwnerBootAndNamespaceBeforeNetwork(t *testing.T) {
	for _, scenario := range []string{"live-owner", "dead-prepared", "reboot", "namespace", "live-core", "dead-core"} {
		t.Run(scenario, func(t *testing.T) {
			controller, network := testController(t)
			directory, err := privatefs.Open(controller.directory)
			if err != nil {
				t.Fatal(err)
			}
			defer directory.Close()
			record := testRecord(t)
			var want error
			switch scenario {
			case "live-owner":
				want = ErrOwned
			case "dead-prepared":
				record.Owner.Start++
			case "reboot":
				record.Owner.Boot = "00000000-0000-0000-0000-000000000001"
			case "namespace":
				record.Owner.Start++
				record.Namespace = "net:[1]"
				want = ErrNamespace
			case "live-core", "dead-core":
				child := coreChild(t)
				identity, alive, err := linuxprocess.ReadIdentity(child.Process.Pid)
				if err != nil || !alive {
					t.Fatal(err)
				}
				record.Core = &identity
				record.Owner.Start++
				if scenario == "live-core" {
					want = ErrCoreAlive
				} else {
					stopChild(t, child)
				}
			}
			network.state.Rules, _ = record.Resources.ExpectedRules()
			if err = writeJournal(directory, &record, true); err != nil {
				t.Fatal(err)
			}
			err = controller.Recover(t.Context())
			if want != nil && !errors.Is(err, want) || want == nil && err != nil {
				t.Fatal("incorrect recovery result", scenario, err)
			}
			if scenario == "dead-core" {
				if len(network.state.Rules) != 0 || network.deletions != 16 {
					t.Fatal("dead core rules not recovered")
				}
			} else if network.deletions != 0 {
				t.Fatal("uncertain or prepared owner changed the network")
			}
			_, statErr := os.Stat(filepath.Join(controller.directory, journalName))
			if want == nil && !errors.Is(statErr, os.ErrNotExist) || want != nil && statErr != nil {
				t.Fatal("wrong journal retirement", statErr)
			}
		})
	}
}

func TestRecoveryPreservesLegacyUntaggedRuleIdentity(t *testing.T) {
	controller, network := testController(t)
	directory, err := privatefs.Open(controller.directory)
	if err != nil {
		t.Fatal(err)
	}
	defer directory.Close()
	record := testRecord(t)
	record.Version = 1
	record.Owner.Start++
	child := coreChild(t)
	identity, alive, err := linuxprocess.ReadIdentity(child.Process.Pid)
	if err != nil || !alive {
		t.Fatal(err)
	}
	record.Core = &identity
	stopChild(t, child)
	legacy, err := record.Resources.expectedRules(0)
	if err != nil {
		t.Fatal(err)
	}
	newResources := record.Resources
	newResources.Priority += priorityStride
	newResources.Table++
	newResources.Name = "rl-new"
	tagged, err := newResources.ExpectedRules()
	if err != nil {
		t.Fatal(err)
	}
	network.state.Rules = append(legacy, tagged...)
	if err = writeJournal(directory, &record, true); err != nil {
		t.Fatal(err)
	}
	if err = controller.Recover(t.Context()); err != nil {
		t.Fatal(err)
	}
	if len(network.state.Rules) != 16 {
		t.Fatal("legacy recovery deleted new managed rules")
	}
	for index, current := range network.state.Rules {
		if same, err := linuxnet.SameRule(tagged[index], current); err != nil || !same {
			t.Fatal("new managed rule was changed", err)
		}
	}
}

func TestJournalRejectsCorruptionAmbiguityOversizeAndLinks(t *testing.T) {
	for _, scenario := range []string{"checksum", "duplicate", "unknown-field", "oversize", "symlink", "mode", "invalid-identity", "invalid-spec", "bound-guardian", "noncanonical"} {
		t.Run(scenario, func(t *testing.T) {
			controller, network := testController(t)
			directory, err := privatefs.Open(controller.directory)
			if err != nil {
				t.Fatal(err)
			}
			defer directory.Close()
			record := testRecord(t)
			record.Owner.Start++
			switch scenario {
			case "invalid-identity":
				record.Owner.Start = 0
			case "invalid-spec":
				record.Resources.Name = "eth0"
			case "bound-guardian":
				record.Core = &record.Owner
			}
			if err = writeJournal(directory, &record, true); err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(controller.directory, journalName)
			data, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			switch scenario {
			case "checksum":
				data = bytes.Replace(data, []byte(record.Nonce), []byte(strings.Repeat("b", 32)), 1)
			case "duplicate":
				data = append([]byte(`{"version":1,`), data[1:]...)
			case "unknown-field":
				data = append([]byte(`{"extra":1,`), data[1:]...)
			case "oversize":
				data = bytes.Repeat([]byte(" "), journalLimit+1)
			case "noncanonical":
				var value any
				_ = json.Unmarshal(data, &value)
				data, _ = json.MarshalIndent(value, "", "  ")
			case "mode":
				if err = os.Chmod(path, 0644); err != nil {
					t.Fatal(err)
				}
			case "symlink":
				other := filepath.Join(controller.directory, "target")
				if err = os.Rename(path, other); err != nil {
					t.Fatal(err)
				}
				if err = os.Symlink(other, path); err != nil {
					t.Fatal(err)
				}
			}
			if scenario != "mode" && scenario != "symlink" {
				if err = os.WriteFile(path, data, 0600); err != nil {
					t.Fatal(err)
				}
			}
			if err = controller.Recover(t.Context()); err == nil {
				t.Fatal("unsafe journal accepted", scenario)
			}
			if network.deletions != 0 {
				t.Fatal("invalid journal changed the network")
			}
			if _, err = os.Lstat(path); err != nil {
				t.Fatal("invalid journal silently discarded", err)
			}
		})
	}
}

func TestAllocatorReservesCompleteBlocksAndEveryTableReference(t *testing.T) {
	state := linuxnet.State{}
	for index := uint32(0); index < tablePoolSize-1; index++ {
		if index%2 == 0 {
			state.Routes = append(state.Routes, linuxnet.Route{Table: tablePoolStart + index})
		} else {
			state.Rules = append(state.Rules, linuxnet.Rule{Table: tablePoolStart + index})
		}
	}
	for index := uint32(0); index < priorityPoolSize-1; index++ {
		priority := uint32(priorityPoolStart) + index*priorityStride + RuleSpan - 1
		if index%2 == 0 {
			state.Rules = append(state.Rules, linuxnet.Rule{Priority: priority})
		} else {
			state.Rules = append(state.Rules, linuxnet.Rule{Attributes: []linuxnet.Attribute{integerAttribute(unix.FRA_GOTO, priority)}})
		}
	}
	specification, err := chooseResources(state, "rl-free")
	if err != nil || specification.Table != tablePoolStart+tablePoolSize-1 || specification.Priority != priorityPoolStart+(priorityPoolSize-1)*priorityStride {
		t.Fatal("used table or priority tail reused", specification, err)
	}
	state.Rules = append(state.Rules, linuxnet.Rule{Priority: specification.Priority + 5})
	if _, err = chooseResources(state, "rl-free"); err == nil {
		t.Fatal("priority pool exhaustion ignored")
	}
	state.Rules = state.Rules[:len(state.Rules)-1]
	state.Routes = append(state.Routes, linuxnet.Route{Table: specification.Table})
	if _, err = chooseResources(state, "rl-free"); err == nil {
		t.Fatal("table pool exhaustion ignored")
	}
	if _, err = chooseResources(linuxnet.State{Links: []linuxnet.Link{{Name: "rl-free"}}}, "rl-free"); err == nil {
		t.Fatal("existing interface reused")
	}
	if _, err = chooseResources(linuxnet.State{Rules: []linuxnet.Rule{{Attributes: []linuxnet.Attribute{{Type: unix.FRA_GOTO, Value: []byte{1}}}}}}, "rl-free"); err == nil {
		t.Fatal("invalid goto reference ignored")
	}
}
