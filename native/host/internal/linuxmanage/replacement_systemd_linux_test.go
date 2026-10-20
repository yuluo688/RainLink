//go:build linux && !android

package linuxmanage

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"

	"golang.org/x/sys/unix"
	"rainlink.local/host/internal/linuxinstall"
)

const installedHost = "/usr/libexec/rainlink/rainlink-host"
const installedCore = "/usr/libexec/rainlink/sing-box"
const installationState = "/var/lib/rainlink/tun-install"

// fanotify holds a real core-file open after the new host has been installed.
// The production broker, pkexec, root worker and installer have no test hook.
func TestRealSystemdBrokerCancellationDuringReplacement(t *testing.T) {
	if os.Getenv("RAINLINK_TEST_REAL_MANAGEMENT") != "disposable-vm" {
		t.Skip("requires disposable systemd/polkit VM with fanotify permissions")
	}
	if os.Geteuid() != 0 {
		t.Fatal("VM controller must be root")
	}
	if data, err := os.ReadFile("/proc/1/comm"); err != nil || strings.TrimSpace(string(data)) != "systemd" {
		t.Fatal("requires real systemd", err)
	}
	const rulePath = "/etc/polkit-1/rules.d/42-rainlink-replacement-qa.rules"
	for _, path := range []string{rulePath, installedHost} {
		if _, err := os.Lstat(path); !os.IsNotExist(err) {
			t.Fatal("requires absent VM policy/service", path, err)
		}
	}
	ctx, cancel := context.WithTimeout(t.Context(), 8*time.Minute)
	defer cancel()
	host := filepath.Join(filepath.Dir(os.Args[0]), "rainlink-host")
	previous := filepath.Join(filepath.Dir(host), "previous", "rainlink-host")
	currentHash := replacementDigest(t, host)
	previousHash := replacementDigest(t, previous)
	if currentHash == previousHash {
		t.Fatal("requires two different valid host builds")
	}
	run := func(t *testing.T, parent context.Context, program string, args ...string) {
		t.Helper()
		commandCtx, stop := context.WithTimeout(parent, time.Minute)
		defer stop()
		if data, err := exec.CommandContext(commandCtx, program, args...).CombinedOutput(); err != nil {
			t.Fatalf("VM command %s failed: %v %s", filepath.Base(program), err, data)
		}
	}
	policy := "polkit.addRule(function(action, subject) {\n" +
		"  var program = action.lookup('program') || '';\n" +
		"  if (action.id === 'org.freedesktop.policykit.exec' && subject.user === 'nobody' &&\n" +
		"      /^\\/proc\\/[0-9]+\\/exe$/.test(program)) return polkit.Result.YES;\n});\n"
	if err := os.WriteFile(rulePath, []byte(policy), 0644); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		run(t, context.Background(), host, "uninstall-tun")
		if err := os.Remove(rulePath); err != nil {
			t.Error(err)
		}
		run(t, context.Background(), "/usr/bin/systemctl", "restart", "polkit.service")
	})
	run(t, ctx, "/usr/bin/systemctl", "restart", "polkit.service")
	run(t, ctx, previous, "install-tun")
	beforeManifest, err := os.ReadFile(filepath.Join(installationState, "manifest.json"))
	if err != nil {
		t.Fatal(err)
	}
	for _, enabled := range []bool{false, true} {
		for _, action := range []string{"cancel", "eof"} {
			if !t.Run(fmt.Sprintf("enabled-%t/%s", enabled, action), func(t *testing.T) {
				mode := "disable"
				if enabled {
					mode = "enable"
				}
				run(t, ctx, "/usr/bin/systemctl", mode, "--now", "rainlink-tun.socket")
				testBrokerReplacementCancellation(t, ctx, host, currentHash, previousHash, beforeManifest, enabled, action)
			}) {
				return
			}
		}
	}
}

func replacementDigest(t *testing.T, path string) string {
	t.Helper()
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	hash := sha256.New()
	if _, err = io.Copy(hash, file); err != nil {
		t.Fatal(err)
	}
	return hex.EncodeToString(hash.Sum(nil))
}

