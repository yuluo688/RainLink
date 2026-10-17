//go:build linux && !android

package session

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"rainlink.local/host/internal/linuxipc"
	"rainlink.local/host/internal/linuxprocess"
)

const installedTUNSocket = "/run/rainlink/tun.sock"

// linuxTUNClient is private to the native host. It never exposes credentials or
// the core API secret through Flutter; loss of transport is not a stop receipt.
type linuxTUNClient struct {
	connection *net.UnixConn
	peer       *linuxipc.Peer
	codec      *linuxipc.Codec
	started    LinuxTUNStart
	guardian   linuxprocess.Identity
	logs       *linuxTUNLogReceiver
	done       chan struct{}
	stopOnce   sync.Once
	requested  atomic.Bool
	terminal   error // Written before done closes; immutable afterwards.
}

func linuxTUNFailure(code string) error {
	switch code {
	case "permission_denied":
		return fail("tun_permission_denied", "已取消 TUN 权限申请，未启用 TUN")
	case "authorization_unavailable":
		return fail("tun_authorization_unavailable", "TUN 权限服务无法完成系统授权，请检查 polkit 与桌面认证服务")
	case "already_connected":
		return fail("already_connected", "已有 RainLink TUN 会话，请先断开")
	case "cancelled":
		return fail("cancelled", "TUN 连接已取消")
	case "recovery_pending":
		return fail("tun_restore_failed", "权限服务尚未确认网络恢复，请稍后重试断开")
	default:
		return fail("tun_start_failed", "TUN 权限服务未能建立连接，请检查服务与网络配置")
	}
}

func startLinuxTUNClient(ctx context.Context, request MobileRequest, logs *logBuffer) (*linuxTUNClient, error) {
	return dialLinuxTUNClientWithLogs(ctx, installedTUNSocket, request, logs)
}

// This marker retains a trusted guardian lifetime when a start may have reached
// root. Only its exit followed by the idle receipt can clear uncertain recovery.
type linuxTUNUnconfirmedStart struct {
	error
	guardian linuxprocess.Identity
}

func (err *linuxTUNUnconfirmedStart) Unwrap() error { return err.error }

func dialLinuxTUNClient(ctx context.Context, socket string, request MobileRequest) (_ *linuxTUNClient, result error) {
	return dialLinuxTUNClientWithLogs(ctx, socket, request, nil)
}

