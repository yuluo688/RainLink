//go:build windows

package update

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

func noReparse(name string) error {
	pointer, err := windows.UTF16PtrFromString(name)
	if err != nil {
		return fmt.Errorf("encode local path: %w", err)
	}
	attributes, err := windows.GetFileAttributes(pointer)
	if err != nil || attributes&windows.FILE_ATTRIBUTE_REPARSE_POINT != 0 {
		return errors.New("reparse points are not supported in update paths")
	}
	return nil
}

func replaceStateFile(source, destination string, exclusive bool) error {
	from, err := windows.UTF16PtrFromString(source)
	if err != nil {
		return err
	}
	to, err := windows.UTF16PtrFromString(destination)
	if err != nil {
		return err
	}
	flags := uint32(windows.MOVEFILE_WRITE_THROUGH)
	if !exclusive {
		flags |= windows.MOVEFILE_REPLACE_EXISTING
	}
	if err := windows.MoveFileEx(from, to, flags); err != nil {
		return fmt.Errorf("commit durable file: %w", err)
	}
	return nil
}

// ParentProcess holds the original process handle, avoiding PID reuse.
type ParentProcess struct{ handle windows.Handle }

// OpenParent verifies that the requester is the installed RainLink process.
func OpenParent(request Request) (*ParentProcess, error) {
	if request.Parent == 0 || request.Parent == uint32(os.Getpid()) {
		return nil, errors.New("invalid parent process")
	}
	handle, err := windows.OpenProcess(windows.SYNCHRONIZE|windows.PROCESS_QUERY_LIMITED_INFORMATION, false, request.Parent)
	if err != nil {
		return nil, fmt.Errorf("open original application: %w", err)
	}
	buffer := make([]uint16, 32768)
	size := uint32(len(buffer))
	err = windows.QueryFullProcessImageName(handle, 0, &buffer[0], &size)
	manifest, manifestErr := loadManifest(request.Target)
	if err != nil || manifestErr != nil || !strings.EqualFold(filepath.Clean(windows.UTF16ToString(buffer[:size])), filepath.Join(filepath.Clean(request.Target), runtimeExecutable(manifest))) {
		closeErr := windows.CloseHandle(handle)
		return nil, errors.Join(errors.New("parent executable does not match installation"), closeErr)
	}
	return &ParentProcess{handle: handle}, nil
}

// Wait waits for normal exit without terminating the user's application.
func (parent *ParentProcess) Wait(ctx context.Context) error {
	for {
		if err := ctx.Err(); err != nil {
			return err
		}
		status, err := windows.WaitForSingleObject(parent.handle, 100)
		if err != nil {
			return fmt.Errorf("wait for original application: %w", err)
		}
		if status == windows.WAIT_OBJECT_0 {
			return nil
		}
		if status != uint32(windows.WAIT_TIMEOUT) {
			return errors.New("unexpected original process state")
		}
	}
}

// Close releases the retained process handle.
func (parent *ParentProcess) Close() error { return windows.CloseHandle(parent.handle) }

// ProcessRuntime verifies a new process's database/bootstrap and first frame.
type ProcessRuntime struct {
	command *exec.Cmd
	done    chan struct{}
	job     windows.Handle
}

func launch(executable string, arguments ...string) *exec.Cmd {
	command := exec.Command(executable, arguments...)
	command.Dir = filepath.Dir(executable)
	command.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: windows.CREATE_NEW_PROCESS_GROUP}
	return command
}

