//go:build linux && !android

package session

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
	"syscall"
	"time"

	"rainlink.local/host/internal/coreprocess"
	"rainlink.local/host/internal/linuxipc"
	"rainlink.local/host/internal/linuxnet"
	"rainlink.local/host/internal/linuxprocess"
	"rainlink.local/host/internal/linuxtun"
)

const (
	installedTUNHost         = "/usr/libexec/rainlink/rainlink-host"
	installedTUNCore         = "/usr/libexec/rainlink/sing-box"
	permissionHelloTimeout   = 5 * time.Second
	permissionCleanupTimeout = 25 * time.Second
)

// LinuxTUNStart is private native IPC data. Only Snapshot may cross the public
// Flutter channel; APIPort and APISecret belong to the ordinary native host.
type LinuxTUNStart struct {
	Snapshot  Snapshot               `json:"snapshot"`
	APIPort   int                    `json:"apiPort"`
	APISecret string                 `json:"apiSecret"`
	Resources linuxtun.Specification `json:"resources"`
}

type managedChild struct {
	command *exec.Cmd
	done    chan struct{}
}

func startManagedChild(command *exec.Cmd) (*managedChild, error) {
	if err := command.Start(); err != nil {
		return nil, err
	}
	child := &managedChild{command: command, done: make(chan struct{})}
	go func() { _ = command.Wait(); close(child.done) }()
	return child, nil
}

