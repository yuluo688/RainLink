package session

import (
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"runtime"
	"strconv"
	"sync"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
)

func hideWindow(cmd *exec.Cmd) { cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true} }

func crypt(data []byte, entropy string, decrypt bool) ([]byte, error) {
	if len(data) == 0 {
		return nil, errors.New("empty protected input")
	}
	input := windows.DataBlob{Size: uint32(len(data)), Data: &data[0]}
	contextBytes := []byte("RainLink/" + entropy)
	contextBlob := windows.DataBlob{Size: uint32(len(contextBytes)), Data: &contextBytes[0]}
	var output windows.DataBlob
	var err error
	if decrypt {
		err = windows.CryptUnprotectData(&input, nil, &contextBlob, 0, nil, windows.CRYPTPROTECT_UI_FORBIDDEN, &output)
	} else {
		err = windows.CryptProtectData(&input, nil, &contextBlob, 0, nil, windows.CRYPTPROTECT_UI_FORBIDDEN, &output)
	}
	if err != nil {
		return nil, err
	}
	defer windows.LocalFree(windows.Handle(unsafe.Pointer(output.Data)))
	return append([]byte(nil), unsafe.Slice(output.Data, output.Size)...), nil
}

func seal(ctx context.Context, plain []byte, id string) (string, error) {
	if err := ctx.Err(); err != nil {
		return "", err
	}
	data, err := crypt(plain, id, false)
	defer clear(data)
	if err != nil {
		return "", err
	}
	if err := ctx.Err(); err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(data), nil
}
func unseal(ctx context.Context, cipher, id string) ([]byte, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	data, err := base64.StdEncoding.DecodeString(cipher)
	defer clear(data)
	if err != nil {
		return nil, err
	}
	plain, err := crypt(data, id, true)
	if ctx.Err() != nil {
		clear(plain)
		return nil, ctx.Err()
	}
	return plain, err
}

type registryValue struct {
	Exists bool
	Kind   uint32
	Data   []byte
}
type proxyJournal struct {
	Owner   int
	Before  map[string]registryValue
	Owned   map[string]registryValue
	Applied bool
}

const internetKey = `Software\Microsoft\Windows\CurrentVersion\Internet Settings`

var managedValues = []string{"ProxyEnable", "ProxyServer", "ProxyOverride", "AutoConfigURL", "AutoDetect"}
var wininet = windows.NewLazySystemDLL("wininet.dll")
var internetSetOption = wininet.NewProc("InternetSetOptionW")

func registrySnapshot(key registry.Key) (map[string]registryValue, error) {
	values := make(map[string]registryValue)
	for _, name := range managedValues {
		size, kind, err := key.GetValue(name, nil)
		if errors.Is(err, registry.ErrNotExist) {
			values[name] = registryValue{}
			continue
		}
		if err != nil {
			return nil, err
		}
		if kind != registry.SZ && kind != registry.EXPAND_SZ && kind != registry.DWORD {
			return nil, errors.New("unsupported proxy setting type")
		}
		data := make([]byte, size)
		_, _, err = key.GetValue(name, data)
		if err != nil {
			return nil, err
		}
		values[name] = registryValue{true, kind, data}
	}
	return values, nil
}

func writeRegistry(key registry.Key, values map[string]registryValue) error {
	for _, name := range managedValues {
		value := values[name]
		if !value.Exists {
			if err := key.DeleteValue(name); err != nil && !errors.Is(err, registry.ErrNotExist) {
				return err
			}
			continue
		}
		switch value.Kind {
		case registry.DWORD:
			if len(value.Data) != 4 {
				return errors.New("invalid registry DWORD")
			}
			if err := key.SetDWordValue(name, binary.LittleEndian.Uint32(value.Data)); err != nil {
				return err
			}
		case registry.SZ, registry.EXPAND_SZ:
			if len(value.Data)%2 != 0 {
				return errors.New("invalid registry string")
			}
			units := make([]uint16, len(value.Data)/2)
			for i := range units {
				units[i] = binary.LittleEndian.Uint16(value.Data[i*2:])
			}
			text := windows.UTF16ToString(units)
			var err error
			if value.Kind == registry.SZ {
				err = key.SetStringValue(name, text)
			} else {
				err = key.SetExpandStringValue(name, text)
			}
			if err != nil {
				return err
			}
		default:
			return errors.New("unsupported registry type")
		}
	}
	return notifyProxy()
}

