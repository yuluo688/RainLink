package session

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"

	"rainlink.local/host/internal/coreprocess"
)

// Failure is safe to display; core output and credentials never cross this boundary.
type Failure struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

func (e *Failure) Error() string      { return e.Message }
func fail(code, message string) error { return &Failure{code, message} }

// Snapshot is an observed session, not merely the user's desired state.
type Snapshot struct {
	Phase           string                  `json:"phase"`
	SessionID       string                  `json:"sessionId"`
	Node            *Node                   `json:"node,omitempty"`
	Target          *Target                 `json:"target,omitempty"`
	Mode            string                  `json:"mode"`
	ConfigRevision  string                  `json:"configRevision"`
	ProxyPort       int                     `json:"proxyPort"`
	SystemProxy     bool                    `json:"systemProxy"`
	TUN             bool                    `json:"tun"`
	TUNInterface    string                  `json:"tunInterface,omitempty"`
	RuleRevision    int                     `json:"ruleRevision"`
	RouteBindings   map[string]RouteBinding `json:"routeBindings,omitempty"`
	Error           string                  `json:"error"`
	Telemetry       *Telemetry              `json:"telemetry,omitempty"`
	RuntimeSettings *RuntimeSettings        `json:"runtimeSettings,omitempty"`
}

// Telemetry contains observations; nil fields remain unavailable in the UI.
type Telemetry struct {
	Upload        int64  `json:"upload"`
	Download      int64  `json:"download"`
	UploadTotal   int64  `json:"uploadTotal"`
	DownloadTotal int64  `json:"downloadTotal"`
	IP            string `json:"ip"`
	Country       string `json:"country"`
	CountryCode   string `json:"countryCode"`
	Latency       *int64 `json:"latency"`
	LatencyAt     int64  `json:"latencyAt"`
	ProbeError    string `json:"probeError"`
}

// A permission service has a distinct lifetime from a directly owned process.
// stop must confirm complete capture restoration; transport EOF is insufficient.
type managedCapture interface {
	observe(context.Context) error
	stop(context.Context) error
	close()
}

type runningCore struct {
	process       coreprocess.Process
	managed       managedCapture
	done          chan struct{}
	api           string
	secret        string
	client        *http.Client
	snapshot      Snapshot
	telemetry     Telemetry
	lastUpload    int64
	lastDownload  int64
	lastSample    time.Time
	cancelProbe   context.CancelFunc
	outboundNames map[string]string
}

// Manager serializes all lifecycle operations. Exit monitoring restores capture.
type Manager struct {
	mu               sync.Mutex
	corePath         string
	stateDir         string
	active           *runningCore
	lastError        string
	logs             *logBuffer
	connectionsCache *connectionBatch
	isolated         bool
	pendingTUN       string
	pendingManaged   managedCapture
}

// New constructs a manager without starting a core or changing system settings.
func New(corePath, stateDir string) *Manager {
	return &Manager{corePath: corePath, stateDir: stateDir, logs: newLogBuffer()}
}

func (m *Manager) recoverPrevious() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	// Repeated handshakes must never restore a still-running session's capture.
	if m.active != nil {
		return nil
	}
	if err := restoreProxy(m.stateDir); err != nil {
		return err
	}
	return m.cleanupTUNLocked()
}

// CorePath resolves only the bundled executable, never an arbitrary PATH command.
func CorePath() string {
	executable, err := os.Executable()
	if err != nil {
		return ""
	}
	name := "sing-box"
	if runtime.GOOS == "windows" {
		name += ".exe"
	}
	return filepath.Join(filepath.Dir(executable), name)
}

// Version validates that the bundled file is a runnable sing-box core.
func Version(corePath string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, corePath, "version")
	hideWindow(cmd)
	output, err := cmd.Output()
	if err != nil {
		return "", err
	}
	first, _, _ := strings.Cut(string(output), "\n")
	if !strings.HasPrefix(first, "sing-box version ") {
		return "", errors.New("unrecognized core")
	}
	return strings.TrimSpace(strings.TrimPrefix(first, "sing-box version ")), nil
}

