package mobile

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"sync"
	"time"

	"github.com/sagernet/sing-box/experimental/libbox"
	"rainlink.local/host/mobileconfig"
)

// Runtime owns one embedded core. Its lifetime belongs to the Android service,
// independent of Flutter activities. All returned errors are safe for display.
type Runtime struct {
	mu          sync.Mutex
	lifecycle   sync.Mutex
	prepared    mobileconfig.Prepared
	service     *libbox.BoxService
	ctx         context.Context
	cancel      context.CancelFunc
	client      *http.Client
	started     bool
	closed      bool
	closeErr    error
	lastAt      time.Time
	lastUp      int64
	lastDown    int64
	telemetry   mobileconfig.Telemetry
	probeCancel context.CancelFunc
	logs        *mobileconfig.Logs
	platform    *loggingPlatform
	connections *mobileconfig.Connections
}

type loggingPlatform struct {
	libbox.PlatformInterface
	logs       *mobileconfig.Logs
	tunnelName string
}

func (p *loggingPlatform) WriteLog(message string) { p.logs.WriteLine(message) }

func (p *loggingPlatform) OpenTun(options libbox.TunOptions) (int32, error) {
	fd, err := p.PlatformInterface.OpenTun(options)
	if err != nil {
		return fd, err
	}
	p.tunnelName, err = observedTunnelName(fd)
	return fd, err
}

// NewRuntime compiles secure-store output, validates with libbox, and creates a
// service without starting a TUN. The request must not be persisted or logged.
func NewRuntime(request string, platform libbox.PlatformInterface, tunnel bool) (*Runtime, error) {
	return NewRuntimeWithLogs(request, platform, tunnel, NewLogStore())
}

// NewRuntimeWithLogs attaches a service-owned public buffer while keeping each
// session's redaction inputs separate. Temporary probes use NewRuntime instead.
func NewRuntimeWithLogs(request string, platform libbox.PlatformInterface, tunnel bool, store *LogStore) (*Runtime, error) {
	if store == nil {
		return nil, errors.New("日志服务不可用")
	}
	prepared, err := mobileconfig.Prepare(request, tunnel)
	if err != nil {
		return nil, err
	}
	if err := CheckConfig(prepared.Configuration); err != nil {
		return nil, err
	}
	logs := store.logs.ForSession(prepared.SecretValues)
	adapter := &loggingPlatform{PlatformInterface: platform, logs: logs}
	service, err := libbox.NewService(prepared.Configuration, adapter)
	if err != nil {
		return nil, errors.New("无法创建网络核心，请检查协议和网络配置")
	}
	// Release the compiled plaintext configuration after libbox has consumed it.
	prepared.Configuration = ""
	prepared.SecretValues = nil
	ctx, cancel := context.WithCancel(context.Background())
	client := &http.Client{Timeout: 2 * time.Second, Transport: &http.Transport{Proxy: nil}}
	return &Runtime{prepared: prepared, service: service, ctx: ctx, cancel: cancel, logs: logs, platform: adapter,
		client: client, connections: mobileconfig.NewConnections(prepared, client, logs)}, nil
}

// ReadLogs returns only bounded, credential-filtered log entries.
func (r *Runtime) ReadLogs(stream string, after int64) (string, error) {
	encoded, err := json.Marshal(r.logs.Read(stream, after))
	return string(encoded), err
}

// Start reports success only after the TUN and authenticated control endpoint
// are ready. Closing concurrently cancels readiness and releases the core.
func (r *Runtime) Start() error {
	r.lifecycle.Lock()
	defer r.lifecycle.Unlock()
	if r.ctx.Err() != nil {
		return errors.New("连接已取消")
	}
	if err := r.service.Start(); err != nil {
		return errors.New("网络服务启动失败，请检查系统授权和端口占用")
	}
	ctx, cancel := context.WithTimeout(r.ctx, 8*time.Second)
	defer cancel()
	for {
		if _, err := r.api(ctx, http.MethodGet, "/version", nil); err == nil {
			r.mu.Lock()
			r.prepared.Snapshot.TUNInterface = r.platform.tunnelName
			r.started = true
			mode := r.prepared.Snapshot.Mode
			r.mu.Unlock()
			return r.SetMode(mode)
		}
		select {
		case <-ctx.Done():
			return errors.New("网络服务就绪超时或已取消")
		case <-time.After(80 * time.Millisecond):
		}
	}
}

// Close cancels in-flight observations and waits for the embedded core to stop.
// Repeated calls are safe. Android closes its original TUN descriptor afterward.
func (r *Runtime) Close() error {
	r.cancel()
	r.lifecycle.Lock()
	defer r.lifecycle.Unlock()
	r.mu.Lock()
	if r.closed {
		err := r.closeErr
		r.mu.Unlock()
		return err
	}
	r.closed = true
	r.started = false
	r.mu.Unlock()
	r.client.CloseIdleConnections()
	// Box.Start closes itself on failure. Its exact already-closed sentinel is
	// safe here; other errors (including aggregated cleanup failures) still fail.
	if err := r.service.Close(); err != nil && err != os.ErrClosed {
		r.mu.Lock()
		r.closeErr = errors.New("网络核心停止失败，请重试断开")
		r.mu.Unlock()
		return r.closeErr
	}
	return nil
}