func dialLinuxTUNClientWithLogs(ctx context.Context, socket string, request MobileRequest, logs *logBuffer) (_ *linuxTUNClient, result error) {
	ctx, cancel := context.WithTimeout(ctx, 80*time.Second)
	defer cancel()
	if ctx.Err() != nil {
		return nil, fail("cancelled", "TUN 连接已取消")
	}
	connection, peer, err := linuxipc.DialRootService(ctx, socket)
	if err != nil {
		if ctx.Err() != nil || errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
			return nil, fail("cancelled", "TUN 连接已取消")
		}
		return nil, fail("tun_service_unavailable", "未找到可信的 TUN 权限服务，请检查服务安装状态")
	}
	keep := false
	defer func() {
		if !keep {
			_ = connection.Close()
			_ = peer.Close()
		}
	}()
	// Cancellation during polkit/startup closes the private transport and asks
	// the guardian to recover. Its lifetime stops depending on this operation
	// context after the successful receipt has been fully validated.
	aborted := make(chan struct{})
	abort := context.AfterFunc(ctx, func() { _ = connection.Close(); close(aborted) })
	startupStopped := false
	defer func() {
		if !startupStopped && !abort() {
			<-aborted
		}
	}()
	codec := linuxipc.NewCodec(connection)
	receiver := newLinuxTUNLogReceiver(logs, request)
	guardian, err := linuxTUNHello(ctx, codec, receiver != nil)
	if err != nil {
		return nil, err
	}
	attempted, rejected := false, false
	defer func() {
		if attempted && !rejected && !keep && result != nil {
			result = &linuxTUNUnconfirmedStart{error: result, guardian: guardian}
		}
	}()
	raw, err := json.Marshal(request)
	if err != nil {
		return nil, fail("invalid_request", "TUN 连接参数无效")
	}
	attempted = true
	err = codec.Write(ctx, linuxipc.Command{Version: linuxipc.ProtocolVersion, ID: 2, Method: "start", Payload: raw})
	clear(raw)
	if err != nil {
		return nil, linuxTUNTransportFailure(ctx, err)
	}
	for {
		raw, err = codec.Read(ctx)
		if err != nil {
			return nil, linuxTUNTransportFailure(ctx, err)
		}
		event, logErr := receiver.receive(raw)
		if logErr != nil {
			clear(raw)
			return nil, fail("tun_service_invalid_reply", "TUN 权限服务返回了无效的日志状态")
		}
		if !event {
			break
		}
		clear(raw)
	}
	defer clear(raw)
	var reply struct {
		Version int            `json:"version"`
		ID      int            `json:"id"`
		Result  *LinuxTUNStart `json:"result,omitempty"`
		Error   string         `json:"error,omitempty"`
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err = decoder.Decode(&reply); err != nil || reply.Version != linuxipc.ProtocolVersion || reply.ID != 2 || (reply.Result == nil) == (reply.Error == "") {
		return nil, fail("tun_service_invalid_reply", "TUN 权限服务返回了无效的启动状态")
	}
	if reply.Error != "" {
		rejected = reply.Error != "recovery_pending"
		return nil, linuxTUNFailure(reply.Error)
	}
	started := *reply.Result
	_, resourceErr := started.Resources.ExpectedRules()
	if started.Snapshot.Phase != "connected" || !started.Snapshot.TUN || started.Snapshot.SystemProxy || started.Snapshot.SessionID == "" ||
		!strings.HasPrefix(started.Snapshot.TUNInterface, "rl-") || len(started.Snapshot.TUNInterface) > 15 ||
		started.APIPort < 1024 || started.APIPort > 65535 || len(started.APISecret) < 16 || len(started.APISecret) > 128 ||
		started.Snapshot.ProxyPort < 1024 || started.Snapshot.ProxyPort > 65535 || started.Snapshot.ProxyPort == started.APIPort ||
		(started.Snapshot.Node != nil && started.Snapshot.Node.Credential != "") || resourceErr != nil || started.Resources.Name != started.Snapshot.TUNInterface || peer.Check() != nil {
		return nil, fail("tun_service_invalid_reply", "TUN 权限服务没有确认完整的网络接管状态")
	}
	if ctx.Err() != nil {
		return nil, fail("cancelled", "TUN 连接已取消")
	}
	// Synchronize with the startup cancellation callback before handing the
	// socket to the persistent reader. A racing cancel cannot close it later.
	if !abort() {
		<-aborted
		return nil, fail("cancelled", "TUN 连接已取消")
	}
	startupStopped = true
	if receiver != nil {
		receiver.secrets = append(receiver.secrets, started.APISecret)
	}
	client := &linuxTUNClient{connection: connection, peer: peer, codec: codec, started: started, guardian: guardian, logs: receiver, done: make(chan struct{})}
	keep = true
	go client.readEvents()
	return client, nil
}

func linuxTUNTransportFailure(ctx context.Context, err error) error {
	// A socket deadline can fire before context's timer publishes Err. The
	// codec already retains the expired operation deadline's error category.
	if ctx.Err() != nil || errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
		return fail("cancelled", "TUN 连接已取消")
	}
	return fail("tun_service_lost", "TUN 权限服务连接已中断，未收到网络恢复确认")
}

func (client *linuxTUNClient) readEvents() {
	defer close(client.done)
	defer client.peer.Close()
	defer client.connection.Close()
	var raw []byte
	var err error
	for {
		raw, err = client.codec.Read(context.Background())
		if err != nil {
			client.terminal = linuxTUNTransportFailure(context.Background(), err)
			return
		}
		event, logErr := client.logs.receive(raw)
		if logErr != nil {
			clear(raw)
			client.terminal = fail("tun_service_invalid_reply", "TUN 权限服务返回了无效的日志状态")
			return
		}
		if !event {
			break
		}
		clear(raw)
	}
	defer clear(raw)
	var reply struct {
		Version int `json:"version"`
		ID      int `json:"id"`
		Result  *struct {
			Stopped bool `json:"stopped"`
		} `json:"result,omitempty"`
		Error string `json:"error,omitempty"`
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err = decoder.Decode(&reply); err != nil || !client.requested.Load() || reply.Version != linuxipc.ProtocolVersion || reply.ID != 3 || (reply.Result == nil) == (reply.Error == "") {
		client.terminal = fail("tun_service_invalid_reply", "TUN 权限服务返回了无效的停止状态")
	} else if reply.Error != "" {
		client.terminal = linuxTUNFailure(reply.Error)
	} else if !reply.Result.Stopped {
		client.terminal = fail("tun_restore_failed", "TUN 权限服务尚未确认网络恢复")
	}
}

func (client *linuxTUNClient) stop(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, permissionCleanupTimeout+3*time.Second)
	defer cancel()
	if err := ctx.Err(); err != nil {
		return err
	}
	client.stopOnce.Do(func() {
		select {
		case <-client.done:
			return
		default:
		}
		client.requested.Store(true)
		write, cancel := context.WithTimeout(ctx, 2*time.Second)
		defer cancel()
		if err := client.codec.Write(write, linuxipc.Command{Version: linuxipc.ProtocolVersion, ID: 3, Method: "stop"}); err != nil {
			_ = client.connection.Close()
		}
	})
	select {
	case <-client.done:
		return client.terminal
	case <-ctx.Done():
		// EOF still starts root recovery, but cannot be reported as a confirmed
		// stop. The caller must keep this incomplete cleanup visible.
		_ = client.connection.Close()
		return errors.Join(fail("tun_restore_failed", "等待 TUN 网络恢复确认超时，请稍后重试断开"), ctx.Err())
	}
}