// Connect commits system capture only after the core control channel is ready.
func (m *Manager) Connect(ctx context.Context, node Node, mode string, capture bool) (Snapshot, error) {
	return m.ConnectRouting(ctx, node, mode, capture, nil)
}

// ConnectRouting freezes all rule outbounds before checking or starting a core.
func (m *Manager) ConnectRouting(ctx context.Context, node Node, mode string, capture bool, plan *RoutingPlan) (Snapshot, error) {
	return m.connectTarget(ctx, node, nil, mode, capture, plan, true)
}

// ConnectChain freezes all hops before starting the core, exactly as node sessions do.
func (m *Manager) ConnectChain(ctx context.Context, chain ChainSnapshot, mode string, capture bool, plan *RoutingPlan) (Snapshot, error) {
	return m.connectTarget(ctx, Node{}, &chain, mode, capture, plan, true)
}

func (m *Manager) connectTarget(ctx context.Context, node Node, chain *ChainSnapshot, mode string, capture bool, plan *RoutingPlan, startProbe bool, values ...RuntimeSettings) (Snapshot, error) {
	return m.connectTargetCapture(ctx, node, chain, mode, capture, false, plan, startProbe, values...)
}

func (m *Manager) connectTargetCapture(ctx context.Context, node Node, chain *ChainSnapshot, mode string, capture, useTUN bool, plan *RoutingPlan, startProbe bool, values ...RuntimeSettings) (Snapshot, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if ctx.Err() != nil {
		return Snapshot{}, fail("cancelled", "连接已取消")
	}
	if m.active != nil {
		return Snapshot{}, fail("already_connected", "请先断开当前连接")
	}
	if err := m.cleanupTUNLocked(); err != nil {
		return Snapshot{}, err
	}
	settings, err := selectedRuntimeSettings(values)
	if err != nil {
		return Snapshot{}, err
	}
	if chain != nil {
		if node.ID != "" {
			return Snapshot{}, fail("invalid_target", "只能选择一个连接目标")
		}
		if err := chain.validate(); err != nil {
			return Snapshot{}, err
		}
	} else if err := node.validate(); err != nil {
		return Snapshot{}, fail("invalid_node", err.Error())
	}
	if m.isolated && (capture || useTUN) {
		return Snapshot{}, fail("isolated_probe", "链路测试不能接管系统网络")
	}
	if capture && !SystemProxyAvailable(ctx) {
		return Snapshot{}, fail("capture_unavailable", "当前桌面环境没有可用的系统代理，请使用本地代理端口")
	}
	if !validMode(mode) {
		return Snapshot{}, fail("invalid_mode", "代理模式无效")
	}
	if err := plan.validate(true); err != nil {
		return Snapshot{}, err
	}
	if _, err := Version(m.corePath); err != nil {
		return Snapshot{}, fail("core_unavailable", "未找到可运行的 sing-box 核心")
	}
	if runtime.GOOS == "linux" && useTUN {
		return m.connectManagedTUNLocked(ctx, node, chain, mode, capture, plan, startProbe, settings)
	}
	primary, err := prepareTarget(ctx, RoutingOutbound{Key: "proxy", Node: node, Chain: chain})
	if err != nil {
		return Snapshot{}, err
	}
	var prepared []preparedOutbound
	bindings := map[string]RouteBinding{}
	identity := Target{ID: node.ID, Name: node.Name, Revision: node.Revision, Kind: "node"}
	if chain != nil {
		identity = Target{ID: chain.ID, Name: chain.Name, Revision: chain.Revision, Kind: "chain"}
		primary.bindings("proxy", bindings)
	}
	names := map[string]string{"proxy": identity.Name, "direct": "直连"}
	secrets := primary.credentialsForLogs()
	if plan != nil {
		for index, target := range plan.Outbounds {
			ready, prepareErr := prepareTarget(ctx, target)
			if prepareErr != nil {
				return Snapshot{}, prepareErr
			}
			prepared = append(prepared, ready)
			target.bindings(target.Key, bindings)
			names["route-"+strconv.Itoa(index)] = target.Name
			secrets = append(secrets, ready.credentialsForLogs()...)
		}
	}
	proxyPort := settings.ProxyPort
	if proxyPort == 0 {
		proxyPort, err = freePort()
	} else {
		var listener net.Listener
		listener, err = net.Listen("tcp4", net.JoinHostPort("127.0.0.1", strconv.Itoa(proxyPort)))
		if err == nil {
			err = listener.Close()
		}
	}
	if err != nil {
		return Snapshot{}, fail("port_unavailable", "本地代理端口被占用或不可用，请修改端口后重试")
	}
	apiPort, err := freePort()
	if err != nil {
		return Snapshot{}, fail("port_unavailable", "无法分配核心控制端口")
	}
	if apiPort == proxyPort {
		apiPort, err = freePort()
		if err != nil || apiPort == proxyPort {
			return Snapshot{}, fail("port_unavailable", "无法分配核心控制端口")
		}
	}
	secret := randomID()
	config, err := targetConfiguration(primary, mode, proxyPort, apiPort, secret, plan, prepared, settings)
	if err != nil {
		return Snapshot{}, fail("invalid_credentials", "节点协议凭据无效，请检查密码、UUID 或加密方式")
	}
	var tun tunPlan
	committed := false
	if useTUN {
		tun, err = newTUNPlan(ctx)
		if err != nil {
			return Snapshot{}, err
		}
		config, err = configureTUN(config, tun)
		if err != nil {
			return Snapshot{}, fail("tun_config_failed", "无法生成 TUN 配置")
		}
		m.pendingTUN = tun.Name
		// Runs after process cleanup, including rejected authorization/checks.
		defer func() {
			if !committed {
				_ = m.cleanupTUNLocked()
			}
		}()
	}
	check := exec.CommandContext(ctx, m.corePath, "check", "-c", "stdin")
	hideWindow(check)
	check.Stdin = bytes.NewReader(config)
	if err = check.Run(); err != nil {
		if ctx.Err() != nil {
			return Snapshot{}, fail("cancelled", "连接已取消")
		}
		return Snapshot{}, fail("config_rejected", "核心配置校验失败，请检查节点参数")
	}
	secrets = append(secrets, secret)
	stdout := &coreLogWriter{logs: m.logs, secrets: secrets}
	stderr := &coreLogWriter{logs: m.logs, secrets: stdout.secrets}
	// The core gets its configuration through stdin; plaintext secrets never enter files or argv.
	process, err := coreprocess.Start(ctx, m.corePath, config, stdout, stderr, useTUN)
	if err != nil {
		if errors.Is(err, coreprocess.ErrPermissionDenied) {
			return Snapshot{}, fail("tun_permission_denied", "已取消 TUN 权限申请，未启用 TUN")
		}
		if ctx.Err() != nil {
			return Snapshot{}, fail("cancelled", "连接已取消")
		}
		if useTUN {
			return Snapshot{}, fail("tun_start_failed", "无法启动 TUN，请检查管理员授权和随应用提供的核心文件")
		}
		return Snapshot{}, fail("core_start_failed", "无法启动网络核心")
	}
	core := &runningCore{process: process, done: make(chan struct{}), api: fmt.Sprintf("http://127.0.0.1:%d", apiPort), secret: secret,
		client: &http.Client{Timeout: 2 * time.Second, Transport: &http.Transport{Proxy: nil}}, lastSample: time.Now(), outboundNames: names}
	go func() { _ = process.Wait(); stdout.finish(); stderr.finish(); close(core.done); m.coreExited(core) }()
	defer func() {
		if !committed {
			_ = process.Kill()
			<-core.done
			process.Close()
			core.client.CloseIdleConnections()
		}
	}()
	if err = core.waitReady(ctx); err != nil {
		return Snapshot{}, fail("core_not_ready", "网络核心未能就绪，正在清理本次网络设置")
	}
	if useTUN {
		if err = waitTUN(ctx, tun.Name, true); err != nil {
			return Snapshot{}, fail("tun_not_ready", "未能确认 TUN 网卡与路由，已停止本次连接")
		}
	}
	if err = ctx.Err(); err != nil {
		return Snapshot{}, fail("cancelled", "连接已取消")
	}
	if capture {
		if err = startRecoveryWatcher(ctx, m.stateDir); err != nil {
			return Snapshot{}, fail("recovery_unavailable", "无法启动系统代理恢复保护")
		}
		if err = applyProxy(ctx, m.stateDir, proxyPort); err != nil {
			return Snapshot{}, fail("proxy_apply_failed", "系统代理设置失败，已尝试恢复原设置；请重试")
		}
	}
	if err = ctx.Err(); err != nil {
		if restoreErr := restoreProxy(m.stateDir); restoreErr != nil {
			return Snapshot{}, fail("proxy_restore_failed", "连接已取消，但系统代理尚未恢复，请重试断开")
		}
		return Snapshot{}, fail("cancelled", "连接已取消")
	}
	digest := sha256.Sum256(config)
	publicNode := node
	publicNode.Credential = ""
	core.snapshot = Snapshot{Phase: "connected", SessionID: randomID(), Target: &identity, Mode: mode, ConfigRevision: hex.EncodeToString(digest[:]), ProxyPort: proxyPort, SystemProxy: capture, RouteBindings: bindings}
	core.snapshot.TUN, core.snapshot.TUNInterface = useTUN, tun.Name
	core.snapshot.RuntimeSettings = &settings
	if chain == nil {
		core.snapshot.Node = &publicNode
	}
	if plan != nil {
		core.snapshot.RuleRevision = plan.Revision
	}
	m.active = core
	m.lastError = ""
	m.connectionsCache = nil
	m.logs.append("info", "host", "网络核心已连接")
	committed = true
	if startProbe {
		probeCtx, cancel := context.WithCancel(context.Background())
		core.cancelProbe = cancel
		go m.probe(probeCtx, core)
	}
	return core.snapshot, nil
}