func notifyProxy() error {
	for _, option := range []uintptr{39, 37} {
		result, _, err := internetSetOption.Call(0, option, 0, 0)
		if result == 0 {
			return err
		}
	}
	return nil
}

func dwordValue(number uint32) registryValue {
	data := make([]byte, 4)
	binary.LittleEndian.PutUint32(data, number)
	return registryValue{true, registry.DWORD, data}
}
func stringValue(text string) registryValue {
	units, _ := windows.UTF16FromString(text)
	data := make([]byte, len(units)*2)
	for i, v := range units {
		binary.LittleEndian.PutUint16(data[i*2:], v)
	}
	return registryValue{true, registry.SZ, data}
}
func journalPath(directory string) string { return filepath.Join(directory, "proxy-recovery.bin") }

func withProxyLock(work func() error) error {
	// Win32 mutex ownership belongs to an OS thread, not a Go goroutine.
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	user, err := windows.GetCurrentProcessToken().GetTokenUser()
	if err != nil {
		return err
	}
	name, _ := windows.UTF16PtrFromString(`Local\RainLink.Proxy.` + user.User.Sid.String())
	handle, err := windows.CreateMutex(nil, false, name)
	if err != nil && !errors.Is(err, windows.ERROR_ALREADY_EXISTS) {
		return err
	}
	defer windows.CloseHandle(handle)
	result, err := windows.WaitForSingleObject(handle, 5000)
	if err != nil {
		return err
	}
	if result != windows.WAIT_OBJECT_0 && result != windows.WAIT_ABANDONED {
		return errors.New("proxy settings are busy")
	}
	defer windows.ReleaseMutex(handle)
	return work()
}

func readJournal(directory string) (*proxyJournal, error) {
	data, err := os.ReadFile(journalPath(directory))
	if err != nil {
		return nil, err
	}
	plain, err := crypt(data, "proxy-recovery", true)
	if err != nil {
		return nil, err
	}
	var journal proxyJournal
	if err = json.Unmarshal(plain, &journal); err != nil {
		return nil, err
	}
	return &journal, nil
}

func ownerAlive(pid int) bool {
	handle, err := windows.OpenProcess(windows.SYNCHRONIZE, false, uint32(pid))
	if err != nil {
		return !errors.Is(err, windows.ERROR_INVALID_PARAMETER)
	}
	defer windows.CloseHandle(handle)
	result, err := windows.WaitForSingleObject(handle, 0)
	return err != nil || result == uint32(windows.WAIT_TIMEOUT)
}

func restoreLocked(directory string) error {
	journal, err := readJournal(directory)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if journal.Owner != os.Getpid() && ownerAlive(journal.Owner) {
		return errors.New("another RainLink session owns the proxy")
	}
	key, err := registry.OpenKey(registry.CURRENT_USER, internetKey, registry.QUERY_VALUE|registry.SET_VALUE)
	if err != nil {
		return err
	}
	defer key.Close()
	current, err := registrySnapshot(key)
	if err != nil {
		return err
	}
	// A new routing owner keeps its configuration. A bypass-only edit should
	// not strand our now-dead proxy endpoint: restore routing, preserve that edit.
	routingChanged := false
	for _, name := range []string{"ProxyEnable", "ProxyServer", "AutoConfigURL", "AutoDetect"} {
		if !reflect.DeepEqual(current[name], journal.Owned[name]) {
			routingChanged = true
		}
	}
	if !journal.Applied || !routingChanged {
		restore := make(map[string]registryValue)
		for _, name := range managedValues {
			restore[name] = current[name]
			if reflect.DeepEqual(current[name], journal.Owned[name]) {
				restore[name] = journal.Before[name]
			}
		}
		if err = writeRegistry(key, restore); err != nil {
			return err
		}
		readBack, readErr := registrySnapshot(key)
		if readErr != nil {
			return readErr
		}
		if !reflect.DeepEqual(readBack, restore) {
			return errors.New("proxy restore readback mismatch")
		}
	}
	return os.Remove(journalPath(directory))
}

func restoreProxy(directory string) error {
	return withProxyLock(func() error { return restoreLocked(directory) })
}

