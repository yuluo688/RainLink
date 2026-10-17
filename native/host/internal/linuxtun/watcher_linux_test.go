//go:build linux && !android

package linuxtun

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strconv"
	"syscall"
	"testing"
	"time"

	"golang.org/x/sys/unix"
	"rainlink.local/host/internal/coreprocess"
	"rainlink.local/host/internal/linuxnet"
	"rainlink.local/host/internal/linuxprocess"
)

type watchdogFixtureReport struct {
	Resources Specification          `json:"resources"`
	Owner     linuxprocess.Identity  `json:"owner"`
	Watchdog  linuxprocess.Identity  `json:"watchdog"`
	Core      *linuxprocess.Identity `json:"core,omitempty"`
}

func fixtureIdentity(t *testing.T, pid int) linuxprocess.Identity {
	t.Helper()
	identity, alive, err := linuxprocess.ReadIdentity(pid)
	if err != nil || !alive {
		t.Fatal("fixture process identity unavailable", err)
	}
	return identity
}

func fixtureWaitRules(t *testing.T, ctx context.Context, specification Specification) {
	t.Helper()
	expected, err := specification.ExpectedRules()
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	for {
		state, err := linuxnet.Read(ctx)
		if err != nil {
			t.Fatal(err)
		}
		matches := 0
		for _, rule := range expected {
			for _, current := range state.Rules {
				same, err := linuxnet.SameRule(rule, current)
				if err != nil {
					t.Fatal(err)
				}
				if same {
					matches++
				}
			}
		}
		if matches == len(expected) {
			return
		}
		select {
		case <-ctx.Done():
			t.Fatal("fixture did not install all managed rules", matches, ctx.Err())
		case <-time.After(20 * time.Millisecond):
		}
	}
}

func TestLinuxTUNWatchdogOwnerFixture(t *testing.T) {
	if os.Getenv("RAINLINK_TEST_TUN_WATCHDOG") != "owner" {
		t.Skip("fixture child only")
	}
	requireRootFixture(t)
	core := os.Getenv("RAINLINK_TEST_CORE_PATH")
	if !coreprocess.Trusted(core) {
		t.Fatal("requires the locked Linux core")
	}
	ctx, cancel := context.WithTimeout(t.Context(), 20*time.Second)
	defer cancel()
	owner := fixtureIdentity(t, os.Getpid())
	readyReader, readyWriter, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer readyReader.Close()
	watchdog := exec.Command(filepath.Join(filepath.Dir(core), "rainlink-host"), "watch-tun",
		strconv.Itoa(owner.PID), strconv.FormatUint(owner.Start, 10), owner.Boot)
	watchdog.Env = []string{"PATH=", "LANG=C"}
	watchdog.Stderr = os.Stderr
	watchdog.ExtraFiles = []*os.File{readyWriter}
	// It must survive the guardian, including the guardian's process session.
	watchdog.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err = watchdog.Start(); err != nil {
		_ = readyWriter.Close()
		t.Fatal(err)
	}
	watchdogDone := make(chan error, 1)
	go func() { watchdogDone <- watchdog.Wait() }()
	t.Cleanup(func() {
		_ = watchdog.Process.Kill()
		<-watchdogDone
	})
	if err = readyWriter.Close(); err != nil {
		t.Fatal(err)
	}
	if err = readyReader.SetReadDeadline(time.Now().Add(3 * time.Second)); err != nil {
		t.Fatal(err)
	}
	var ready [1]byte
	if _, err = io.ReadFull(readyReader, ready[:]); err != nil || ready[0] != 1 {
		t.Fatal("watchdog did not acknowledge its pinned parent before capture", err)
	}
	controller, err := New()
	if err != nil {
		t.Fatal(err)
	}
	lease, err := controller.Acquire(ctx, "rl-watch-test")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = lease.Close() })
	report := watchdogFixtureReport{Resources: lease.Specification(), Owner: owner, Watchdog: fixtureIdentity(t, watchdog.Process.Pid)}
	scenario := os.Getenv("RAINLINK_TEST_TUN_WATCHDOG_SCENARIO")
	if scenario != "prepared" {
		command := exec.CommandContext(ctx, core, "run", "-c", "stdin")
		command.Env = []string{"PATH=", "LANG=C"}
		var resistantReadyReader, resistantReadyWriter *os.File
		if scenario == "term-resistant" {
			// Fixture only: an ignored SIGTERM survives exec. The watchdog must
			// escalate using the same pidfd, without relying on Pdeathsig.
			resistantReadyReader, resistantReadyWriter, err = os.Pipe()
			if err != nil {
				t.Fatal(err)
			}
			defer resistantReadyReader.Close()
			defer resistantReadyWriter.Close()
			command = exec.CommandContext(ctx, "/bin/sh", "-c", "trap '' TERM; printf r >&3; exec /bin/sleep 30")
			command.Env = []string{"PATH=", "LANG=C"}
			command.ExtraFiles = []*os.File{resistantReadyWriter}
		}
		input, err := command.StdinPipe()
		if err != nil {
			t.Fatal(err)
		}
		defer input.Close()
		if err = command.Start(); err != nil {
			t.Fatal(err)
		}
		done := make(chan error, 1)
		go func() { done <- command.Wait() }()
		t.Cleanup(func() {
			_ = command.Process.Kill()
			<-done
		})
		if resistantReadyReader != nil {
			if err = resistantReadyWriter.Close(); err != nil {
				t.Fatal(err)
			}
			if err = resistantReadyReader.SetReadDeadline(time.Now().Add(time.Second)); err != nil {
				t.Fatal(err)
			}
			if _, err = io.ReadFull(resistantReadyReader, ready[:]); err != nil || ready[0] != 'r' {
				t.Fatal("fixture did not confirm its ignored termination signal", err)
			}
		}
		identity := fixtureIdentity(t, command.Process.Pid)
		report.Core = &identity
		if err = lease.BindCore(ctx, identity.PID); err != nil {
			t.Fatal(err)
		}
		if scenario != "term-resistant" {
			if err = json.NewEncoder(input).Encode(managedCoreConfiguration(report.Resources)); err != nil {
				t.Fatal(err)
			}
		}
		if err = input.Close(); err != nil {
			t.Fatal(err)
		}
		if scenario != "term-resistant" {
			fixtureWaitRules(t, ctx, report.Resources)
		}
	}
	output := os.NewFile(3, "watchdog-fixture-report")
	if output == nil {
		t.Fatal("fixture report pipe missing")
	}
	if err = json.NewEncoder(output).Encode(report); err != nil {
		t.Fatal(err)
	}
	if err = output.Close(); err != nil {
		t.Fatal(err)
	}
	// The outer fixture SIGKILLs this process. No manual recovery runs here.
	<-ctx.Done()
	t.Fatal("outer fixture did not end the guardian", ctx.Err())
}