func (core *runningCore) waitReady(ctx context.Context) error {
	deadline := time.NewTimer(8 * time.Second)
	defer deadline.Stop()
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-core.done:
			return errors.New("core exited")
		case <-deadline.C:
			return errors.New("core readiness timeout")
		case <-ticker.C:
			var info map[string]any
			if core.apiJSON(ctx, http.MethodGet, "/version", nil, &info) == nil {
				return nil
			}
		}
	}
}

func (core *runningCore) apiJSON(ctx context.Context, method, path string, body any, out any) error {
	var data []byte
	var err error
	if body != nil {
		data, err = json.Marshal(body)
		if err != nil {
			return err
		}
	}
	req, err := http.NewRequestWithContext(ctx, method, core.api+path, bytes.NewReader(data))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+core.secret)
	req.Header.Set("Content-Type", "application/json")
	res, err := core.client.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return fmt.Errorf("core API status %d", res.StatusCode)
	}
	if out != nil {
		return json.NewDecoder(io.LimitReader(res.Body, 2<<20)).Decode(out)
	}
	return nil
}

// Snapshot samples the core only while the UI requests observations.
func (m *Manager) Snapshot(ctx context.Context) Snapshot {
	m.mu.Lock()
	defer m.mu.Unlock()
	core := m.active
	if core == nil {
		if m.pendingManaged != nil {
			return Snapshot{Phase: "failed", Error: m.lastError}
		}
		return Snapshot{Phase: "idle", Error: m.lastError}
	}
	var totals struct {
		Upload   int64 `json:"uploadTotal"`
		Download int64 `json:"downloadTotal"`
	}
	result := core.snapshot
	if core.managed != nil {
		if err := core.managed.observe(ctx); err != nil {
			result.Phase, result.Error = "failed", err.Error()
			telemetry := core.telemetry
			result.Telemetry = &telemetry
			return result
		}
	} else if result.TUN {
		_, ready, observeErr := observeTUN(result.TUNInterface)
		if observeErr != nil || !ready {
			result.Phase, result.Error = "failed", "TUN 网卡或路由异常，请断开后重连"
		}
	}
	if err := core.apiJSON(ctx, http.MethodGet, "/connections", nil, &totals); err != nil {
		// Keep the session identity so the user can still disconnect safely.
		result.Phase = "failed"
		result.Error = "无法确认核心状态，请重试断开后连接"
	} else {
		elapsed := time.Since(core.lastSample).Seconds()
		if elapsed > 0 {
			core.telemetry.Upload = int64(float64(max(0, totals.Upload-core.lastUpload)) / elapsed)
			core.telemetry.Download = int64(float64(max(0, totals.Download-core.lastDownload)) / elapsed)
		}
		core.telemetry.UploadTotal = totals.Upload
		core.telemetry.DownloadTotal = totals.Download
		core.lastUpload = totals.Upload
		core.lastDownload = totals.Download
		core.lastSample = time.Now()
	}
	telemetry := core.telemetry
	result.Telemetry = &telemetry
	return result
}