func (r *Runtime) api(ctx context.Context, method, path string, body []byte) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, method, "http://127.0.0.1:"+strconv.Itoa(r.prepared.APIPort)+path, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+r.prepared.APISecret)
	req.Header.Set("Content-Type", "application/json")
	response, err := r.client.Do(req)
	if err != nil {
		return nil, errors.New("核心控制通道不可用")
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return nil, errors.New("核心未确认操作")
	}
	return io.ReadAll(io.LimitReader(response.Body, 8<<20))
}

// Snapshot returns public identity, observed TUN state and actual core counters.
func (r *Runtime) Snapshot() (string, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if !r.started || r.closed {
		return "", errors.New("当前没有活动连接")
	}
	body, err := r.api(r.ctx, http.MethodGet, "/connections", nil)
	if err != nil {
		return "", err
	}
	var counters struct {
		Upload   int64 `json:"uploadTotal"`
		Download int64 `json:"downloadTotal"`
	}
	if json.Unmarshal(body, &counters) != nil || counters.Upload < 0 || counters.Download < 0 {
		return "", errors.New("核心流量响应无效")
	}
	now := time.Now()
	if !r.lastAt.IsZero() {
		seconds := now.Sub(r.lastAt).Seconds()
		if seconds > 0 && counters.Upload >= r.lastUp && counters.Download >= r.lastDown {
			r.telemetry.Upload = int64(float64(counters.Upload-r.lastUp) / seconds)
			r.telemetry.Download = int64(float64(counters.Download-r.lastDown) / seconds)
		}
	}
	r.lastAt, r.lastUp, r.lastDown = now, counters.Upload, counters.Download
	r.telemetry.UploadTotal, r.telemetry.DownloadTotal = counters.Upload, counters.Download
	snapshot := r.prepared.Snapshot
	snapshot.Telemetry = &r.telemetry
	encoded, err := json.Marshal(snapshot)
	return string(encoded), err
}

// SetMode updates actual routing and confirms its value through the core API.
func (r *Runtime) SetMode(mode string) error {
	if mode != "global" && mode != "rule" && mode != "direct" {
		return errors.New("代理模式无效")
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if !r.started || r.closed {
		return errors.New("请先连接节点")
	}
	body, _ := json.Marshal(map[string]string{"mode": mode})
	if _, err := r.api(r.ctx, http.MethodPatch, "/configs", body); err != nil {
		return err
	}
	reply, err := r.api(r.ctx, http.MethodGet, "/configs", nil)
	var observed struct {
		Mode string `json:"mode"`
	}
	if err != nil || json.Unmarshal(reply, &observed) != nil || observed.Mode != mode {
		return errors.New("核心未确认代理模式")
	}
	r.prepared.Snapshot.Mode = mode
	return nil
}

// Probe starts a cancellable observation using the same egress probe as desktop.
func (r *Runtime) Probe() {
	r.mu.Lock()
	defer r.mu.Unlock()
	if !r.started || r.closed {
		return
	}
	if r.probeCancel != nil {
		r.probeCancel()
	}
	ctx, cancel := context.WithCancel(r.ctx)
	r.probeCancel = cancel
	go func() {
		observation := mobileconfig.Probe(ctx, r.prepared.Snapshot.ProxyPort)
		r.mu.Lock()
		defer r.mu.Unlock()
		if ctx.Err() != nil || r.closed {
			return
		}
		r.telemetry.IP, r.telemetry.Country, r.telemetry.CountryCode = observation.IP, observation.Country, observation.CountryCode
		r.telemetry.Latency, r.telemetry.LatencyAt, r.telemetry.ProbeError = observation.Latency, observation.LatencyAt, observation.ProbeError
	}()
}

// Measure tests the temporary runtime's actual HTTPS path. It does not change
// the live session or system capture; Close cancels the request immediately.
func (r *Runtime) Measure() (int64, error) {
	proxy, _ := url.Parse("http://127.0.0.1:" + strconv.Itoa(r.prepared.Snapshot.ProxyPort))
	client := &http.Client{Timeout: 10 * time.Second, Transport: &http.Transport{Proxy: http.ProxyURL(proxy)}}
	defer client.CloseIdleConnections()
	req, _ := http.NewRequestWithContext(r.ctx, http.MethodGet, "https://www.gstatic.com/generate_204", nil)
	started := time.Now()
	response, err := client.Do(req)
	if err != nil {
		return 0, errors.New("节点测试未通过，请检查认证、网络和目标可达性")
	}
	defer response.Body.Close()
	if response.StatusCode != 204 {
		return 0, errors.New("节点未返回预期响应")
	}
	return time.Since(started).Milliseconds(), nil
}