func TestIsolatedTUNWatchdogRecoversGuardianExit(t *testing.T) {
	requireRootFixture(t)
	for _, scenario := range []string{"core-live", "core-dead", "prepared", "term-resistant"} {
		t.Run(scenario, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(t.Context(), 12*time.Second)
			defer cancel()
			before, err := linuxnet.Read(ctx)
			if err != nil {
				t.Fatal(err)
			}
			executable, err := os.Executable()
			if err != nil {
				t.Fatal(err)
			}
			reader, writer, err := os.Pipe()
			if err != nil {
				t.Fatal(err)
			}
			defer reader.Close()
			owner := exec.CommandContext(ctx, executable, "-test.run=^TestLinuxTUNWatchdogOwnerFixture$", "-test.timeout=25s")
			owner.Env = append(os.Environ(), "RAINLINK_TEST_TUN_WATCHDOG=owner", "RAINLINK_TEST_TUN_WATCHDOG_SCENARIO="+scenario)
			owner.ExtraFiles = []*os.File{writer}
			var ownerOutput bytes.Buffer
			owner.Stdout, owner.Stderr = &ownerOutput, &ownerOutput
			if err = owner.Start(); err != nil {
				_ = writer.Close()
				t.Fatal(err)
			}
			done := make(chan error, 1)
			go func() { done <- owner.Wait() }()
			reaped := false
			t.Cleanup(func() {
				if !reaped {
					_ = owner.Process.Kill()
					<-done
				}
				if t.Failed() {
					t.Log("guardian and watchdog fixture output:", ownerOutput.String())
				}
			})
			if err = writer.Close(); err != nil {
				t.Fatal(err)
			}
			if err = reader.SetReadDeadline(time.Now().Add(6 * time.Second)); err != nil {
				t.Fatal(err)
			}
			var report watchdogFixtureReport
			if err = json.NewDecoder(io.LimitReader(reader, 4096)).Decode(&report); err != nil {
				_ = owner.Process.Kill()
				<-done
				reaped = true
				t.Fatal("guardian fixture did not become ready", err, ownerOutput.String())
			}
			if report.Owner != fixtureIdentity(t, owner.Process.Pid) {
				t.Fatal("guardian report identity mismatch")
			}
			watchdog, err := linuxprocess.Open(report.Watchdog)
			if err != nil {
				t.Fatal(err)
			}
			defer watchdog.Close()
			controller, err := New()
			if err != nil {
				t.Fatal(err)
			}
			if err = controller.RecoverOrphan(ctx, report.Owner); !errors.Is(err, ErrOwned) {
				t.Fatal("orphan recovery touched a live guardian", err)
			}
			ready, err := linuxnet.Read(ctx)
			if err != nil {
				t.Fatal(err)
			}
			if scenario == "core-dead" {
				core, err := linuxprocess.Open(*report.Core)
				if err != nil {
					t.Fatal(err)
				}
				if err = core.Signal(unix.SIGKILL); err != nil {
					t.Fatal(err)
				}
				if err = core.Wait(ctx); err != nil {
					t.Fatal(err)
				}
				if err = core.Close(); err != nil {
					t.Fatal(err)
				}
			}
			if err = owner.Process.Kill(); err != nil {
				t.Fatal(err)
			}
			<-done
			reaped = true
			if err = watchdog.Wait(ctx); err != nil {
				t.Fatal("independent watchdog did not exit after recovery", err)
			}
			after, err := linuxnet.Read(ctx)
			if err != nil || !reflect.DeepEqual(before, after) {
				t.Fatal("automatic watchdog recovery did not restore exact network state", err)
			}
			if report.Core != nil {
				if alive, err := linuxprocess.Alive(*report.Core); err != nil || alive {
					t.Fatal("watchdog left its orphan core alive", err)
				}
			}
			if _, err = os.Stat(filepath.Join(runtimeDirectory, journalName)); !errors.Is(err, os.ErrNotExist) {
				journal, readErr := os.ReadFile(filepath.Join(runtimeDirectory, journalName))
				t.Log("retained watchdog resource journal:", string(journal), readErr)
				t.Fatal("watchdog retained a recovered journal", err)
			}
			if err = controller.RecoverOrphan(ctx, report.Owner); err != nil {
				t.Fatal("empty orphan recovery is not idempotent", err)
			}
			if directory := os.Getenv("RAINLINK_TEST_NETWORK_EVIDENCE_DIR"); directory != "" {
				data, err := json.MarshalIndent(map[string]any{"scenario": scenario, "report": report,
					"before": before, "ready": ready, "recovered": after, "automatic": true}, "", "  ")
				if err != nil {
					t.Fatal(err)
				}
				if err = os.WriteFile(filepath.Join(directory, "watchdog-"+scenario+".json"), append(data, '\n'), 0600); err != nil {
					t.Fatal(err)
				}
			}
		})
	}
}