// SetMode changes a running route mode and confirms the core's resulting value.
func (m *Manager) SetMode(ctx context.Context, mode string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if !validMode(mode) {
		return fail("invalid_mode", "代理模式无效")
	}
	if m.active == nil {
		return fail("not_connected", "当前未连接")
	}
	core := m.active
	previous := core.snapshot.Mode
	if err := core.apiJSON(ctx, http.MethodPatch, "/configs", map[string]any{"mode": clashMode(mode)}, nil); err != nil {
		return fail("mode_failed", "核心未确认代理模式，请重试")
	}
	var current struct {
		Mode string `json:"mode"`
	}
	if err := core.apiJSON(ctx, http.MethodGet, "/configs", nil, &current); err != nil || !strings.EqualFold(current.Mode, mode) {
		if rollbackErr := core.apiJSON(ctx, http.MethodPatch, "/configs", map[string]any{"mode": clashMode(previous)}, nil); rollbackErr != nil {
			return fail("mode_unknown", "模式状态不确定，请断开后重连")
		}
		return fail("mode_failed", "模式确认失败，已请求恢复原模式")
	}
	core.snapshot.Mode = mode
	m.logs.append("info", "host", "代理模式已切换为 "+mode)
	return nil
}

// SetCapture applies or restores only the system settings owned by this session.
func (m *Manager) SetCapture(ctx context.Context, enabled bool) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if err := ctx.Err(); err != nil {
		return fail("cancelled", "操作已取消")
	}
	if m.isolated {
		return fail("isolated_probe", "链路测试不能接管系统网络")
	}
	if enabled && !SystemProxyAvailable(ctx) {
		return fail("capture_unavailable", "当前桌面环境没有可用的系统代理，请使用本地代理端口")
	}
	if m.active == nil {
		return fail("not_connected", "当前未连接")
	}
	select {
	case <-m.active.done:
		return fail("core_not_ready", "网络核心已停止，请先断开并确认网络恢复")
	default:
	}
	if enabled == m.active.snapshot.SystemProxy {
		return nil
	}
	if enabled {
		if err := startRecoveryWatcher(ctx, m.stateDir); err != nil {
			return fail("recovery_unavailable", "无法启动代理恢复保护")
		}
		if err := applyProxy(ctx, m.stateDir, m.active.snapshot.ProxyPort); err != nil {
			return fail("proxy_apply_failed", "无法启用系统代理")
		}
		if ctx.Err() != nil {
			if err := restoreProxy(m.stateDir); err != nil {
				return fail("proxy_restore_failed", "操作已取消，但系统代理尚未恢复，请重试关闭")
			}
			return fail("cancelled", "操作已取消")
		}
	} else if err := restoreProxy(m.stateDir); err != nil {
		return fail("proxy_restore_failed", "系统代理恢复失败，请重试关闭")
	}
	m.active.snapshot.SystemProxy = enabled
	return nil
}

