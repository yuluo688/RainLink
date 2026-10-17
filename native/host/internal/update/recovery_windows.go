//go:build windows

package update

import (
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"io"
	"path/filepath"
	"runtime"
	"strings"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

// ErrInstallationBusy means another launcher, installer or recovery owns the
// installation. Callers may retry while the old helper is finishing.
var ErrInstallationBusy = errors.New("installation is busy")

type updateLease struct{ handle windows.Handle }

func (lease *updateLease) Close() error {
	if lease.handle == 0 {
		return nil
	}
	err := windows.ReleaseMutex(lease.handle)
	closeErr := windows.CloseHandle(lease.handle)
	lease.handle = 0
	runtime.UnlockOSThread()
	return errors.Join(err, closeErr)
}

// AcquireLock serializes launch/update across sessions without writing to the
// installation directory. Close must run on the acquiring goroutine: Windows
// mutex ownership belongs to an OS thread. Process death abandons the mutex.
func AcquireLock(target string) (io.Closer, error) {
	target, err := canonicalDirectory(target)
	if err != nil {
		return nil, err
	}
	key := sha256.Sum256([]byte(strings.ToLower(target)))
	name := fmt.Sprintf(`Global\RainLink.Installation.%x`, key)
	pointer, err := windows.UTF16PtrFromString(name)
	if err != nil {
		return nil, err
	}
	handle, err := windows.CreateMutex(nil, false, pointer)
	if err != nil && !errors.Is(err, windows.ERROR_ALREADY_EXISTS) {
		return nil, fmt.Errorf("open installation mutex: %w", err)
	}
	runtime.LockOSThread()
	status, err := windows.WaitForSingleObject(handle, 0)
	if err != nil || status != windows.WAIT_OBJECT_0 && status != windows.WAIT_ABANDONED {
		windows.CloseHandle(handle)
		runtime.UnlockOSThread()
		if err != nil {
			return nil, err
		}
		return nil, ErrInstallationBusy
	}
	return &updateLease{handle: handle}, nil
}

var user32 = windows.NewLazySystemDLL("user32.dll")
var findWindow = user32.NewProc("FindWindowW")
var showWindow = user32.NewProc("ShowWindow")
var foregroundWindow = user32.NewProc("SetForegroundWindow")
var messageBox = user32.NewProc("MessageBoxW")

// ShowExistingWindow retains the single desktop session behavior.
func ShowExistingWindow() bool {
	class, _ := windows.UTF16PtrFromString("FLUTTER_RUNNER_WIN32_WINDOW")
	title, _ := windows.UTF16PtrFromString("RainLink")
	handle, _, _ := findWindow.Call(uintptr(unsafe.Pointer(class)), uintptr(unsafe.Pointer(title)))
	if handle == 0 {
		return false
	}
	showWindow.Call(handle, 9)
	foregroundWindow.Call(handle)
	return true
}

// ShowLaunchFailure exposes a fixed message without local paths or user data.
func ShowLaunchFailure(busy bool) {
	text := "RainLink 无法安全恢复或启动。文件与备份已保留，请关闭其他 RainLink 进程后重试。"
	if busy {
		text = "RainLink 正在更新或恢复，请稍后重新打开。"
	}
	message, _ := windows.UTF16PtrFromString(text)
	title, _ := windows.UTF16PtrFromString("RainLink")
	messageBox.Call(0, uintptr(unsafe.Pointer(message)), uintptr(unsafe.Pointer(title)), 0x10)
}

// WaitForRuntimeExit also covers a process still loading DLLs before creating
// its desktop mutex/window. It only waits on matching retained process handles.
func WaitForRuntimeExit(ctx context.Context, target string) error {
	snapshot, err := windows.CreateToolhelp32Snapshot(windows.TH32CS_SNAPPROCESS, 0)
	if err != nil {
		return err
	}
	defer windows.CloseHandle(snapshot)
	entry := windows.ProcessEntry32{Size: uint32(unsafe.Sizeof(windows.ProcessEntry32{}))}
	err = windows.Process32First(snapshot, &entry)
	for err == nil {
		name := windows.UTF16ToString(entry.ExeFile[:])
		if strings.EqualFold(name, "rainlink-ui.exe") && entry.ProcessID != windows.GetCurrentProcessId() {
			handle, openErr := windows.OpenProcess(windows.PROCESS_QUERY_LIMITED_INFORMATION|windows.SYNCHRONIZE, false, entry.ProcessID)
			if openErr != nil && !errors.Is(openErr, windows.ERROR_INVALID_PARAMETER) {
				return openErr
			}
			if openErr == nil {
				buffer := make([]uint16, 32768)
				size := uint32(len(buffer))
				queryErr := windows.QueryFullProcessImageName(handle, 0, &buffer[0], &size)
				if queryErr == nil && strings.EqualFold(filepath.Clean(windows.UTF16ToString(buffer[:size])), filepath.Join(target, "rainlink-ui.exe")) {
					waitErr := waitRuntime(ctx, handle)
					windows.CloseHandle(handle)
					if waitErr != nil {
						return waitErr
					}
				} else {
					windows.CloseHandle(handle)
					if queryErr != nil {
						return queryErr
					}
				}
			}
		}
		err = windows.Process32Next(snapshot, &entry)
	}
	if !errors.Is(err, windows.ERROR_NO_MORE_FILES) {
		return err
	}
	return nil
}

func waitRuntime(ctx context.Context, handle windows.Handle) error {
	for {
		if err := ctx.Err(); err != nil {
			return err
		}
		status, err := windows.WaitForSingleObject(handle, 100)
		if err != nil {
			return err
		}
		if status == windows.WAIT_OBJECT_0 {
			return nil
		}
		if status != uint32(windows.WAIT_TIMEOUT) {
			return errors.New("unexpected runtime state")
		}
		time.Sleep(25 * time.Millisecond)
	}
}