func TestWatchdogRecoveryOwnershipCancellationAndStaleCore(t *testing.T) {
	controller, network := testController(t)
	lease := acquire(t, controller)
	core := coreChild(t)
	if err := lease.BindCore(t.Context(), core.Process.Pid); err != nil {
		t.Fatal(err)
	}
	assertPreserved := func(t *testing.T, owner linuxprocess.Identity, ctx context.Context, expected error) {
		t.Helper()
		before, err := lease.directory.Read(journalName, journalLimit)
		if err != nil {
			t.Fatal(err)
		}
		if err = controller.recoverOrphanLocked(ctx, lease.directory, owner); !errors.Is(err, expected) {
			t.Fatal("unexpected ownership failure", err)
		}
		after, err := lease.directory.Read(journalName, journalLimit)
		if err != nil || !bytes.Equal(before, after) || network.deletions != 0 {
			t.Fatal("rejected watchdog recovery changed its journal or policy", err)
		}
		if alive, err := linuxprocess.Alive(*lease.record.Core); err != nil || !alive {
			t.Fatal("rejected watchdog recovery signaled the live core", err)
		}
	}
	t.Run("live-owner", func(t *testing.T) {
		assertPreserved(t, lease.record.Owner, t.Context(), ErrOwned)
	})
	t.Run("later-owner", func(t *testing.T) {
		staleOwner := lease.record.Owner
		staleOwner.Start++
		assertPreserved(t, staleOwner, t.Context(), ErrOwned)
	})
	oldOwner := coreChild(t)
	deadIdentity := fixtureIdentity(t, oldOwner.Process.Pid)
	stopChild(t, oldOwner)
	lease.record.Owner = deadIdentity
	namespace := lease.record.Namespace
	lease.record.Namespace = "net:[1]"
	if err := writeJournal(lease.directory, lease.record, false); err != nil {
		t.Fatal(err)
	}
	t.Run("different-namespace", func(t *testing.T) {
		assertPreserved(t, deadIdentity, t.Context(), ErrNamespace)
	})
	lease.record.Namespace = namespace
	if err := writeJournal(lease.directory, lease.record, false); err != nil {
		t.Fatal(err)
	}
	t.Run("cancelled", func(t *testing.T) {
		ctx, cancel := context.WithCancel(t.Context())
		cancel()
		assertPreserved(t, deadIdentity, ctx, context.Canceled)
	})
	t.Run("reused-core-pid", func(t *testing.T) {
		identity := *lease.record.Core
		lease.record.Core.Start++
		if err := writeJournal(lease.directory, lease.record, false); err != nil {
			t.Fatal(err)
		}
		var err error
		network.state.Rules, err = lease.record.Resources.ExpectedRules()
		if err != nil {
			t.Fatal(err)
		}
		if err = controller.recoverOrphanLocked(t.Context(), lease.directory, deadIdentity); err != nil {
			t.Fatal("stale core identity prevented exact resource recovery", err)
		}
		if len(network.state.Rules) != 0 || network.deletions != 16 {
			t.Fatal("stale core's rules were not recovered")
		}
		if alive, err := linuxprocess.Alive(identity); err != nil || !alive {
			t.Fatal("watchdog signaled the different owner of a reused PID", err)
		}
		lease.restored = true
	})
}