// Disconnect restores capture before stopping the listener and is idempotent.
func (m *Manager) Disconnect() error {
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	return m.DisconnectContext(ctx)
}

// DisconnectContext retains the session when restoration is unconfirmed, so a
// later disconnect can retry without mistaking a lost service for success.
func (m *Manager) DisconnectContext(ctx context.Context) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if ctx.Err() != nil {
		return fail("cancelled", "断开已取消")
	}
	if !m.isolated {
		if err := restoreProxy(m.stateDir); err != nil {
			return fail("proxy_restore_failed", "系统代理恢复失败，请重试断开")
		}
	}
	core := m.active
	if core == nil {
		return m.cleanupTUNContextLocked(ctx)
	}
	core.snapshot.SystemProxy = false
	if core.cancelProbe != nil {
		core.cancelProbe()
	}
	if core.managed != nil {
		if err := core.managed.stop(ctx); err != nil {
			core.snapshot.Phase, core.snapshot.Error = "failed", "TUN 网络恢复尚未确认，请重试断开"
			m.lastError = core.snapshot.Error
			return err
		}
		core.managed.close()
	} else {
		select {
		case <-core.done:
		default:
			if err := core.process.Kill(); err != nil && !errors.Is(err, os.ErrProcessDone) {
				return fail("core_stop_failed", "无法停止网络核心，请重试断开")
			}
		}
		select {
		case <-core.done:
		case <-ctx.Done():
			return fail("core_stop_failed", "等待核心退出已取消，请重试断开")
		case <-time.After(3 * time.Second):
			return fail("core_stop_failed", "核心未能及时退出")
		}
		if core.snapshot.TUN {
			if err := m.cleanupTUNContextLocked(ctx); err != nil {
				return err
			}
		}
		core.process.Close()
	}
	m.active = nil
	m.lastError = ""
	m.connectionsCache = nil
	m.logs.append("info", "host", "连接已断开")
	core.client.CloseIdleConnections()
	return nil
}

