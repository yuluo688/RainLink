package session

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"
)

type request struct {
	ID             int             `json:"id"`
	Method         string          `json:"method"`
	Payload        json.RawMessage `json:"payload"`
	cancelRevision int
}
type response struct {
	ID     int      `json:"id"`
	Result any      `json:"result,omitempty"`
	Error  *Failure `json:"error,omitempty"`
}

// Serve uses inherited stdin/stdout as a private, bounded, versioned channel.
// EOF cancels in-flight connection work and restores capture before exiting.
func Serve(input io.Reader, output io.Writer, corePath, stateDir string) error {
	return serve(input, output, corePath, stateDir, false)
}

// ServeIsolated owns a disposable runtime and only permits node/chain diagnostics.
// It cannot recover, replace or capture a normal interactive session's network.
func ServeIsolated(input io.Reader, output io.Writer, corePath string) error {
	stateDir, err := os.MkdirTemp("", "rainlink-probe-*")
	if err != nil {
		return err
	}
	serveErr := serve(input, output, corePath, stateDir, true)
	return errors.Join(serveErr, os.RemoveAll(stateDir))
}

func serve(input io.Reader, output io.Writer, corePath, stateDir string, isolated bool) error {
	if runtime.GOOS != "windows" && runtime.GOOS != "linux" && runtime.GOOS != "darwin" {
		return errors.New("interactive sessions are unavailable on this platform")
	}
	if stateDir == "" {
		directory, err := os.UserCacheDir()
		if err != nil {
			return err
		}
		stateDir = filepath.Join(directory, "RainLink", "runtime")
	}
	manager := New(corePath, stateDir)
	manager.isolated = isolated
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	requests := make(chan request, 16)
	readErrors := make(chan error, 1)
	var operationMu sync.Mutex
	var cancelOperation context.CancelFunc
	var cancelRevision int
	go func() {
		defer close(requests)
		scanner := bufio.NewScanner(input)
		scanner.Buffer(make([]byte, 4096), 128<<10)
		for scanner.Scan() {
			var command request
			decoder := json.NewDecoder(strings.NewReader(scanner.Text()))
			decoder.DisallowUnknownFields()
			if err := decoder.Decode(&command); err != nil || command.ID < 1 {
				readErrors <- errors.New("invalid session request")
				cancel()
				return
			}
			if command.Method == "cancel" {
				operationMu.Lock()
				cancelRevision++
				if cancelOperation != nil {
					cancelOperation()
				}
				operationMu.Unlock()
			}
			operationMu.Lock()
			command.cancelRevision = cancelRevision
			operationMu.Unlock()
			select {
			case requests <- command:
			case <-ctx.Done():
				return
			}
		}
		if err := scanner.Err(); err != nil {
			readErrors <- err
		}
		cancel()
	}()
	encoder := json.NewEncoder(output)
	var serveErr error
	for command := range requests {
		if ctx.Err() != nil {
			break
		}
		timeout := 20 * time.Second
		if isolated && command.Method == "testChain" {
			timeout = 45 * time.Second
		}
		if !isolated && command.Method == "connect" {
			timeout = 90 * time.Second
		}
		if !isolated && command.Method == "disconnect" {
			timeout = 45 * time.Second
		}
		operationCtx, operationCancel := context.WithTimeout(ctx, timeout)
		operationMu.Lock()
		cancelOperation = operationCancel
		// A cancel may arrive after enqueueing work but before execute starts.
		// Cancel that queued attempt as well; it must not open a late UAC dialog.
		if command.cancelRevision != cancelRevision && command.Method != "cancel" {
			operationCancel()
		}
		operationMu.Unlock()
		result, err := manager.execute(operationCtx, command)
		operationCancel()
		operationMu.Lock()
		cancelOperation = nil
		operationMu.Unlock()
		reply := response{ID: command.ID, Result: result}
		if err != nil {
			var public *Failure
			if errors.As(err, &public) {
				reply.Error = public
			} else {
				reply.Error = &Failure{"operation_failed", "操作失败，请重试"}
			}
			reply.Result = nil
		}
		if err = encoder.Encode(reply); err != nil {
			serveErr = err
			cancel()
			break
		}
	}
	cleanupErr := manager.Disconnect()
	select {
	case err := <-readErrors:
		serveErr = errors.Join(serveErr, err)
	default:
	}
	return errors.Join(serveErr, cleanupErr)
}

