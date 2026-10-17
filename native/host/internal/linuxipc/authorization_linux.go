//go:build linux && !android

package linuxipc

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"runtime"
	"syscall"
	"time"
)

const (
	// TUNAction is fixed in the installed polkit policy, never supplied by IPC.
	TUNAction            = "org.rainlink.tun.manage"
	authorizationTimeout = 60 * time.Second
)

var (
	// ErrPermissionDenied distinguishes cancellation of a system prompt.
	ErrPermissionDenied = errors.New("TUN authorization was declined")
	// ErrAuthorizationUnavailable retains configuration and system failures.
	ErrAuthorizationUnavailable = errors.New("system TUN authorization is unavailable")
)

// AuthorizeTUN asks the system authorization authority for the socket creator's
// exact PID,start-time,UID subject. Peer authentication is checked again after
// the prompt; neither root identity nor a previous approval bypasses this call.
func AuthorizeTUN(ctx context.Context, peer *Peer) (result error) {
	if os.Geteuid() != 0 {
		return ErrAuthorizationUnavailable
	}
	subject, err := peer.Subject()
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(ctx, authorizationTimeout)
	defer cancel()
	file, err := OpenRootExecutable("/usr/bin/pkcheck")
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	defer func() { result = errors.Join(result, file.Close()) }()
	command := exec.CommandContext(ctx, "/proc/self/fd/3", "--action-id", TUNAction, "--process", subject, "--allow-user-interaction")
	command.ExtraFiles = []*os.File{file}
	command.Env = []string{"PATH=/usr/sbin:/usr/bin:/sbin:/bin", "LANG=C", "LC_ALL=C"}
	command.Dir = "/"
	command.WaitDelay = time.Second
	command.SysProcAttr = &syscall.SysProcAttr{Pdeathsig: syscall.SIGKILL}
	// Pdeathsig belongs to the creating OS thread, which must live through Wait.
	runtime.LockOSThread()
	err = command.Run()
	runtime.UnlockOSThread()
	if ctx.Err() != nil {
		return ctx.Err()
	}
	if err != nil {
		var exit *exec.ExitError
		if errors.As(err, &exit) && (exit.ExitCode() == 1 || exit.ExitCode() == 126) {
			return ErrPermissionDenied
		}
		return ErrAuthorizationUnavailable
	}
	return peer.Check()
}
