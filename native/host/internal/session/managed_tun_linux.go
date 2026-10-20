//go:build linux && !android

package session

import (
	"context"
	"errors"
	"net"
	"net/http"
	"strconv"
	"time"

	"rainlink.local/host/internal/linuxprocess"
)

type linuxManagedCapture struct {
	client   *linuxTUNClient
	guardian linuxprocess.Identity
}

func (capture *linuxManagedCapture) observe(ctx context.Context) error {
	if capture.client == nil {
		return fail("tun_restore_failed", "TUN 网络恢复尚未确认，请重试断开")
	}
	select {
	case <-capture.client.done:
		return fail("tun_service_lost", "TUN 权限服务连接已中断，请重试断开以确认网络恢复")
	default:
	}
	ready, err := observeManagedTUN(ctx, capture.client.started.Resources)
	if err != nil || !ready {
		return fail("tun_not_ready", "TUN 网卡或路由异常，请断开后重连")
	}
	return nil
}

func (capture *linuxManagedCapture) stop(ctx context.Context) error {
	if capture.client != nil {
		if err := capture.client.stop(ctx); err == nil {
			return nil
		}
	}
	if ctx.Err() != nil {
		return fail("tun_restore_failed", "等待 TUN 网络恢复确认已取消，请重试断开")
	}
	// A socket-activated listener can outlive the guardian. Use the guardian
	// reported before start, not SO_PEERCRED, to fence late startup mutations.
	alive, err := linuxprocess.Alive(capture.guardian)
	if err != nil {
		return fail("tun_restore_failed", "TUN 权限服务仍在退出或恢复，请稍后重试断开")
	}
	if alive {
		guardian, err := linuxprocess.Open(capture.guardian)
		if err != nil && !errors.Is(err, linuxprocess.ErrNotAlive) {
			return fail("tun_restore_failed", "无法确认 TUN 权限服务退出，请稍后重试断开")
		}
		if guardian != nil {
			wait, cancel := context.WithTimeout(ctx, 3*time.Second)
			err = guardian.Wait(wait)
			cancel()
			closeErr := guardian.Close()
			if err != nil || closeErr != nil {
				return fail("tun_restore_failed", "TUN 权限服务仍在退出或恢复，请稍后重试断开")
			}
		}
	}
	return confirmLinuxTUNIdle(ctx, installedTUNSocket)
}

func (capture *linuxManagedCapture) close() {
	if capture.client != nil {
		capture.client.close()
	}
}

// prepareLinuxTUNRequest opens credentials only in the ordinary user's secure store.
// The root compiler receives memory-only values and cannot access that store.
func prepareLinuxTUNRequest(ctx context.Context, node Node, chain *ChainSnapshot, mode string, plan *RoutingPlan, settings RuntimeSettings) (MobileRequest, map[string]string, error) {
	request := MobileRequest{Chain: chain, Mode: mode, TUN: true, Routing: plan, RuntimeSettings: &settings, Secrets: map[string]MobileCredentials{}}
	primary := RoutingOutbound{Node: node, Chain: chain}
	name := node.Name
	if chain == nil {
		request.Node = &node
	} else {
		name = chain.Name
	}
	names := map[string]string{"proxy": name, "direct": "直连"}
	read := func(target RoutingOutbound) error {
		nodes := []Node{target.Node}
		if target.Chain != nil {
			nodes = target.Chain.Hops
		}
		for _, entry := range nodes {
			auth, err := readNodeCredentials(ctx, entry)
			if err != nil {
				return err
			}
			if err = entry.validateCredentials(auth); err != nil {
				return fail("invalid_credentials", "节点认证参数无效，请重新编辑节点")
			}
			if entry.Credential != "" {
				request.Secrets[entry.Credential] = MobileCredentials{Username: auth.Username, Password: auth.Password, ObfsPassword: auth.ObfsPassword}
			}
		}
		return nil
	}
	if err := read(primary); err != nil {
		clear(request.Secrets)
		return MobileRequest{}, nil, err
	}
	if plan != nil {
		for index, target := range plan.Outbounds {
			if err := read(target); err != nil {
				clear(request.Secrets)
				return MobileRequest{}, nil, err
			}
			names["route-"+strconv.Itoa(index)] = target.Name
		}
	}
	return request, names, nil
}