func testBrokerReplacementCancellation(t *testing.T, parent context.Context, host, currentHash, previousHash string, beforeManifest []byte, enabled bool, action string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(parent, 110*time.Second)
	defer cancel()
	watch, err := unix.FanotifyInit(unix.FAN_CLOEXEC|unix.FAN_NONBLOCK|unix.FAN_CLASS_CONTENT, unix.O_RDONLY|unix.O_CLOEXEC)
	if err != nil {
		t.Fatal("VM kernel must support actual fanotify permission events", err)
	}
	closeWatch := func() error {
		if watch < 0 {
			return nil
		}
		err := unix.Close(watch)
		watch = -1
		return err
	}
	defer closeWatch()
	if err = unix.FanotifyMark(watch, unix.FAN_MARK_ADD, unix.FAN_OPEN_PERM, unix.AT_FDCWD, installedCore); err != nil {
		t.Fatal(err)
	}
	broker := exec.CommandContext(ctx, host, "manage-tun-service")
	broker.Env = []string{"PATH=/usr/bin:/bin", "LANG=C", "LC_ALL=C"}
	broker.SysProcAttr = &syscall.SysProcAttr{Credential: &syscall.Credential{Uid: 65534, Gid: 65534}}
	input, err := broker.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	defer input.Close()
	output, err := broker.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	var diagnostics bytes.Buffer
	broker.Stderr = &diagnostics
	if err = broker.Start(); err != nil {
		t.Fatal(err)
	}
	waited := false
	defer func() {
		if !waited {
			// Closing the fanotify group releases any permission wait before
			// waiting for the real worker to finish its cancellation/rollback.
			_ = input.Close()
			_ = closeWatch()
			cancel()
			_ = broker.Wait()
		}
	}()
	encode, decode := json.NewEncoder(input), json.NewDecoder(output)
	if err = encode.Encode(request{ID: 1, Method: "install"}); err != nil {
		t.Fatal(err)
	}
	event := holdReplacementOpen(t, ctx, watch, currentHash)
	defer unix.Close(int(event.Fd))
	workerPID := int(event.Pid)
	parentPID, rootUID, err := fixtureProcessParent(workerPID)
	if err != nil || parentPID != broker.Process.Pid || rootUID != 0 {
		t.Fatal("permission event is not the broker's real root worker", workerPID, parentPID, rootUID, err)
	}
	_, brokerUID, err := fixtureProcessParent(broker.Process.Pid)
	if err != nil || brokerUID != 65534 {
		t.Fatal("broker must remain an ordinary user", brokerUID, err)
	}
	journal, err := os.ReadFile(filepath.Join(installationState, "transaction.json"))
	if err != nil {
		t.Fatal(err)
	}
	var transaction struct{ Committed bool }
	if json.Unmarshal(journal, &transaction) != nil || transaction.Committed {
		t.Fatal("requires an uncommitted real installation transaction")
	}
	// The host is already replaced. The new core has been fully written and
	// fsynced; only its final destination check is held in the kernel.
	temporary, err := filepath.Glob(filepath.Dir(installedCore) + "/.rainlink-*.tmp")
	if err != nil || len(temporary) != 1 || replacementDigest(t, temporary[0]) != replacementDigest(t, filepath.Join(filepath.Dir(host), "sing-box")) {
		t.Fatal("did not observe the complete second-file replacement", temporary, err)
	}
	start := time.Now()
	if action == "cancel" {
		if err = encode.Encode(request{ID: 2, Method: "cancel"}); err != nil {
			t.Fatal(err)
		}
		var ack struct {
			ID     int
			Result map[string]bool
			Error  *failure
		}
		if err = decode.Decode(&ack); err != nil || ack.ID != 2 || ack.Error != nil || !ack.Result["requested"] {
			t.Fatal("ordinary cancellation was not acknowledged", ack, err)
		}
	} else if err = input.Close(); err != nil {
		t.Fatal(err)
	}
	waitForRevokedControl(t, ctx, broker.Process.Pid, workerPID)
	if _, err = os.Stat(fmt.Sprintf("/proc/%d", workerPID)); err != nil {
		t.Fatal("worker must still be waiting for the actual file operation", err)
	}
	response := make([]byte, 8)
	binary.NativeEndian.PutUint32(response[:4], uint32(event.Fd))
	binary.NativeEndian.PutUint32(response[4:], unix.FAN_ALLOW)
	if n, err := unix.Write(watch, response); err != nil || n != len(response) {
		t.Fatal("could not release real filesystem permission wait", n, err)
	}
	if err = closeWatch(); err != nil {
		t.Fatal(err)
	}
	if action == "cancel" {
		var result struct {
			ID     int
			Error  *failure
			Result json.RawMessage
		}
		if err = decode.Decode(&result); err != nil || result.ID != 1 || result.Error == nil || result.Error.Code != "cancelled" || len(result.Result) != 0 {
			t.Fatal("original replacement did not retain cancellation", result, err)
		}
		if err = input.Close(); err != nil {
			t.Fatal(err)
		}
	}
	err = broker.Wait()
	waited = true
	var exit *exec.ExitError
	if action == "cancel" && err != nil || action == "eof" && (!errors.As(err, &exit) || exit.ExitCode() != 1) {
		t.Fatal("unexpected broker exit", err, diagnostics.String())
	}
	if elapsed := time.Since(start); elapsed > 45*time.Second {
		t.Fatal("cancellation/rollback exceeded its VM acceptance bound", elapsed)
	}
	if _, err = os.Stat(fmt.Sprintf("/proc/%d", workerPID)); !os.IsNotExist(err) {
		t.Fatal("root worker remained after broker completion", err)
	}
	afterManifest, err := os.ReadFile(filepath.Join(installationState, "manifest.json"))
	if err != nil || !bytes.Equal(afterManifest, beforeManifest) || replacementDigest(t, installedHost) != previousHash {
		t.Fatal("previous installed host and manifest were not restored", err)
	}
	entries, err := os.ReadDir(installationState)
	if err != nil || len(entries) != 2 || entries[0].Name() != "install.lock" || entries[1].Name() != "manifest.json" {
		t.Fatal("installation transaction or spool was left behind", entries, err)
	}
	remaining, err := filepath.Glob(filepath.Dir(installedCore) + "/.rainlink-*.tmp")
	if err != nil || len(remaining) != 0 {
		t.Fatal("replacement temporary file was left behind", remaining, err)
	}
	status := linuxinstall.InspectService(ctx)
	if status.State != "different" || !status.CanManage || status.Enabled != enabled || status.Active != enabled {
		t.Fatal("cancelled upgrade did not restore actual service state", status)
	}
	evidence := map[string]any{
		"action": action, "brokerUID": brokerUID, "elevatedUID": rootUID,
		"workerPID": workerPID, "heldFile": installedCore,
		"hostSha256Before": previousHash, "hostSha256WhileHeld": currentHash,
		"hostSha256After":                replacementDigest(t, installedHost),
		"realCoreTemporaryWriteObserved": true, "uncommittedJournalObserved": true,
		"controlRevokedBeforeFilesystemRelease": true, "originalOperationCancelled": true,
		"socketEnabledAfter": status.Enabled, "socketActiveAfter": status.Active,
		"workerExited": true, "transactionAndTemporaryFilesRetired": true,
		"cancelAndRollbackSeconds": time.Since(start).Seconds(),
	}
	data, err := json.MarshalIndent(evidence, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	if directory := os.Getenv("RAINLINK_TEST_MANAGEMENT_EVIDENCE"); directory != "" {
		name := fmt.Sprintf("broker-replacement-enabled-%t-%s.json", enabled, action)
		if err = os.WriteFile(filepath.Join(directory, name), append(data, '\n'), 0600); err != nil {
			t.Fatal(err)
		}
	}
	t.Log(string(data))
}

func holdReplacementOpen(t *testing.T, ctx context.Context, watch int, currentHash string) unix.FanotifyEventMetadata {
	t.Helper()
	var buffer [4096]byte
	for {
		n, err := unix.Read(watch, buffer[:])
		if err != nil && !errors.Is(err, unix.EAGAIN) && !errors.Is(err, unix.EINTR) {
			t.Fatal(err)
		}
		for offset := 0; offset < n; {
			var event unix.FanotifyEventMetadata
			if err = binary.Read(bytes.NewReader(buffer[offset:n]), binary.NativeEndian, &event); err != nil || event.Vers != unix.FANOTIFY_METADATA_VERSION || event.Event_len < uint32(binary.Size(event)) || int(event.Event_len) > n-offset || event.Fd < 0 || event.Mask&unix.FAN_OPEN_PERM == 0 {
				t.Fatal("unexpected actual fanotify permission event", event, err)
			}
			if replacementDigest(t, installedHost) == currentHash {
				return event
			}
			response := make([]byte, 8)
			binary.NativeEndian.PutUint32(response[:4], uint32(event.Fd))
			binary.NativeEndian.PutUint32(response[4:], unix.FAN_ALLOW)
			written, writeErr := unix.Write(watch, response)
			closeErr := unix.Close(int(event.Fd))
			if writeErr != nil || closeErr != nil || written != len(response) {
				t.Fatal("could not allow preliminary core inspection", written, errors.Join(writeErr, closeErr))
			}
			offset += int(event.Event_len)
		}
		select {
		case <-ctx.Done():
			t.Fatal("actual replacement never reached the expected file boundary", ctx.Err())
		case <-time.After(10 * time.Millisecond):
		}
	}
}

// Observe revocation of the real stdin pipe, rather than assuming the cancel
// acknowledgement means the root worker has already received the cancellation.
func waitForRevokedControl(t *testing.T, ctx context.Context, brokerPID, workerPID int) {
	t.Helper()
	pipe, err := os.Readlink(fmt.Sprintf("/proc/%d/fd/0", workerPID))
	if err != nil || !strings.HasPrefix(pipe, "pipe:[") {
		t.Fatal("root worker stdin is not a private control pipe", pipe, err)
	}
	for {
		entries, err := os.ReadDir(fmt.Sprintf("/proc/%d/fd", brokerPID))
		if err != nil {
			t.Fatal(err)
		}
		writer := false
		for _, entry := range entries {
			base := fmt.Sprintf("/proc/%d/", brokerPID)
			target, err := os.Readlink(base + "fd/" + entry.Name())
			if err != nil || target != pipe {
				continue
			}
			data, err := os.ReadFile(base + "fdinfo/" + entry.Name())
			if err != nil {
				continue // It may have just closed as cancellation arrives.
			}
			for _, line := range strings.Split(string(data), "\n") {
				var flags uint32
				if _, err := fmt.Sscanf(line, "flags:\t%o", &flags); err == nil && flags&unix.O_ACCMODE == unix.O_WRONLY {
					writer = true
				}
			}
		}
		if !writer {
			return
		}
		select {
		case <-ctx.Done():
			t.Fatal("broker did not revoke the actual root worker control pipe", ctx.Err())
		case <-time.After(10 * time.Millisecond):
		}
	}
}
