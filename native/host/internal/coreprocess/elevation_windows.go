package coreprocess

import (
	"bufio"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"

	"github.com/Microsoft/go-winio"
	"golang.org/x/sys/windows"
)

const pipePrefix = `\\.\pipe\RainLink.TUN.`
const maxConfigBytes = 128 << 10

type coreEvent struct {
	Kind string `json:"kind"`
	Data string `json:"data,omitempty"`
}

type eventWriter struct {
	mu      sync.Mutex
	encoder *json.Encoder
}

func (w *eventWriter) send(event coreEvent) error {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.encoder.Encode(event)
}

func (w *eventWriter) Write(data []byte) (int, error) {
	// Bound individual frames even if the core writes a long diagnostic.
	for remaining := data; len(remaining) > 0; {
		length := min(len(remaining), 8<<10)
		if err := w.send(coreEvent{Kind: "log", Data: string(remaining[:length])}); err != nil {
			return 0, err
		}
		remaining = remaining[length:]
	}
	return len(data), nil
}

type elevatedProcess struct {
	connection net.Conn
	handle     windows.Handle
	done       chan struct{}
	err        error
	closeOnce  sync.Once
	stopOnce   sync.Once
}

func (p *elevatedProcess) Kill() error {
	// EOF is a stop request, including when the unelevated host is killed.
	var err error
	p.stopOnce.Do(func() { err = p.connection.Close() })
	return err
}

func (p *elevatedProcess) Wait() error { <-p.done; return p.err }
func (p *elevatedProcess) Close() {
	p.closeOnce.Do(func() {
		_ = p.Kill()
		windows.CloseHandle(p.handle)
	})
}

func pipePID(connection net.Conn, server bool) (uint32, error) {
	file, ok := connection.(interface{ Fd() uintptr })
	if !ok {
		return 0, errors.New("pipe has no native handle")
	}
	var pid uint32
	var err error
	if server {
		err = windows.GetNamedPipeServerProcessId(windows.Handle(file.Fd()), &pid)
	} else {
		err = windows.GetNamedPipeClientProcessId(windows.Handle(file.Fd()), &pid)
	}
	return pid, err
}

func sameExecutable(pid uint32) (windows.Handle, error) {
	process, err := windows.OpenProcess(windows.PROCESS_QUERY_LIMITED_INFORMATION|windows.SYNCHRONIZE, false, pid)
	if err != nil {
		return 0, err
	}
	buffer := make([]uint16, 32768)
	length := uint32(len(buffer))
	err = windows.QueryFullProcessImageName(process, 0, &buffer[0], &length)
	self, selfErr := os.Executable()
	if err != nil || selfErr != nil || !strings.EqualFold(filepath.Clean(windows.UTF16ToString(buffer[:length])), filepath.Clean(self)) {
		windows.CloseHandle(process)
		return 0, errors.New("untrusted elevation peer")
	}
	return process, nil
}

// launchAsAdministrator does not elevate the GUI or accept a command to run.
func launchAsAdministrator(ctx context.Context, executable, arguments string) (windows.Handle, error) {
	type result struct {
		handle windows.Handle
		err    error
	}
	finished := make(chan result)
	go func() {
		verb, _ := windows.UTF16PtrFromString("runas")
		file, fileErr := windows.UTF16PtrFromString(executable)
		args, argsErr := windows.UTF16PtrFromString(arguments)
		if fileErr != nil || argsErr != nil {
			select {
			case finished <- result{err: errors.New("invalid elevation arguments")}:
			case <-ctx.Done():
			}
			return
		}
		// SHELLEXECUTEINFOW is kept here because x/sys exposes ShellExecuteW,
		// which cannot return the handle needed for peer verification/reaping.
		type executeInfo struct {
			Size, Mask                        uint32
			Window                            windows.Handle
			Verb, File, Parameters, Directory *uint16
			Show                              int32
			Instance                          windows.Handle
			IDList                            uintptr
			Class                             *uint16
			ClassKey                          windows.Handle
			HotKey                            uint32
			Icon                              windows.Handle
			Process                           windows.Handle
		}
		info := executeInfo{Mask: 0x40 | 0x100 | 0x400, Verb: verb, File: file, Parameters: args, Show: windows.SW_HIDE}
		info.Size = uint32(unsafe.Sizeof(info))
		call := windows.NewLazySystemDLL("shell32.dll").NewProc("ShellExecuteExW")
		ok, _, callErr := call.Call(uintptr(unsafe.Pointer(&info)))
		var err error
		if ok == 0 {
			err = callErr
		}
		select {
		case finished <- result{info.Process, err}:
		case <-ctx.Done():
			// A dialog may finish after cancellation. No configuration is sent,
			// and this late helper must never survive to create an adapter.
			if info.Process != 0 {
				_ = windows.TerminateProcess(info.Process, 1)
				windows.CloseHandle(info.Process)
			}
		}
	}()
	select {
	case <-ctx.Done():
		return 0, ctx.Err()
	case outcome := <-finished:
		if errors.Is(outcome.err, windows.ERROR_CANCELLED) {
			return 0, ErrPermissionDenied
		}
		if outcome.err != nil {
			return 0, outcome.err
		}
		if outcome.handle == 0 {
			return 0, errors.New("elevation returned no process")
		}
		return outcome.handle, nil
	}
}

