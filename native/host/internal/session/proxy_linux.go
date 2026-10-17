//go:build linux && !android

package session

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strconv"
	"sync"
	"syscall"
	"time"

	"golang.org/x/sys/unix"
	"rainlink.local/host/internal/linuxproxy"
)

// SystemProxyAvailable requires a verified desktop backend and crash monitoring.
func SystemProxyAvailable(ctx context.Context) bool {
	if !linuxproxy.Available(ctx) {
		return false
	}
	fd, err := unix.PidfdOpen(os.Getpid(), 0)
	if err != nil {
		return false
	}
	return unix.Close(fd) == nil
}

func applyProxy(ctx context.Context, _ string, port int) error {
	controller, err := linuxproxy.New()
	if err != nil {
		return err
	}
	return controller.Apply(ctx, port)
}

func restoreProxy(_ string) error {
	controller, err := linuxproxy.New()
	if err != nil {
		return err
	}
	return controller.Restore(context.Background())
}

type recoveryWatcher struct {
	done chan struct{}
	err  error // Published before done closes.
}

var watcherMu sync.Mutex
var linuxWatcher *recoveryWatcher

func startRecoveryWatcher(ctx context.Context, directory string) error {
	watcherMu.Lock()
	defer watcherMu.Unlock()
	if err := ctx.Err(); err != nil {
		return err
	}
	if linuxWatcher != nil {
		select {
		case <-linuxWatcher.done:
			linuxWatcher = nil
		default:
			return nil
		}
	}
	executable, err := os.Executable()
	if err != nil {
		return err
	}
	reader, writer, err := os.Pipe()
	if err != nil {
		return err
	}
	defer reader.Close()
	command := exec.Command(executable, "watch-proxy", directory, strconv.Itoa(os.Getpid()))
	command.ExtraFiles = []*os.File{writer}
	// Unlike the core, this child must survive the host, including its session.
	command.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err = command.Start(); err != nil {
		return errors.Join(err, writer.Close())
	}
	child := &recoveryWatcher{done: make(chan struct{})}
	go func() {
		child.err = command.Wait()
		close(child.done)
	}()
	stop := func(cause error) error {
		killErr := command.Process.Kill()
		if errors.Is(killErr, os.ErrProcessDone) {
			killErr = nil
		}
		select {
		case <-child.done:
			return errors.Join(cause, killErr, child.err)
		case <-time.After(3 * time.Second):
			return errors.Join(cause, killErr, errors.New("proxy watcher did not exit"))
		}
	}
	if err = writer.Close(); err != nil {
		return stop(err)
	}
	readyCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	stopClose := context.AfterFunc(readyCtx, func() { _ = reader.Close() })
	defer stopClose()
	var ready [1]byte
	_, err = io.ReadFull(reader, ready[:])
	if readyCtx.Err() != nil {
		return stop(readyCtx.Err())
	}
	if err != nil || ready[0] != 1 {
		return stop(errors.Join(errors.New("proxy watcher did not confirm readiness"), err))
	}
	select {
	case <-child.done:
		return errors.Join(errors.New("proxy watcher exited before capture"), child.err)
	default:
	}
	linuxWatcher = child
	return nil
}

// WatchProxy acknowledges pidfd readiness before capture, then restores on exit.
// The recovery journal, not the runtime directory argument, determines the lease.
func WatchProxy(_ string, pid int) error {
	if pid < 2 {
		return errors.New("invalid proxy owner PID")
	}
	// The inherited ready pipe belongs to the spawning host. If it has already
	// died, restore without opening an unrelated process that reused its PID.
	if os.Getppid() != pid {
		return restoreProxy("")
	}
	fd, err := unix.PidfdOpen(pid, 0)
	if errors.Is(err, unix.ESRCH) {
		return restoreProxy("")
	}
	if err != nil {
		return fmt.Errorf("open proxy owner monitor: %w", err)
	}
	defer unix.Close(fd)
	ack := os.NewFile(3, "proxy-watcher-ready")
	if ack == nil {
		return errors.New("proxy watcher readiness pipe missing")
	}
	info, err := ack.Stat()
	if err != nil || info.Mode()&os.ModeNamedPipe == 0 {
		return errors.Join(errors.New("invalid proxy watcher readiness pipe"), err, ack.Close())
	}
	n, writeErr := ack.Write([]byte{1})
	if writeErr == nil && n != 1 {
		writeErr = io.ErrShortWrite
	}
	if err = errors.Join(writeErr, ack.Close()); err != nil {
		return err
	}
	for {
		fds := []unix.PollFd{{Fd: int32(fd), Events: unix.POLLIN}}
		_, err = unix.Poll(fds, -1)
		if errors.Is(err, unix.EINTR) {
			continue
		}
		if err != nil {
			return err
		}
		if fds[0].Revents&(unix.POLLERR|unix.POLLNVAL) != 0 {
			return errors.New("proxy owner monitor failed")
		}
		if fds[0].Revents&(unix.POLLIN|unix.POLLHUP) != 0 {
			return restoreProxy("")
		}
	}
}