func (child *managedChild) stop(ctx context.Context) error {
	if child == nil {
		return nil
	}
	select {
	case <-child.done:
		return nil
	default:
	}
	if err := child.command.Process.Kill(); err != nil && !errors.Is(err, os.ErrProcessDone) {
		return err
	}
	select {
	case <-child.done:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

type linuxTUNSession struct {
	watchdog    *managedChild
	core        *managedChild
	lease       *linuxtun.Lease
	client      *http.Client
	stopMonitor context.CancelFunc
	stage       string
	logs        *logBuffer
	stdout      *coreLogWriter
	stderr      *coreLogWriter
}

func (session *linuxTUNSession) close() (result error) {
	if session.stopMonitor != nil {
		session.stopMonitor()
	}
	ctx, cancel := context.WithTimeout(context.Background(), permissionCleanupTimeout)
	defer cancel()
	if session.client != nil {
		session.client.CloseIdleConnections()
	}
	stop, stopCancel := context.WithTimeout(ctx, 4*time.Second)
	err := session.core.stop(stop)
	stopCancel()
	result = errors.Join(result, err)
	if err == nil {
		if session.stdout != nil {
			session.stdout.finish()
		}
		if session.stderr != nil {
			session.stderr.finish()
		}
	}
	if session.lease != nil {
		if err == nil {
			result = errors.Join(result, session.lease.Restore(ctx))
		}
		result = errors.Join(result, session.lease.Close())
		session.lease = nil
	}
	// A failed cleanup keeps the independent watchdog alive. When this guardian
	// exits it gets one more chance to restore the retained journal.
	if result == nil {
		stop, stopCancel = context.WithTimeout(ctx, 2*time.Second)
		result = session.watchdog.stop(stop)
		stopCancel()
	}
	if session.logs != nil {
		if result == nil {
			session.logs.append("info", "host", "TUN 会话清理已完成，网络资源已恢复")
		} else {
			session.logs.append("error", "host", "TUN 网络资源恢复尚未确认，请重试断开")
		}
	}
	return result
}

func startTUNWatchdog(ctx context.Context, binary *os.File) (_ *managedChild, result error) {
	identity, alive, err := linuxprocess.ReadIdentity(os.Getpid())
	if err != nil || !alive {
		return nil, errors.Join(linuxprocess.ErrNotAlive, err)
	}
	reader, writer, err := os.Pipe()
	if err != nil {
		return nil, err
	}
	defer func() { result = errors.Join(result, reader.Close()) }()
	command := exec.Command("/proc/self/fd/4", "watch-tun", strconv.Itoa(identity.PID), strconv.FormatUint(identity.Start, 10), identity.Boot)
	command.ExtraFiles = []*os.File{writer, binary}
	command.Env = []string{"PATH=", "LANG=C", "LC_ALL=C"}
	command.Dir = "/"
	command.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	child, err := startManagedChild(command)
	closeErr := writer.Close()
	if err != nil {
		return nil, errors.Join(err, closeErr)
	}
	keep := false
	defer func() {
		if !keep {
			cleanup, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer cancel()
			result = errors.Join(result, child.stop(cleanup))
		}
	}()
	if closeErr != nil {
		return nil, closeErr
	}
	deadline := time.Now().Add(3 * time.Second)
	if limit, ok := ctx.Deadline(); ok && limit.Before(deadline) {
		deadline = limit
	}
	if err = reader.SetReadDeadline(deadline); err != nil {
		return nil, err
	}
	stop := context.AfterFunc(ctx, func() { _ = reader.Close() })
	defer stop()
	var ready [1]byte
	if _, err = io.ReadFull(reader, ready[:]); err != nil || ready[0] != 1 {
		return nil, errors.Join(errors.New("TUN watchdog did not become ready"), err)
	}
	if err = ctx.Err(); err != nil {
		return nil, err
	}
	select {
	case <-child.done:
		return nil, errors.New("TUN watchdog exited before capture")
	default:
	}
	keep = true
	return child, nil
}

func confirmManagedTUN(ctx context.Context, resources linuxtun.Specification) error {
	if _, err := resources.ExpectedRules(); err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	for {
		ready, err := observeManagedTUN(ctx, resources)
		if err != nil {
			return err
		}
		if ready {
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(20 * time.Millisecond):
		}
	}
}

func observeManagedTUN(ctx context.Context, resources linuxtun.Specification) (bool, error) {
	expected, err := resources.ExpectedRules()
	if err != nil {
		return false, err
	}
	state, err := linuxnet.Read(ctx)
	if err != nil {
		return false, err
	}
	index := uint32(0)
	for _, link := range state.Links {
		if link.Name == resources.Name && link.Kind == "tun" && link.Up() {
			index = link.Index
		}
	}
	matches := 0
	for _, required := range expected {
		count := 0
		for _, rule := range state.Rules {
			same, err := linuxnet.SameRule(required, rule)
			if err != nil {
				return false, err
			}
			if same {
				count++
			}
		}
		if count == 1 {
			matches++
		}
	}
	families := map[uint8]bool{}
	for _, route := range state.Routes {
		if route.Table == resources.Table && route.Interface == index && index != 0 {
			families[route.Family] = true
		}
	}
	return index != 0 && matches == len(expected) && families[syscall.AF_INET] && families[syscall.AF_INET6], nil
}

func (session *linuxTUNSession) start(ctx context.Context, peer *linuxipc.Peer, raw []byte, lostWatchdog context.CancelFunc) (LinuxTUNStart, error) {
	session.stage = "authorization"
	if err := linuxipc.AuthorizeTUN(ctx, peer); err != nil {
		return LinuxTUNStart{}, err
	}
	session.logs.append("info", "host", "TUN 系统授权已通过")
	session.stage = "trusted-binaries"
	self, err := linuxipc.OpenRootExecutable(installedTUNHost)
	if err != nil {
		return LinuxTUNStart{}, errors.New("installed permission host is not trusted")
	}
	defer self.Close()
	core, err := linuxipc.OpenRootExecutable(installedTUNCore)
	if err != nil {
		return LinuxTUNStart{}, errors.New("installed TUN core is not trusted")
	}
	defer core.Close()
	if !coreprocess.TrustedFile(core) {
		return LinuxTUNStart{}, errors.New("installed TUN core does not match the locked release")
	}
	session.stage = "watchdog"
	session.watchdog, err = startTUNWatchdog(ctx, self)
	if err != nil {
		return LinuxTUNStart{}, err
	}
	monitor, stopMonitor := context.WithCancel(context.Background())
	session.stopMonitor = stopMonitor
	go func() {
		select {
		case <-session.watchdog.done:
			if monitor.Err() == nil {
				lostWatchdog()
			}
		case <-monitor.Done():
		}
	}()
	session.stage = "resource-lease"
	controller, err := linuxtun.New()
	if err != nil {
		return LinuxTUNStart{}, err
	}
	session.lease, err = controller.Acquire(ctx, newTUNInterfaceName())
	if err != nil {
		return LinuxTUNStart{}, err
	}
	session.stage = "compiler"
	compiled, err := CompileLinuxTUN(ctx, raw, session.lease.Specification())
	if err != nil {
		return LinuxTUNStart{}, err
	}
	session.stage = "core-validation"
	check := exec.CommandContext(ctx, "/proc/self/fd/3", "check", "-c", "stdin")
	check.ExtraFiles = []*os.File{core}
	check.Env = []string{"PATH=", "LANG=C", "LC_ALL=C"}
	check.Dir = "/"
	check.Stdin = strings.NewReader(compiled.Configuration)
	checkStdout := &coreLogWriter{logs: session.logs, secrets: compiled.SecretValues}
	checkStderr := &coreLogWriter{logs: session.logs, secrets: compiled.SecretValues}
	check.Stdout, check.Stderr = checkStdout, checkStderr
	check.WaitDelay = time.Second
	check.SysProcAttr = &syscall.SysProcAttr{Pdeathsig: syscall.SIGKILL}
	runtime.LockOSThread()
	err = check.Run()
	runtime.UnlockOSThread()
	checkStdout.finish()
	checkStderr.finish()
	if err != nil {
		return LinuxTUNStart{}, errors.New("controlled TUN configuration was rejected")
	}
	if err = peer.Check(); err != nil {
		return LinuxTUNStart{}, err
	}
	select {
	case <-session.watchdog.done:
		return LinuxTUNStart{}, errors.New("TUN watchdog exited before core start")
	default:
	}
	session.stage = "core-start"
	command := exec.Command("/proc/self/fd/3", "run", "-c", "stdin")
	command.ExtraFiles = []*os.File{core}
	command.Env = []string{"PATH=", "LANG=C", "LC_ALL=C"}
	command.Dir = "/"
	session.stdout = &coreLogWriter{logs: session.logs, secrets: compiled.SecretValues}
	session.stderr = &coreLogWriter{logs: session.logs, secrets: compiled.SecretValues}
	command.Stdout, command.Stderr = session.stdout, session.stderr
	command.WaitDelay = time.Second
	input, err := command.StdinPipe()
	if err != nil {
		return LinuxTUNStart{}, err
	}
	defer input.Close()
	pipe, ok := input.(*os.File)
	if !ok {
		return LinuxTUNStart{}, errors.New("core input does not support bounded writes")
	}
	session.core, err = startManagedChild(command)
	if err != nil {
		return LinuxTUNStart{}, err
	}
	session.stage = "core-binding"
	if err = session.lease.BindCore(ctx, command.Process.Pid); err != nil {
		return LinuxTUNStart{}, err
	}
	if err = ctx.Err(); err != nil {
		return LinuxTUNStart{}, err
	}
	session.stage = "core-input"
	deadline := time.Now().Add(5 * time.Second)
	if limit, ok := ctx.Deadline(); ok && limit.Before(deadline) {
		deadline = limit
	}
	if err = pipe.SetWriteDeadline(deadline); err != nil {
		return LinuxTUNStart{}, err
	}
	stopInput := context.AfterFunc(ctx, func() { _ = input.Close() })
	defer stopInput()
	if err = ctx.Err(); err != nil {
		return LinuxTUNStart{}, err
	}
	// No resource can be created before the child identity is durable. If the
	// guardian dies before this write, pipe EOF makes the unconfigured core exit.
	if _, err = io.WriteString(input, compiled.Configuration); err != nil {
		return LinuxTUNStart{}, errors.New("cannot pass private TUN configuration")
	}
	if err = input.Close(); err != nil {
		return LinuxTUNStart{}, err
	}
	session.client = &http.Client{Timeout: 2 * time.Second, Transport: &http.Transport{Proxy: nil}}
	running := &runningCore{done: session.core.done, api: fmt.Sprintf("http://127.0.0.1:%d", compiled.APIPort), secret: compiled.APISecret, client: session.client}
	session.stage = "api-readiness"
	if err = running.waitReady(ctx); err != nil {
		return LinuxTUNStart{}, err
	}
	session.stage = "capture-readiness"
	if err = confirmManagedTUN(ctx, session.lease.Specification()); err != nil {
		return LinuxTUNStart{}, err
	}
	if err = peer.Check(); err != nil {
		return LinuxTUNStart{}, err
	}
	if err = ctx.Err(); err != nil {
		return LinuxTUNStart{}, err
	}
	compiled.Snapshot.Phase = "connected"
	return LinuxTUNStart{Snapshot: compiled.Snapshot, APIPort: compiled.APIPort, APISecret: compiled.APISecret, Resources: session.lease.Specification()}, nil
}

func permissionFailure(err error) string {
	if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
		return "cancelled"
	}
	if errors.Is(err, linuxipc.ErrPermissionDenied) {
		return "permission_denied"
	}
	if errors.Is(err, linuxipc.ErrAuthorizationUnavailable) {
		return "authorization_unavailable"
	}
	if errors.Is(err, linuxtun.ErrOwned) {
		return "already_connected"
	}
	var failure *Failure
	if errors.As(err, &failure) {
		return failure.Code
	}
	return "tun_start_failed"
}

// ServeLinuxTUN owns one socket-activated root session. An unprivileged host
// supplies validated domain input; authorization, binaries and resource leases
// remain under root control. EOF, caller exit and watchdog loss stop capture.
// It does not install the service or enable the public Linux TUN capability.
func ServeLinuxTUN(parent context.Context, connection *net.UnixConn) (result error) {
	if os.Geteuid() != 0 || connection == nil {
		return errors.New("TUN permission service requires root and an inherited Unix stream")
	}
	defer connection.Close()
	peer, err := linuxipc.Inspect(connection)
	if err != nil {
		return err
	}
	defer peer.Close()
	ctx, cancel := context.WithCancel(parent)
	defer cancel()
	interrupt := context.AfterFunc(ctx, func() { _ = connection.Close() })
	defer interrupt()
	codec := linuxipc.NewCodec(connection)
	hello, helloCancel := context.WithTimeout(ctx, permissionHelloTimeout)
	raw, err := codec.Read(hello)
	helloCancel()
	if err != nil {
		return err
	}
	start, err := linuxipc.ParseCommand(raw)
	clear(raw)
	if err != nil {
		return linuxipc.ErrCommand
	}
	logsEnabled := start.Method == permissionLogHello
	if start.Method == "hello" || logsEnabled {
		// SO_PEERCRED on a socket-activated stream identifies the listener's
		// creator (possibly systemd), not this guardian. Supply our own bounded
		// lifetime before accepting a start. An ordinary host can then wait for
		// this exact guardian to exit before confirming an interrupted startup.
		identity, alive, err := linuxprocess.ReadIdentity(os.Getpid())
		if err != nil || !alive {
			return errors.Join(linuxprocess.ErrNotAlive, err)
		}
		hello, helloCancel := context.WithTimeout(ctx, permissionHelloTimeout)
		err = codec.Write(hello, linuxipc.Reply{Version: linuxipc.ProtocolVersion, ID: start.ID, Result: identity})
		if err == nil {
			raw, err = codec.Read(hello)
		}
		helloCancel()
		if err != nil {
			return err
		}
		previousID := start.ID
		start, err = linuxipc.ParseCommand(raw)
		clear(raw)
		if err != nil || start.Method != "start" || start.ID <= previousID {
			clear(start.Payload)
			return linuxipc.ErrCommand
		}
	}
	if start.Method == "idle" {
		return replyLinuxTUNIdle(ctx, codec, peer, start.ID)
	}
	if start.Method != "start" {
		return linuxipc.ErrCommand
	}
	defer clear(start.Payload)
	operation, stopOperation := context.WithTimeout(ctx, 75*time.Second)
	defer stopOperation()
	stopRequest := make(chan linuxipc.Command, 1)
	readerDone := make(chan struct{})
	go func() {
		defer close(readerDone)
		raw, err := codec.Read(ctx)
		if err != nil {
			cancel()
			return
		}
		command, err := linuxipc.ParseCommand(raw)
		clear(raw)
		if err != nil || command.Method != "stop" || command.ID <= start.ID {
			clear(command.Payload)
			cancel()
			return
		}
		stopRequest <- command
		stopOperation()
	}()
	peerDone := make(chan struct{})
	go func() { defer close(peerDone); _ = peer.Wait(ctx); cancel() }()
	defer func() { cancel(); <-readerDone; <-peerDone }()
	session := &linuxTUNSession{logs: newLogBuffer()}
	var sender *linuxTUNLogSender
	if logsEnabled {
		sender = startLinuxTUNLogs(ctx, codec, session.logs, cancel)
		defer sender.stop()
	}
	closed := false
	defer func() {
		if !closed {
			result = errors.Join(result, session.close())
		}
	}()
	started, err := session.start(operation, peer, start.Payload, cancel)
	clear(start.Payload)
	if err != nil {
		// Only this fixed stage label enters the system journal, never a core
		// response, command payload or original credential-bearing error text.
		fmt.Fprintln(os.Stderr, "TUN permission setup failed at", session.stage)
		session.logs.append("error", "host", permissionStageFailure(session.stage, err))
		cleanup := session.close()
		closed = true
		code := permissionFailure(err)
		if cleanup != nil {
			code = "recovery_pending"
		}
		if ctx.Err() == nil {
			if logErr := sender.finish(ctx); logErr != nil {
				return errors.Join(logErr, cleanup)
			}
			write, writeCancel := context.WithTimeout(ctx, 2*time.Second)
			writeErr := codec.Write(write, linuxipc.Reply{Version: linuxipc.ProtocolVersion, ID: start.ID, Error: code})
			writeCancel()
			if writeErr != nil {
				return errors.Join(writeErr, cleanup)
			}
		}
		return cleanup
	}
	write, writeCancel := context.WithTimeout(ctx, 2*time.Second)
	err = codec.Write(write, linuxipc.Reply{Version: linuxipc.ProtocolVersion, ID: start.ID, Result: started})
	writeCancel()
	if err != nil {
		return err
	}
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-session.core.done:
		session.logs.append("error", "host", "TUN 网络核心意外退出，正在恢复网络资源")
		cleanup := session.close()
		closed = true
		return errors.Join(errors.New("managed TUN core exited"), cleanup, sender.finish(ctx))
	case stop := <-stopRequest:
		cleanup := session.close()
		closed = true
		if logErr := sender.finish(ctx); logErr != nil {
			return errors.Join(logErr, cleanup)
		}
		write, writeCancel := context.WithTimeout(ctx, 2*time.Second)
		defer writeCancel()
		reply := linuxipc.Reply{Version: linuxipc.ProtocolVersion, ID: stop.ID, Result: map[string]bool{"stopped": true}}
		if cleanup != nil {
			reply.Result = nil
			reply.Error = "recovery_pending"
		}
		return errors.Join(cleanup, codec.Write(write, reply))
	}
}

// This read-only receipt contains no session data and requires no polkit
// prompt. Mutating recovery remains exclusively with the owning guardian,
// watchdog and root service cleanup; this path cannot stop another user.
func replyLinuxTUNIdle(ctx context.Context, codec *linuxipc.Codec, peer *linuxipc.Peer, id int) error {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	if err := peer.Check(); err != nil {
		return err
	}
	controller, err := linuxtun.New()
	if err == nil {
		err = controller.ConfirmIdle(ctx)
	}
	reply := linuxipc.Reply{Version: linuxipc.ProtocolVersion, ID: id, Result: map[string]bool{"idle": err == nil}}
	if err != nil && !errors.Is(err, linuxtun.ErrOwned) && !errors.Is(err, linuxtun.ErrPending) {
		reply.Result, reply.Error = nil, "recovery_pending"
	}
	if err := peer.Check(); err != nil {
		return err
	}
	return codec.Write(ctx, reply)
}