// StartAndVerify never signals success from process creation alone.
func (runtime *ProcessRuntime) StartAndVerify(ctx context.Context, executable, healthDirectory string, expected HealthRequest) error {
	// Assign the helper before spawning, so a killed helper cannot leave an
	// unacknowledged candidate or its children alive in the launch/assign gap.
	job, err := windows.CreateJobObject(nil, nil)
	if err != nil {
		return err
	}
	info := windows.JOBOBJECT_EXTENDED_LIMIT_INFORMATION{}
	info.BasicLimitInformation.LimitFlags = windows.JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
	_, err = windows.SetInformationJobObject(job, windows.JobObjectExtendedLimitInformation, uintptr(unsafe.Pointer(&info)), uint32(unsafe.Sizeof(info)))
	if err == nil {
		err = windows.AssignProcessToJobObject(job, windows.CurrentProcess())
	}
	if err != nil {
		windows.CloseHandle(job)
		return fmt.Errorf("guard update candidate: %w", err)
	}
	runtime.job = job
	runtime.command = launch(executable, "--rainlink-update-health="+healthDirectory, "--rainlink-update-token="+expected.Token)
	if err := runtime.command.Start(); err != nil {
		return fmt.Errorf("launch candidate: %w", err)
	}
	runtime.done = make(chan struct{})
	go func() {
		// Wait's status is observed by the done channel. Any exit before the
		// ready file is a failed launch, including a zero exit code.
		runtime.command.Wait()
		close(runtime.done)
	}()
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-runtime.done:
			return errors.New("candidate exited before startup acknowledgment")
		case <-ticker.C:
			file, err := os.Open(filepath.Join(healthDirectory, "ready.json"))
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			if err != nil {
				return fmt.Errorf("read startup acknowledgment: %w", err)
			}
			data, readErr := io.ReadAll(io.LimitReader(file, 4097))
			closeErr := file.Close()
			var ready struct {
				Token   string `json:"token"`
				Version string `json:"version"`
				PID     int    `json:"pid"`
			}
			if readErr != nil || closeErr != nil || len(data) > 4096 ||
				json.Unmarshal(data, &ready) != nil || ready.Token != expected.Token ||
				ready.Version != expected.Version || ready.PID != runtime.command.Process.Pid {
				return errors.New("invalid candidate startup acknowledgment")
			}
			return nil
		}
	}
}

// ReleaseCandidate lets a verified version outlive the helper. Until this
// succeeds, abrupt helper exit terminates its unacknowledged descendants.
func (runtime *ProcessRuntime) ReleaseCandidate() error {
	if runtime.job == 0 {
		return nil
	}
	info := windows.JOBOBJECT_EXTENDED_LIMIT_INFORMATION{}
	if _, err := windows.SetInformationJobObject(runtime.job, windows.JobObjectExtendedLimitInformation, uintptr(unsafe.Pointer(&info)), uint32(unsafe.Sizeof(info))); err != nil {
		return err
	}
	err := windows.CloseHandle(runtime.job)
	if err == nil {
		runtime.job = 0
	}
	return err
}

// Stop terminates only the process created by this runtime and waits for its
// handles and database to close before permitting rollback.
func (runtime *ProcessRuntime) Stop() error {
	if runtime.command == nil || runtime.command.Process == nil {
		return nil
	}
	select {
	case <-runtime.done:
		return nil
	default:
	}
	if err := runtime.command.Process.Kill(); err != nil && !errors.Is(err, os.ErrProcessDone) {
		return fmt.Errorf("stop failed candidate: %w", err)
	}
	select {
	case <-runtime.done:
		return nil
	case <-time.After(10 * time.Second):
		return errors.New("candidate did not exit; backups retained")
	}
}

// StartPrevious restarts the original version only after rollback succeeds.
func (runtime *ProcessRuntime) StartPrevious(executable string) error {
	if err := runtime.ReleaseCandidate(); err != nil {
		return err
	}
	command := launch(executable)
	if err := command.Start(); err != nil {
		return fmt.Errorf("restart previous application: %w", err)
	}
	return command.Process.Release()
}

// WaitConsumed keeps the health files alive until the candidate has observed
// permission to proceed. Only then can successful transaction files be erased.
func (transaction *Transaction) WaitConsumed(ctx context.Context) error {
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
			data, err := os.ReadFile(filepath.Join(transaction.health, "consumed"))
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			if err != nil || string(data) != transaction.token {
				return errors.New("invalid consumed acknowledgment")
			}
			return transaction.Finish()
		}
	}
}