func (m *Manager) execute(ctx context.Context, command request) (any, error) {
	if m.isolated && command.Method != "hello" && command.Method != "validateChain" && command.Method != "testChain" && command.Method != "testNode" && command.Method != "cancel" && command.Method != "validateSettings" && command.Method != "testDNS" {
		return nil, fail("isolated_probe", "测试宿主仅支持节点测试及代理链校验与测试")
	}
	switch command.Method {
	case "validateSettings", "testDNS":
		if !m.isolated {
			return nil, fail("isolated_probe", "请使用独立设置测试宿主")
		}
		settings, err := decodeRuntime(command.Payload)
		if err != nil {
			return nil, err
		}
		if command.Method == "validateSettings" {
			return nil, m.ValidateRuntime(ctx, settings)
		}
		return m.TestDNS(ctx, settings)
	case "hello":
		if !m.isolated {
			if err := m.recoverPrevious(); err != nil {
				return nil, fail("proxy_recovery_failed", "上次系统代理尚未恢复，请关闭其他 RainLink 实例后重试")
			}
		}
		version, err := Version(m.corePath)
		if err != nil {
			return nil, fail("core_unavailable", "未找到可运行的 sing-box 核心")
		}
		return map[string]any{"protocolVersion": 2, "coreVersion": version}, nil
	case "protect":
		var payload struct {
			ID           string `json:"id"`
			Username     string `json:"username"`
			Password     string `json:"password"`
			ObfsPassword string `json:"obfsPassword"`
		}
		if err := json.Unmarshal(command.Payload, &payload); err != nil || payload.ID == "" || len(payload.ID) > 128 || len(payload.Username) > 4096 || len(payload.Password) > 4096 || len(payload.ObfsPassword) > 4096 {
			return nil, fail("invalid_credentials", "节点凭据格式无效")
		}
		plain, err := json.Marshal(credentials{Username: payload.Username, Password: payload.Password, ObfsPassword: payload.ObfsPassword})
		if err != nil {
			return nil, err
		}
		defer clear(plain)
		cipher, err := seal(ctx, plain, payload.ID)
		if err != nil {
			return nil, credentialFailure(err, "credential_store_failed", "无法安全保存节点凭据")
		}
		return map[string]any{"cipher": cipher}, nil
	case "reveal":
		var payload struct {
			ID     string `json:"id"`
			Cipher string `json:"cipher"`
		}
		if err := json.Unmarshal(command.Payload, &payload); err != nil || payload.ID == "" || len(payload.ID) > 128 || len(payload.Cipher) > 32768 {
			return nil, fail("invalid_credentials", "凭据读取参数无效")
		}
		plain, err := unseal(ctx, payload.Cipher, payload.ID)
		if err != nil {
			return nil, credentialFailure(err, "credential_read_failed", "无法解密保存的凭据")
		}
		defer clear(plain)
		var auth credentials
		if err = json.Unmarshal(plain, &auth); err != nil {
			return nil, fail("credential_read_failed", "已保存凭据格式无效")
		}
		return auth, nil
	case "connect":
		var payload struct {
			Node            Node            `json:"node"`
			Chain           *ChainSnapshot  `json:"chain"`
			Mode            string          `json:"mode"`
			SystemProxy     bool            `json:"systemProxy"`
			TUN             bool            `json:"tun"`
			Routing         *RoutingPlan    `json:"routing"`
			RuntimeSettings json.RawMessage `json:"runtimeSettings"`
		}
		if err := json.Unmarshal(command.Payload, &payload); err != nil {
			return nil, fail("invalid_request", "连接参数无效")
		}
		settings := defaultRuntimeSettings()
		if len(payload.RuntimeSettings) != 0 {
			var err error
			settings, err = decodeRuntime(payload.RuntimeSettings)
			if err != nil {
				return nil, err
			}
		}
		return m.connectTargetCapture(ctx, payload.Node, payload.Chain, payload.Mode, payload.SystemProxy, payload.TUN, payload.Routing, true, settings)
	case "validateChain", "testChain":
		if !m.isolated {
			return nil, fail("isolated_probe", "请使用独立测试宿主")
		}
		var chain ChainSnapshot
		if err := json.Unmarshal(command.Payload, &chain); err != nil {
			return nil, fail("invalid_request", "代理链参数无效")
		}
		if command.Method == "validateChain" {
			return nil, m.ValidateChain(ctx, chain)
		}
		return m.TestChain(ctx, chain)
	case "testNode":
		if !m.isolated {
			return nil, fail("isolated_probe", "请使用独立测试宿主")
		}
		var node Node
		if err := json.Unmarshal(command.Payload, &node); err != nil {
			return nil, fail("invalid_request", "节点测速参数无效")
		}
		return m.TestNode(ctx, node)
	case "validateRules":
		var payload RoutingPlan
		if err := json.Unmarshal(command.Payload, &payload); err != nil {
			return nil, fail("invalid_request", "规则参数无效")
		}
		return nil, m.ValidateRules(ctx, payload)
	case "snapshot":
		return m.Snapshot(ctx), nil
	case "traffic":
		var payload struct {
			SessionID string `json:"sessionId"`
		}
		if err := json.Unmarshal(command.Payload, &payload); err != nil {
			return nil, fail("invalid_request", "流量读取参数无效")
		}
		return m.Traffic(ctx, payload.SessionID)
	case "connections":
		var payload struct {
			SessionID  string `json:"sessionId"`
			SnapshotID string `json:"snapshotId"`
			Cursor     int    `json:"cursor"`
		}
		if err := json.Unmarshal(command.Payload, &payload); err != nil || len(payload.SessionID) > 128 || len(payload.SnapshotID) > 128 {
			return nil, fail("invalid_request", "连接读取参数无效")
		}
		return m.Connections(ctx, payload.SessionID, payload.SnapshotID, payload.Cursor)
	case "closeConnections":
		var payload struct {
			SessionID    string `json:"sessionId"`
			ConnectionID string `json:"connectionId"`
			All          bool   `json:"all"`
		}
		if err := json.Unmarshal(command.Payload, &payload); err != nil || len(payload.SessionID) > 128 {
			return nil, fail("invalid_request", "关闭连接参数无效")
		}
		return nil, m.CloseConnections(ctx, payload.SessionID, payload.ConnectionID, payload.All)
	case "logs":
		var payload struct {
			Stream string `json:"stream"`
			After  int64  `json:"after"`
		}
		if err := json.Unmarshal(command.Payload, &payload); err != nil || payload.After < 0 || len(payload.Stream) > 128 {
			return nil, fail("invalid_request", "日志读取参数无效")
		}
		batch := m.logs.read(payload.Stream, payload.After)
		if batch.clockErr != nil {
			return nil, fail("logs_unavailable", "无法记录日志时间，请检查系统时钟服务")
		}
		return batch, nil
	case "clearLogs":
		batch := m.logs.clear()
		if batch.clockErr != nil {
			return nil, fail("logs_unavailable", "无法确认日志清空时间，原记录已保留")
		}
		return batch, nil
	case "disconnect":
		return nil, m.DisconnectContext(ctx)
	case "mode":
		var payload struct {
			Mode string `json:"mode"`
		}
		if err := json.Unmarshal(command.Payload, &payload); err != nil {
			return nil, fail("invalid_request", "代理模式无效")
		}
		return nil, m.SetMode(ctx, payload.Mode)
	case "capture":
		var payload struct {
			Enabled bool `json:"enabled"`
		}
		if err := json.Unmarshal(command.Payload, &payload); err != nil {
			return nil, fail("invalid_request", "系统代理设置无效")
		}
		return nil, m.SetCapture(ctx, payload.Enabled)
	case "probe":
		return nil, m.RefreshProbe()
	case "cancel":
		return nil, nil
	default:
		return nil, fail("unsupported_command", "不支持的宿主命令")
	}
}