func (m *Manager) coreExited(core *runningCore) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.active != core {
		return
	}
	if core.cancelProbe != nil {
		core.cancelProbe()
	}
	if core.managed != nil {
		// The root watchdog may still be restoring the durable journal. Keep
		// identity and the disconnect action until a root receipt confirms idle.
		core.client.CloseIdleConnections()
		core.snapshot.Phase, core.snapshot.Error = "failed", "TUN 权限服务连接已中断，请重试断开以确认网络恢复"
		if !m.isolated {
			if err := restoreProxy(m.stateDir); err != nil {
				core.snapshot.Error = "TUN 连接已中断，系统代理尚未恢复，请重试断开"
			} else {
				core.snapshot.SystemProxy = false
			}
		}
		m.lastError = core.snapshot.Error
		m.logs.append("error", "host", m.lastError)
		return
	}
	m.active = nil
	core.process.Close()
	core.client.CloseIdleConnections()
	m.lastError = "网络核心已退出，连接已中断"
	m.logs.append("error", "host", m.lastError)
	if !m.isolated {
		if err := restoreProxy(m.stateDir); err != nil {
			m.lastError = "核心已退出，系统代理恢复失败，请重试断开"
		}
	}
	if err := m.cleanupTUNLocked(); err != nil {
		m.lastError = "核心已退出，TUN 网卡尚未清理完成，请重试断开"
	}
}

