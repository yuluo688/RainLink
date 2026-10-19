//go:build linux && !android

package linuxmanage

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"syscall"
	"time"

	"rainlink.local/host/internal/linuxinstall"
	"rainlink.local/host/internal/linuxipc"
)

func installationAction(method string) (string, error) {
	switch method {
	case "install":
		return "install-tun", nil
	case "uninstall":
		return "uninstall-tun", nil
	case "recover":
		return "recover-tun-install", nil
	default:
		return "", errors.New("unsupported service operation")
	}
}

type boundedOutput struct{ bytes.Buffer }

func (b *boundedOutput) Write(data []byte) (int, error) {
	if b.Len()+len(data) > 4096 {
		return 0, errors.New("service-management output exceeds bounds")
	}
	return b.Buffer.Write(data)
}

type outcome struct {
	ProtocolVersion int  `json:"protocolVersion"`
	Completed       bool `json:"completed"`
}

func (systemBackend) change(ctx context.Context, method string) (result error) {
	if _, err := installationAction(method); err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return &failure{"cancelled", "服务管理已取消，请重新检查状态"}
	}
	program, err := linuxipc.OpenRootExecutable("/usr/bin/pkexec")
	if err != nil {
		return &failure{"authorization_unavailable", "无法打开系统授权工具 pkexec"}
	}
	defer func() { result = errors.Join(result, program.Close()) }()
	input, control, err := os.Pipe()
	if err != nil {
		return err
	}
	defer func() { result = errors.Join(result, input.Close()) }()
	defer control.Close()
	// Pin the already-running application's inode through procfs. Neither IPC
	// nor PATH can substitute the elevated executable. pkexec may close extra
	// descriptors, so a target /proc/self/fd path would not survive its exec.
	path := fmt.Sprintf("/proc/%d/exe", os.Getpid())
	command := exec.CommandContext(ctx, "/proc/self/fd/3", "--disable-internal-agent", path, "manage-tun-elevated", method)
	command.ExtraFiles = []*os.File{program}
	command.Env = []string{"PATH=/usr/sbin:/usr/bin:/sbin:/bin", "LANG=C", "LC_ALL=C"}
	command.Dir = "/"
	command.Stdin = input
	var stdout, stderr boundedOutput
	command.Stdout, command.Stderr = &stdout, &stderr
	command.Cancel = func() error { return cancelElevation(control, command.Process) }
	command.WaitDelay = 7 * time.Minute
	if err = command.Start(); err != nil {
		return &failure{"authorization_unavailable", "无法启动系统授权，请检查桌面认证服务"}
	}
	_, writeErr := control.Write([]byte{'G'})
	err = command.Wait()
	if ctx.Err() != nil {
		return &failure{"cancelled", "服务管理已取消，请重新检查状态；恢复未完成时可重试恢复安装"}
	}
	var exit *exec.ExitError
	if errors.As(err, &exit) {
		switch exit.ExitCode() {
		case 126:
			return &failure{"authorization_cancelled", "已取消系统授权"}
		case 127:
			return &failure{"authorization_unavailable", "系统授权失败，请检查桌面认证服务"}
		}
	}
	if err != nil || writeErr != nil {
		return &failure{"service_operation_failed", "服务管理未完成，请重新检查状态或恢复安装"}
	}
	var completed outcome
	decoder := json.NewDecoder(bytes.NewReader(stdout.Bytes()))
	decoder.DisallowUnknownFields()
	if decoder.Decode(&completed) != nil || completed.ProtocolVersion != 1 || !completed.Completed ||
		!errors.Is(decoder.Decode(new(any)), io.EOF) {
		return &failure{"invalid_response", "未收到服务安装确认，请重新检查状态"}
	}
	return nil
}

func cancelElevation(control *os.File, process *os.Process) error {
	// Revoke first: even if authorization wins the race, the root worker sees
	// EOF and cancels with durable rollback. pkexec does not read stdin while
	// authenticating; SIGTERM dismisses that pending check while its real UID
	// still belongs to the caller. After it becomes root, EPERM is expected and
	// the pipe remains the only cancellation authority. Never escalate to KILL.
	closeErr := control.Close()
	if errors.Is(closeErr, os.ErrClosed) {
		closeErr = nil
	}
	signalErr := process.Signal(syscall.SIGTERM)
	if errors.Is(signalErr, syscall.EPERM) || errors.Is(signalErr, os.ErrProcessDone) {
		signalErr = nil
	}
	return errors.Join(closeErr, signalErr)
}

// RunElevated is an internal, fixed-action worker. It never reads a password:
// pkexec's desktop agent owns authentication. EOF cancels even a late launch.
func RunElevated(method string, input io.Reader, output io.Writer) error {
	action, err := installationAction(method)
	if err != nil || os.Geteuid() != 0 {
		return errors.New("invalid elevated service operation")
	}
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer cancel()
	var first [1]byte
	if _, err = io.ReadFull(input, first[:]); err != nil || first[0] != 'G' {
		return errors.New("service operation was not granted")
	}
	// Retain a reader for the worker lifetime. More input is invalid and EOF
	// revokes the operation. The broker never sends credentials or parameters.
	go func() {
		var next [1]byte
		_, _ = input.Read(next[:])
		cancel()
	}()
	if err = linuxinstall.Run(ctx, action); err != nil {
		return err
	}
	return json.NewEncoder(output).Encode(outcome{ProtocolVersion: 1, Completed: true})
}