func startElevated(ctx context.Context, path string, config []byte, stdout, stderr io.Writer) (Process, error) {
	self, err := os.Executable()
	if err != nil {
		return nil, err
	}
	if !strings.EqualFold(filepath.Clean(path), filepath.Join(filepath.Dir(self), "sing-box.exe")) {
		return nil, errors.New("elevation requires the bundled core")
	}
	user, err := windows.GetCurrentProcessToken().GetTokenUser()
	if err != nil {
		return nil, err
	}
	name := pipePrefix + strconv.Itoa(os.Getpid()) + "." + rand.Text()
	listener, err := winio.ListenPipe(name, &winio.PipeConfig{
		SecurityDescriptor: "D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;" + user.User.Sid.String() + ")",
		InputBufferSize:    maxConfigBytes, OutputBufferSize: maxConfigBytes,
	})
	if err != nil {
		return nil, err
	}
	defer listener.Close()
	stopAccept := context.AfterFunc(ctx, func() { _ = listener.Close() })
	defer stopAccept()
	arguments := syscall.EscapeArg("tun-core") + " " + syscall.EscapeArg(name) + " " + strconv.Itoa(os.Getpid())
	handle, err := launchAsAdministrator(ctx, self, arguments)
	if err != nil {
		return nil, err
	}
	committed := false
	defer func() {
		if !committed {
			_ = windows.TerminateProcess(handle, 1)
			windows.CloseHandle(handle)
		}
	}()
	var connection net.Conn
	// Ignore clients that race the helper. Their PID cannot authorize config.
	for {
		connection, err = listener.Accept()
		if err != nil {
			return nil, err
		}
		pid, peerErr := pipePID(connection, false)
		expected, pidErr := windows.GetProcessId(handle)
		if peerErr == nil && pidErr == nil && pid == expected {
			break
		}
		_ = connection.Close()
	}
	defer func() {
		if !committed {
			_ = connection.Close()
		}
	}()
	stopIO := context.AfterFunc(ctx, func() { _ = connection.Close() })
	defer stopIO()
	if len(config) > maxConfigBytes {
		return nil, errors.New("core configuration exceeds limit")
	}
	if err = json.NewEncoder(connection).Encode(struct {
		Config json.RawMessage `json:"config"`
	}{config}); err != nil {
		return nil, err
	}
	process := &elevatedProcess{connection: connection, handle: handle, done: make(chan struct{})}
	ready := make(chan error, 1)
	go func() {
		defer close(process.done)
		defer connection.Close()
		started := false
		scanner := bufio.NewScanner(connection)
		scanner.Buffer(make([]byte, 4096), maxConfigBytes)
		for scanner.Scan() {
			var event coreEvent
			if json.Unmarshal(scanner.Bytes(), &event) != nil {
				break
			}
			switch event.Kind {
			case "started":
				if !started {
					started = true
					ready <- nil
				}
			case "log":
				_, _ = stdout.Write([]byte(event.Data))
			case "failed":
				process.err = errors.New("elevated core failed")
			}
		}
		if !started {
			ready <- errors.New("elevated core did not start")
		}
		// Closing the pipe asks the guardian to kill its job. Bound the wait
		// even after a transport error or a stuck child.
		_ = connection.Close()
		result, waitErr := windows.WaitForSingleObject(handle, 3000)
		if waitErr != nil || result != windows.WAIT_OBJECT_0 {
			_ = windows.TerminateProcess(handle, 1)
			_, _ = windows.WaitForSingleObject(handle, 2000)
			process.err = errors.New("elevation guardian stopped unexpectedly")
		}
	}()
	select {
	case <-ctx.Done():
		_ = process.Kill()
		_ = process.Wait()
		return nil, ctx.Err()
	case err = <-ready:
		if err != nil {
			_ = process.Kill()
			_ = process.Wait()
			return nil, err
		}
	}
	committed = true
	return process, nil
}

