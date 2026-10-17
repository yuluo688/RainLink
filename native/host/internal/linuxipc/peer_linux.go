//go:build linux && !android

// Package linuxipc provides bounded private transport for Linux permission
// helpers. Kernel peer identity does not itself grant permission to use TUN.
package linuxipc

import (
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"sync/atomic"

	"golang.org/x/sys/unix"
	"rainlink.local/host/internal/linuxprocess"
)

// Peer holds a kernel-authenticated socket peer and its pinned process lifetime.
// Callers must separately authorize its fixed action, then Check again before
// starting privileged work. No identity supplied in a message is trusted.
type Peer struct {
	credentials unix.Ucred
	identity    linuxprocess.Identity
	namespace   string
	process     *linuxprocess.Handle
	closed      atomic.Bool
}

// Inspect accepts only a connected Unix stream in this network namespace.
func Inspect(connection *net.UnixConn) (_ *Peer, result error) {
	return inspect(connection, false)
}

// InspectRootService authenticates the privileged endpoint from an ordinary
// host. Unprivileged processes cannot read a root process's namespace symlink;
// the root server must instead enforce its caller's namespace with Inspect.
// The client must also connect through the installed, root-controlled socket.
func InspectRootService(connection *net.UnixConn) (*Peer, error) {
	return inspect(connection, true)
}

func inspect(connection *net.UnixConn, rootService bool) (_ *Peer, result error) {
	if connection == nil {
		return nil, errors.New("private socket is missing")
	}
	raw, err := connection.SyscallConn()
	if err != nil {
		return nil, err
	}
	var credentials *unix.Ucred
	var identity linuxprocess.Identity
	var process *linuxprocess.Handle
	keep := false
	defer func() {
		if !keep && process != nil {
			result = errors.Join(result, process.Close())
		}
	}()
	var socketErr error
	err = raw.Control(func(fd uintptr) {
		var kind int
		kind, socketErr = unix.GetsockoptInt(int(fd), unix.SOL_SOCKET, unix.SO_TYPE)
		if socketErr == nil && kind != unix.SOCK_STREAM {
			socketErr = errors.New("private transport requires a Unix stream")
		}
		if socketErr == nil {
			credentials, socketErr = unix.GetsockoptUcred(int(fd), unix.SOL_SOCKET, unix.SO_PEERCRED)
		}
		if socketErr == nil && (credentials == nil || credentials.Pid < 1 || (rootService && credentials.Uid != 0)) {
			socketErr = errors.New("private socket peer identity is not permitted")
		}
		if socketErr == nil {
			var alive bool
			identity, alive, socketErr = linuxprocess.ReadIdentity(int(credentials.Pid))
			if socketErr == nil && !alive {
				socketErr = linuxprocess.ErrNotAlive
			}
			if socketErr == nil {
				process, socketErr = linuxprocess.OpenSocketPeer(int(fd), identity)
			}
		}
	})
	if err != nil || socketErr != nil {
		return nil, errors.Join(err, socketErr)
	}
	if credentials == nil || process == nil {
		return nil, errors.New("private socket peer identity is unavailable")
	}
	namespace := ""
	if !rootService {
		peerNamespace, err := linuxprocess.NetworkNamespace(identity.PID)
		if err != nil {
			return nil, err
		}
		namespace, err = linuxprocess.NetworkNamespace(os.Getpid())
		if err != nil || peerNamespace != namespace {
			return nil, errors.Join(errors.New("private socket peer is in a different network namespace"), err)
		}
	}
	peer := &Peer{credentials: *credentials, identity: identity, namespace: namespace, process: process}
	if err = peer.Check(); err != nil {
		return nil, err
	}
	keep = true
	return peer, nil
}

// UID is the socket creator's UID reported by the kernel, never message data.
func (peer *Peer) UID() uint32 { return peer.credentials.Uid }

// Identity provides the start-time-bound process subject for system authorization.
func (peer *Peer) Identity() linuxprocess.Identity { return peer.identity }

// Check must succeed after authorization as well as before privileged actions.
func (peer *Peer) Check() error {
	if peer == nil || peer.process == nil || !peer.identity.Valid() {
		return errors.New("private socket peer has not been inspected")
	}
	if peer.closed.Load() {
		return os.ErrClosed
	}
	if err := peer.process.CheckAlive(); err != nil {
		return err
	}
	alive, err := linuxprocess.Alive(peer.identity)
	if err != nil {
		return err
	}
	if !alive {
		return linuxprocess.ErrNotAlive
	}
	if err = linuxprocess.VerifyUID(peer.identity, peer.credentials.Uid); err != nil {
		return err
	}
	if peer.namespace != "" {
		namespace, err := linuxprocess.NetworkNamespace(peer.identity.PID)
		if err != nil || namespace != peer.namespace {
			return errors.Join(errors.New("private socket peer namespace changed"), err)
		}
	}
	return peer.process.CheckAlive()
}

// RequireRoot lets an ordinary host reject an impostor permission service.
// A root peer is still required to obey the controlled session protocol.
func (peer *Peer) RequireRoot() error {
	if err := peer.Check(); err != nil {
		return err
	}
	if peer.credentials.Uid != 0 {
		return errors.New("permission service is not root-owned")
	}
	return nil
}

// Subject returns pkcheck's PID,start-time,UID form for the live socket creator.
func (peer *Peer) Subject() (string, error) {
	if err := peer.Check(); err != nil {
		return "", err
	}
	return fmt.Sprintf("%d,%d,%d", peer.identity.PID, peer.identity.Start, peer.credentials.Uid), nil
}

// Wait observes the pinned peer's exit without signaling it.
func (peer *Peer) Wait(ctx context.Context) error {
	if peer == nil || peer.process == nil {
		return errors.New("private socket peer has not been inspected")
	}
	if peer.closed.Load() {
		return os.ErrClosed
	}
	return peer.process.Wait(ctx)
}

// Close releases monitoring only; it does not close the caller-owned socket.
func (peer *Peer) Close() error {
	if peer == nil || peer.process == nil {
		return nil
	}
	peer.closed.Store(true)
	return peer.process.Close()
}