func (m *Manager) connectManagedTUNLocked(ctx context.Context, node Node, chain *ChainSnapshot, mode string, systemProxy bool, plan *RoutingPlan, startProbe bool, settings RuntimeSettings) (_ Snapshot, result error) {
	request, names, err := prepareLinuxTUNRequest(ctx, node, chain, mode, plan, settings)
	if err != nil {
		return Snapshot{}, err
	}
	client, err := startLinuxTUNClient(ctx, request, m.logs)
	clear(request.Secrets)
	if err != nil {
		var uncertain *linuxTUNUnconfirmedStart
		if errors.As(err, &uncertain) {
			m.pendingManaged = &linuxManagedCapture{guardian: uncertain.guardian}
			m.lastError = "TUN 连接未完成，网络恢复尚未确认，请重试断开"
		}
		var failure *Failure
		if errors.As(err, &failure) {
			// These messages are fixed native failure text, never the original
			// transport/authorization error or private core configuration.
			m.logs.append("error", "host", failure.Message)
			if failure.Code == "tun_service_unavailable" {
				return Snapshot{}, fail("capture_unavailable", "未安装或无法联系可信的 TUN 权限服务")
			}
		}
		return Snapshot{}, err
	}
	capture := &linuxManagedCapture{client: client, guardian: client.guardian}
	core := &runningCore{managed: capture, done: client.done, snapshot: client.started.Snapshot,
		api: "http://" + net.JoinHostPort("127.0.0.1", strconv.Itoa(client.started.APIPort)), secret: client.started.APISecret,
		client:     &http.Client{Timeout: 2 * time.Second, Transport: &http.Transport{Proxy: nil}},
		lastSample: time.Now(), outboundNames: names, trafficTargets: trafficTargets(RoutingOutbound{Node: node, Chain: chain}, plan)}
	if chain == nil {
		publicNode := node
		publicNode.Credential = ""
		core.snapshot.Node = &publicNode
	}
	committed := false
	defer func() {
		if !committed {
			cleanup, cancel := context.WithTimeout(context.Background(), permissionCleanupTimeout+3*time.Second)
			defer cancel()
			proxyErr := restoreProxy(m.stateDir)
			stopErr := capture.stop(cleanup)
			core.client.CloseIdleConnections()
			if proxyErr != nil || stopErr != nil {
				m.active = core
				m.lastError = "连接未完成，网络恢复尚未确认，请重试断开"
				core.snapshot.Phase, core.snapshot.Error = "failed", m.lastError
				result = fail("tun_restore_failed", m.lastError)
			} else {
				capture.close()
			}
		}
	}()
	if err = capture.observe(ctx); err != nil {
		return Snapshot{}, err
	}
	if systemProxy {
		if err = startRecoveryWatcher(ctx, m.stateDir); err != nil {
			return Snapshot{}, fail("recovery_unavailable", "无法启动系统代理恢复保护")
		}
		if err = applyProxy(ctx, m.stateDir, core.snapshot.ProxyPort); err != nil {
			return Snapshot{}, fail("proxy_apply_failed", "系统代理设置失败，正在恢复本次连接")
		}
		core.snapshot.SystemProxy = true
	}
	if ctx.Err() != nil {
		return Snapshot{}, fail("cancelled", "连接已取消")
	}
	m.active, m.lastError, m.connectionsCache = core, "", nil
	m.logs.append("info", "host", "TUN 网络已连接")
	committed = true
	go func() { <-core.done; m.coreExited(core) }()
	if startProbe {
		probeCtx, cancel := context.WithCancel(context.Background())
		core.cancelProbe = cancel
		go m.probe(probeCtx, core)
	}
	return core.snapshot, nil
}