func lockedBundledCore() (*os.File, string, error) {
	self, err := os.Executable()
	if err != nil {
		return nil, "", err
	}
	path := filepath.Join(filepath.Dir(self), "sing-box.exe")
	name, err := windows.UTF16PtrFromString(path)
	if err != nil {
		return nil, "", err
	}
	// Deny writes/replacement between checksum verification and child exit.
	handle, err := windows.CreateFile(name, windows.GENERIC_READ, windows.FILE_SHARE_READ, nil, windows.OPEN_EXISTING, windows.FILE_ATTRIBUTE_NORMAL, 0)
	if err != nil {
		return nil, "", err
	}
	file := os.NewFile(uintptr(handle), path)
	digest := sha256.New()
	if _, err = io.Copy(digest, file); err != nil || hex.EncodeToString(digest.Sum(nil)) != lockedCoreHash() {
		file.Close()
		return nil, "", errors.New("bundled core checksum mismatch")
	}
	return file, path, nil
}

// RunElevated owns only the fixed, hash-verified core. It exits on peer EOF,
// parent exit or core exit, and its job kills the child even if it is terminated.
func RunElevated(name string, parentID int) error {
	if !windows.GetCurrentProcessToken().IsElevated() || parentID < 1 ||
		!strings.HasPrefix(name, pipePrefix+strconv.Itoa(parentID)+".") || strings.ContainsAny(strings.TrimPrefix(name, pipePrefix), `\/`) {
		return errors.New("invalid privileged launch")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	connection, err := winio.DialPipeContext(ctx, name)
	if err != nil {
		return err
	}
	defer connection.Close()
	pid, err := pipePID(connection, true)
	if err != nil || pid != uint32(parentID) {
		return errors.New("untrusted pipe server")
	}
	parent, err := sameExecutable(pid)
	if err != nil {
		return err
	}
	defer windows.CloseHandle(parent)
	_ = connection.SetReadDeadline(time.Now().Add(5 * time.Second))
	reader := bufio.NewReader(io.LimitReader(connection, maxConfigBytes+1))
	line, err := reader.ReadBytes('\n')
	if err != nil || len(line) > maxConfigBytes {
		return errors.New("invalid privileged request")
	}
	var payload struct {
		Config json.RawMessage `json:"config"`
	}
	if json.Unmarshal(line, &payload) != nil || len(payload.Config) == 0 {
		return errors.New("invalid core configuration")
	}
	_ = connection.SetReadDeadline(time.Time{})
	file, path, err := lockedBundledCore()
	if err != nil {
		return err
	}
	defer file.Close()
	// The lease is a kernel handle, so a killed guardian releases it without a
	// stale lock file. TUN capture is system-wide, including other user sessions.
	leaseName, _ := windows.UTF16PtrFromString(`Global\RainLink.TUN.Runtime`)
	lease, leaseErr := windows.CreateEvent(nil, 1, 0, leaseName)
	if lease != 0 {
		defer windows.CloseHandle(lease)
	}
	if leaseErr != nil {
		return errors.New("another RainLink TUN session is active")
	}
	if err = guardDescendants(); err != nil {
		return err
	}
	events := &eventWriter{encoder: json.NewEncoder(connection)}
	child, err := Start(context.Background(), path, payload.Config, events, events, false)
	if err != nil {
		_ = events.send(coreEvent{Kind: "failed"})
		return err
	}
	defer child.Close()
	done := make(chan error, 1)
	go func() { done <- child.Wait() }()
	peerClosed := make(chan struct{})
	go func() { _, _ = io.Copy(io.Discard, connection); close(peerClosed) }()
	parentClosed := make(chan struct{})
	watching := make(chan struct{})
	watcherDone := make(chan struct{})
	defer func() { close(watching); <-watcherDone }()
	go func() {
		defer close(watcherDone)
		for {
			result, err := windows.WaitForSingleObject(parent, 250)
			if err != nil || result == windows.WAIT_OBJECT_0 {
				close(parentClosed)
				return
			}
			select {
			case <-watching:
				return
			default:
			}
		}
	}()
	if err = events.send(coreEvent{Kind: "started"}); err != nil {
		_ = child.Kill()
		<-done
		return err
	}
	select {
	case err = <-done:
		if err != nil {
			_ = events.send(coreEvent{Kind: "failed"})
		}
	case <-peerClosed:
		_ = child.Kill()
		err = <-done
	case <-parentClosed:
		_ = child.Kill()
		err = <-done
	}
	return err
}