// SystemProxyAvailable reports the Windows user proxy backend capability.
func SystemProxyAvailable(ctx context.Context) bool { return ctx.Err() == nil }

func applyProxy(ctx context.Context, directory string, port int) error {
	return withProxyLock(func() error {
		if err := ctx.Err(); err != nil {
			return err
		}
		if err := restoreLocked(directory); err != nil {
			return err
		}
		key, err := registry.OpenKey(registry.CURRENT_USER, internetKey, registry.QUERY_VALUE|registry.SET_VALUE)
		if err != nil {
			return err
		}
		defer key.Close()
		before, err := registrySnapshot(key)
		if err != nil {
			return err
		}
		owned := map[string]registryValue{"ProxyEnable": dwordValue(1), "ProxyServer": stringValue("127.0.0.1:" + strconv.Itoa(port)), "ProxyOverride": stringValue("localhost;127.*;[::1];<local>"), "AutoConfigURL": {}, "AutoDetect": dwordValue(0)}
		journal := proxyJournal{Owner: os.Getpid(), Before: before, Owned: owned}
		plain, err := json.Marshal(journal)
		if err != nil {
			return err
		}
		encrypted, err := crypt(plain, "proxy-recovery", false)
		if err != nil {
			return err
		}
		if err = os.MkdirAll(directory, 0700); err != nil {
			return err
		}
		file, err := os.OpenFile(journalPath(directory), os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
		if err != nil {
			return err
		}
		_, writeErr := file.Write(encrypted)
		syncErr := file.Sync()
		closeErr := file.Close()
		if writeErr != nil || syncErr != nil || closeErr != nil {
			os.Remove(journalPath(directory))
			return errors.Join(writeErr, syncErr, closeErr)
		}
		if err = writeRegistry(key, owned); err == nil {
			var actual map[string]registryValue
			actual, err = registrySnapshot(key)
			if err == nil && !reflect.DeepEqual(actual, owned) {
				err = errors.New("proxy readback mismatch")
			}
		}
		if err == nil {
			err = ctx.Err()
		}
		if err == nil {
			journal.Applied = true
			err = commitJournal(directory, journal)
		}
		if err != nil {
			// A partial apply is still ours; rollback before releasing the mutex.
			rollbackErr := writeRegistry(key, before)
			if rollbackErr == nil {
				os.Remove(journalPath(directory))
			}
			return errors.Join(err, rollbackErr)
		}
		return nil
	})
}

func commitJournal(directory string, journal proxyJournal) error {
	plain, err := json.Marshal(journal)
	if err != nil {
		return err
	}
	encrypted, err := crypt(plain, "proxy-recovery", false)
	if err != nil {
		return err
	}
	temporary := journalPath(directory) + ".tmp"
	file, err := os.OpenFile(temporary, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	_, writeErr := file.Write(encrypted)
	syncErr := file.Sync()
	closeErr := file.Close()
	if err = errors.Join(writeErr, syncErr, closeErr); err != nil {
		return err
	}
	return os.Rename(temporary, journalPath(directory))
}

var watcherMu sync.Mutex
var watcherStarted bool

func startRecoveryWatcher(ctx context.Context, directory string) error {
	watcherMu.Lock()
	defer watcherMu.Unlock()
	if err := ctx.Err(); err != nil {
		return err
	}
	if watcherStarted {
		return nil
	}
	executable, err := os.Executable()
	if err != nil {
		return err
	}
	cmd := exec.Command(executable, "watch-proxy", directory, strconv.Itoa(os.Getpid()))
	hideWindow(cmd)
	if err = cmd.Start(); err != nil {
		return err
	}
	if err = cmd.Process.Release(); err != nil {
		return err
	}
	watcherStarted = true
	return nil
}

// WatchProxy restores the durable lease after an abrupt host exit.
func WatchProxy(directory string, pid int) error {
	handle, err := windows.OpenProcess(windows.SYNCHRONIZE, false, uint32(pid))
	if err == nil {
		_, err = windows.WaitForSingleObject(handle, windows.INFINITE)
		windows.CloseHandle(handle)
	}
	if err != nil && !errors.Is(err, windows.ERROR_INVALID_PARAMETER) {
		return err
	}
	return restoreProxy(directory)
}
