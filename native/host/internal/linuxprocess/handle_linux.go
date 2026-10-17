//go:build linux && !android

package linuxprocess

import (
	"context"
	"errors"
	"fmt"
	"os"
	"sync"

	"golang.org/x/sys/unix"
)

// ErrNotAlive means the recorded identity no longer owns its PID.
var ErrNotAlive = errors.New("recorded process is no longer alive")

const cancellationPollMillis = 100

// Handle pins a process lifetime in the kernel. Signals never fall back to a
// numeric PID, including when that PID has been reused after Open.
type Handle struct {
	mu   sync.Mutex
	fd   int
	open bool
}

// Open verifies the persisted identity on both sides of pidfd_open. An exited
// process, PID reuse or a different boot cannot authorize signaling a new owner.
func Open(identity Identity) (*Handle, error) {
	if !identity.Valid() {
		return nil, errors.New("invalid process monitor identity")
	}
	current, alive, err := ReadIdentity(identity.PID)
	if err != nil {
		return nil, err
	}
	if !alive || current != identity {
		return nil, ErrNotAlive
	}
	fd, err := unix.PidfdOpen(identity.PID, 0)
	if errors.Is(err, unix.ESRCH) {
		return nil, ErrNotAlive
	}
	if err != nil {
		return nil, fmt.Errorf("open process lifetime monitor: %w", err)
	}
	current, alive, err = ReadIdentity(identity.PID)
	if err != nil || !alive || current != identity {
		closeErr := unix.Close(fd)
		if err == nil {
			err = ErrNotAlive
		}
		return nil, errors.Join(err, closeErr)
	}
	return &Handle{fd: fd, open: true}, nil
}

// OpenSocketPeer pins the actual socket creator, including when its numeric PID
// has already been reused. SO_PEERPIDFD requires Linux 6.5 or newer; permission
// IPC fails closed on older kernels instead of authorizing a replacement PID.
func OpenSocketPeer(socket int, identity Identity) (_ *Handle, result error) {
	if !identity.Valid() {
		return nil, errors.New("invalid socket peer process identity")
	}
	credentials, err := unix.GetsockoptUcred(socket, unix.SOL_SOCKET, unix.SO_PEERCRED)
	if err != nil || credentials == nil || int(credentials.Pid) != identity.PID {
		return nil, errors.Join(errors.New("socket creator does not match process identity"), err)
	}
	fd, err := unix.GetsockoptInt(socket, unix.SOL_SOCKET, unix.SO_PEERPIDFD)
	if err != nil {
		return nil, fmt.Errorf("pin socket peer lifetime (requires Linux 6.5): %w", err)
	}
	unix.CloseOnExec(fd)
	handle := &Handle{fd: fd, open: true}
	keep := false
	defer func() {
		if !keep {
			result = errors.Join(result, handle.Close())
		}
	}()
	if err = handle.CheckAlive(); err != nil {
		return nil, err
	}
	current, alive, err := ReadIdentity(identity.PID)
	if err != nil {
		return nil, err
	}
	if !alive || current != identity {
		return nil, ErrNotAlive
	}
	// Checking the pinned creator on both sides of procfs prevents reading a
	// replacement process's identity after the socket creator has exited.
	if err = handle.CheckAlive(); err != nil {
		return nil, err
	}
	keep = true
	return handle, nil
}

// CheckAlive checks the pinned lifetime without waiting or trusting its PID.
func (handle *Handle) CheckAlive() (result error) {
	fd, err := handle.duplicate()
	if err != nil {
		return err
	}
	defer func() { result = errors.Join(result, unix.Close(fd)) }()
	for {
		poll := []unix.PollFd{{Fd: int32(fd), Events: unix.POLLIN}}
		_, err = unix.Poll(poll, 0)
		if errors.Is(err, unix.EINTR) {
			continue
		}
		if err != nil {
			return err
		}
		if poll[0].Revents&(unix.POLLERR|unix.POLLNVAL) != 0 {
			return errors.New("process lifetime monitor failed")
		}
		if poll[0].Revents&(unix.POLLIN|unix.POLLHUP) != 0 {
			return ErrNotAlive
		}
		return nil
	}
}

func (handle *Handle) duplicate() (int, error) {
	handle.mu.Lock()
	defer handle.mu.Unlock()
	if !handle.open {
		return -1, os.ErrClosed
	}
	return unix.FcntlInt(uintptr(handle.fd), unix.F_DUPFD_CLOEXEC, 0)
}

// Wait returns only after this exact process has exited, or its context ends.
// Bounded kernel waits keep cancellation responsive without helper goroutines.
func (handle *Handle) Wait(ctx context.Context) (result error) {
	if err := ctx.Err(); err != nil {
		return err
	}
	fd, err := handle.duplicate()
	if err != nil {
		return err
	}
	defer func() { result = errors.Join(result, unix.Close(fd)) }()
	waitMillis := cancellationPollMillis
	if ctx.Done() == nil {
		// A background watchdog sleeps until the kernel reports exit, with no
		// periodic wakeups. Cancellable waits stay bounded without a goroutine.
		waitMillis = -1
	}
	for {
		if err = ctx.Err(); err != nil {
			return err
		}
		poll := []unix.PollFd{{Fd: int32(fd), Events: unix.POLLIN}}
		_, err = unix.Poll(poll, waitMillis)
		if errors.Is(err, unix.EINTR) {
			continue
		}
		if err != nil {
			return err
		}
		if poll[0].Revents&(unix.POLLERR|unix.POLLNVAL) != 0 {
			return errors.New("process lifetime monitor failed")
		}
		if poll[0].Revents&(unix.POLLIN|unix.POLLHUP) != 0 {
			return nil
		}
	}
}

// Signal supports only the two shutdown stages used by resource guardians.
func (handle *Handle) Signal(signal unix.Signal) (result error) {
	if signal != unix.SIGTERM && signal != unix.SIGKILL {
		return errors.New("unsupported process shutdown signal")
	}
	fd, err := handle.duplicate()
	if err != nil {
		return err
	}
	defer func() { result = errors.Join(result, unix.Close(fd)) }()
	if err = unix.PidfdSendSignal(fd, signal, nil, 0); errors.Is(err, unix.ESRCH) {
		return ErrNotAlive
	}
	return err
}

// Close releases the monitor; it never terminates the process.
func (handle *Handle) Close() error {
	handle.mu.Lock()
	defer handle.mu.Unlock()
	if !handle.open {
		return nil
	}
	err := unix.Close(handle.fd)
	handle.fd = -1
	handle.open = false
	return err
}