func (client *linuxTUNClient) close() {
	_ = client.connection.Close()
	<-client.done
}

func linuxTUNHello(ctx context.Context, codec *linuxipc.Codec, logs bool) (linuxprocess.Identity, error) {
	method := "hello"
	if logs {
		method = permissionLogHello
	}
	if err := codec.Write(ctx, linuxipc.Command{Version: linuxipc.ProtocolVersion, ID: 1, Method: method}); err != nil {
		return linuxprocess.Identity{}, linuxTUNTransportFailure(ctx, err)
	}
	raw, err := codec.Read(ctx)
	if err != nil {
		if logs && ctx.Err() == nil && !errors.Is(err, context.Canceled) && !errors.Is(err, context.DeadlineExceeded) {
			return linuxprocess.Identity{}, fail("tun_service_handshake_failed", "无法协商 TUN 权限日志，请检查或更新权限服务")
		}
		return linuxprocess.Identity{}, linuxTUNTransportFailure(ctx, err)
	}
	defer clear(raw)
	var reply struct {
		Version int                    `json:"version"`
		ID      int                    `json:"id"`
		Result  *linuxprocess.Identity `json:"result,omitempty"`
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err = decoder.Decode(&reply); err != nil || reply.Version != linuxipc.ProtocolVersion || reply.ID != 1 || reply.Result == nil || !reply.Result.Valid() {
		return linuxprocess.Identity{}, fail("tun_service_invalid_reply", "TUN 权限服务没有提供有效的进程身份")
	}
	alive, err := linuxprocess.Alive(*reply.Result)
	if err != nil || !alive || linuxprocess.VerifyUID(*reply.Result, 0) != nil {
		return linuxprocess.Identity{}, fail("tun_service_invalid_reply", "TUN 权限服务进程已退出")
	}
	return *reply.Result, nil
}

// ConfirmLinuxTUNServiceIdle performs the installer's read-only readiness check
// against the fixed root service. It neither authorizes nor starts capture.
func ConfirmLinuxTUNServiceIdle(ctx context.Context) error {
	return confirmLinuxTUNIdle(ctx, installedTUNSocket)
}

func confirmLinuxTUNIdle(ctx context.Context, socket string) error {
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	connection, peer, err := linuxipc.DialRootService(ctx, socket)
	if err != nil {
		return fail("tun_restore_failed", "无法联系 TUN 权限服务确认网络恢复，请稍后重试断开")
	}
	defer connection.Close()
	defer peer.Close()
	codec := linuxipc.NewCodec(connection)
	if err = codec.Write(ctx, linuxipc.Command{Version: linuxipc.ProtocolVersion, ID: 1, Method: "idle"}); err != nil {
		return fail("tun_restore_failed", "无法请求 TUN 网络恢复状态，请稍后重试断开")
	}
	raw, err := codec.Read(ctx)
	if err != nil {
		return fail("tun_restore_failed", "未收到 TUN 网络恢复确认，请稍后重试断开")
	}
	defer clear(raw)
	var reply struct {
		Version int `json:"version"`
		ID      int `json:"id"`
		Result  *struct {
			Idle bool `json:"idle"`
		} `json:"result,omitempty"`
		Error string `json:"error,omitempty"`
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err = decoder.Decode(&reply); err != nil || reply.Version != linuxipc.ProtocolVersion || reply.ID != 1 ||
		reply.Error != "" || reply.Result == nil || !reply.Result.Idle || peer.Check() != nil {
		return fail("tun_restore_failed", "权限服务尚未确认 TUN 网络恢复，请稍后重试断开")
	}
	return nil
}