func (m *Manager) probe(ctx context.Context, core *runningCore) {
	m.probeFor(ctx, core, 20*time.Second)
}

func (m *Manager) probeFor(parent context.Context, core *runningCore, timeout time.Duration) {
	probe := ProbeTelemetry(parent, core.snapshot.ProxyPort, timeout)
	m.mu.Lock()
	defer m.mu.Unlock()
	// Only disconnect, replacement or explicit cancellation discards the result.
	if m.active != core || parent.Err() != nil {
		return
	}
	core.telemetry.IP = probe.IP
	core.telemetry.Country = probe.Country
	core.telemetry.CountryCode = probe.CountryCode
	core.telemetry.Latency = probe.Latency
	core.telemetry.LatencyAt = probe.LatencyAt
	core.telemetry.ProbeError = probe.ProbeError
}

// ProbeTelemetry measures the selected proxy path without changing capture.
// Errors are scrubbed; deadlines publish a failed observation for either host.
func ProbeTelemetry(parent context.Context, proxyPort int, timeout time.Duration) Telemetry {
	ctx, cancel := context.WithTimeout(parent, timeout)
	defer cancel()
	proxyURL, _ := url.Parse("http://127.0.0.1:" + strconv.Itoa(proxyPort))
	client := &http.Client{Timeout: 5 * time.Second, Transport: &http.Transport{Proxy: http.ProxyURL(proxyURL)}}
	defer client.CloseIdleConnections()
	probe := Telemetry{}
	started := time.Now()
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, "https://www.gstatic.com/generate_204", nil)
	if res, err := client.Do(req); err == nil {
		io.Copy(io.Discard, io.LimitReader(res.Body, 4096))
		res.Body.Close()
		if res.StatusCode == 204 {
			latency := time.Since(started).Milliseconds()
			probe.Latency = &latency
			probe.LatencyAt = time.Now().UnixMilli()
		}
	}
	for _, endpoint := range []string{"https://api.ip.sb/geoip", "https://www.cloudflare.com/cdn-cgi/trace", "https://ipwho.is/"} {
		if ctx.Err() != nil {
			break
		}
		req, _ = http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
		req.Header.Set("User-Agent", "RainLink/0.1")
		res, err := client.Do(req)
		if err != nil {
			continue
		}
		var payload struct {
			IP          string `json:"ip"`
			Country     string `json:"country"`
			CountryCode string `json:"country_code"`
		}
		if strings.Contains(endpoint, "/cdn-cgi/trace") {
			var body []byte
			body, err = io.ReadAll(io.LimitReader(res.Body, 64<<10))
			for _, line := range strings.Split(string(body), "\n") {
				key, value, _ := strings.Cut(line, "=")
				switch key {
				case "ip":
					payload.IP = strings.TrimSpace(value)
				case "loc":
					payload.CountryCode = strings.TrimSpace(value)
				}
			}
		} else {
			err = json.NewDecoder(io.LimitReader(res.Body, 64<<10)).Decode(&payload)
		}
		res.Body.Close()
		if err == nil && res.StatusCode == 200 && net.ParseIP(payload.IP) != nil {
			probe.IP = payload.IP
			probe.Country = payload.Country
			probe.CountryCode = strings.ToLower(payload.CountryCode)
			break
		}
	}
	if probe.IP == "" {
		probe.ProbeError = "出口检测失败，可重试；连接状态以核心回执为准"
	}
	return probe
}

// RefreshProbe retries optional egress and latency observations without reconnecting.
func (m *Manager) RefreshProbe() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.active == nil {
		return fail("not_connected", "请先连接节点")
	}
	core := m.active
	if core.cancelProbe != nil {
		core.cancelProbe()
	}
	ctx, cancel := context.WithCancel(context.Background())
	core.cancelProbe = cancel
	go m.probe(ctx, core)
	return nil
}
