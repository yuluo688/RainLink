package session

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"strconv"
)

// MobileCredentials exists only in memory, after the platform secure store has
// authenticated each node's ciphertext and identity. It must never be logged.
type MobileCredentials struct {
	Username     string `json:"username"`
	Password     string `json:"password"`
	ObfsPassword string `json:"obfsPassword,omitempty"`
}

// MobileRequest uses the desktop domain contract. Secrets are indexed by their
// ciphertext, so two revisions of one node cannot accidentally share credentials.
type MobileRequest struct {
	Node            *Node                        `json:"node,omitempty"`
	Chain           *ChainSnapshot               `json:"chain,omitempty"`
	Mode            string                       `json:"mode"`
	SystemProxy     bool                         `json:"systemProxy"`
	TUN             bool                         `json:"tun"`
	Routing         *RoutingPlan                 `json:"routing,omitempty"`
	RuntimeSettings *RuntimeSettings             `json:"runtimeSettings,omitempty"`
	Secrets         map[string]MobileCredentials `json:"secrets"`
}

// MobileConfiguration is private to the native service. Only Snapshot may be
// returned to Flutter; Configuration and APISecret contain runtime secrets.
type MobileConfiguration struct {
	Configuration string            `json:"configuration"`
	Snapshot      Snapshot          `json:"snapshot"`
	APIPort       int               `json:"apiPort"`
	APISecret     string            `json:"apiSecret"`
	SecretValues  []string          `json:"-"`
	OutboundNames map[string]string `json:"-"`
}

// MobileLogs applies the same secret filtering, bounds and cursor as desktop.
type MobileLogs struct{ writer *coreLogWriter }

// NewMobileLogs constructs a memory-only log stream for one embedded core.
func NewMobileLogs(secrets []string) *MobileLogs {
	return &MobileLogs{writer: &coreLogWriter{logs: newLogBuffer(), secrets: secrets}}
}

// WriteLine sanitizes a core message before it enters the buffer.
func (l *MobileLogs) WriteLine(message string) {
	// coreLogWriter is an in-memory consumer which never returns an error.
	l.writer.Write([]byte(message + "\n"))
}

// Read returns bounded, sanitized cursor pages.
func (l *MobileLogs) Read(stream string, after int64) LogBatch {
	return l.writer.logs.read(stream, after)
}

// Clear advances the checkpoint without replaying earlier entries.
func (l *MobileLogs) Clear() LogBatch { return l.writer.logs.clear() }

// ForSession shares the public buffer, keeping credentials only in that session's
// writer. The service-wide store does not retain credentials after disconnect.
func (l *MobileLogs) ForSession(secrets []string) *MobileLogs {
	return &MobileLogs{writer: &coreLogWriter{logs: l.writer.logs, secrets: secrets}}
}

// CompileMobile reuses protocol, routing, chain and advanced-settings validation
// without desktop credential APIs, subprocesses or physical-interface binding.
func CompileMobile(raw []byte, tunnel bool) (MobileConfiguration, error) {
	return compileNativeRequest(raw, tunnel, mobileTunnelConfiguration)
}

// compileNativeRequest shares the validated domain compiler with native
// permission services, while each platform supplies its own capture policy.
func compileNativeRequest(raw []byte, tunnel bool, capture func([]byte) ([]byte, error)) (MobileConfiguration, error) {
	var result MobileConfiguration
	if len(raw) == 0 || len(raw) > 4<<20 {
		return result, fail("invalid_request", "连接请求大小无效")
	}
	var request MobileRequest
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&request); err != nil {
		return result, fail("invalid_request", "连接请求无效")
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		return result, fail("invalid_request", "连接请求包含额外数据")
	}
	if request.SystemProxy || request.TUN != tunnel || !validMode(request.Mode) ||
		(request.Node == nil) == (request.Chain == nil) || len(request.Secrets) > (maxRouteTargets+1)*maxChainHops {
		return result, fail("invalid_request", "连接目标、模式或接管设置无效")
	}
	if err := request.Routing.validate(true); err != nil {
		return result, err
	}
	settings := defaultRuntimeSettings()
	if request.RuntimeSettings != nil {
		settings = *request.RuntimeSettings
	}
	if err := settings.validate(); err != nil {
		return result, err
	}
	prepare := func(target RoutingOutbound) (preparedOutbound, error) {
		prepared := preparedOutbound{RoutingOutbound: target}
		nodes := []Node{target.Node}
		if target.Chain != nil {
			if err := target.Chain.validate(); err != nil {
				return prepared, err
			}
			nodes = target.Chain.Hops
		}
		for _, node := range nodes {
			if err := node.validate(); err != nil {
				return prepared, fail("invalid_node", "节点参数无效")
			}
			secret, found := request.Secrets[node.Credential]
			if node.Credential != "" && !found {
				return prepared, fail("credential_failed", "无法读取节点凭据，请重新保存节点")
			}
			auth := credentials{Username: secret.Username, Password: secret.Password, ObfsPassword: secret.ObfsPassword}
			if err := node.validateCredentials(auth); err != nil {
				return prepared, fail("invalid_credentials", "节点认证参数无效")
			}
			prepared.hops = append(prepared.hops, preparedHop{node: node, auth: auth})
		}
		return prepared, nil
	}
	primary := RoutingOutbound{Chain: request.Chain}
	target := Target{Kind: "chain"}
	if request.Node != nil {
		primary.Node = *request.Node
		target = Target{ID: request.Node.ID, Name: request.Node.Name, Revision: request.Node.Revision, Kind: "node"}
	} else {
		target.ID, target.Name, target.Revision = request.Chain.ID, request.Chain.Name, request.Chain.Revision
	}
	preparedPrimary, err := prepare(primary)
	if err != nil {
		return result, err
	}
	var prepared []preparedOutbound
	bindings := map[string]RouteBinding{}
	names := map[string]string{"proxy": target.Name, "direct": "直连"}
	if request.Chain != nil {
		primary.bindings("proxy", bindings)
	}
	if request.Routing != nil {
		for index, outbound := range request.Routing.Outbounds {
			entry, err := prepare(outbound)
			if err != nil {
				return result, err
			}
			prepared = append(prepared, entry)
			outbound.bindings(outbound.Key, bindings)
			names["route-"+strconv.Itoa(index)] = outbound.Name
		}
	}
	proxyPort := settings.ProxyPort
	if proxyPort == 0 {
		proxyPort, err = freePort()
		if err != nil {
			return result, fail("port_failed", "无法分配本地代理端口")
		}
	}
	apiPort, err := freePort()
	if err != nil || apiPort == proxyPort {
		return result, fail("port_failed", "无法分配本地控制端口，请重试")
	}
	secret := randomID()
	config, err := targetConfiguration(preparedPrimary, request.Mode, proxyPort, apiPort, secret, request.Routing, prepared, settings)
	if err != nil {
		return result, fail("invalid_config", "核心配置编译失败")
	}
	if tunnel {
		config, err = capture(config)
		if err != nil {
			return result, err
		}
	}
	digest := sha256.Sum256(config)
	ruleRevision := 0
	if request.Routing != nil {
		ruleRevision = request.Routing.Revision
	}
	result = MobileConfiguration{Configuration: string(config), APIPort: apiPort, APISecret: secret, OutboundNames: names,
		Snapshot: Snapshot{Phase: "connected", SessionID: randomID(), Target: &target, Mode: request.Mode,
			ConfigRevision: hex.EncodeToString(digest[:]), ProxyPort: proxyPort, TUN: tunnel,
			RuleRevision: ruleRevision, RouteBindings: bindings, RuntimeSettings: &settings}}
	result.SecretValues = []string{secret}
	for _, auth := range request.Secrets {
		result.SecretValues = append(result.SecretValues, auth.Username, auth.Password, auth.ObfsPassword)
	}
	return result, nil
}

func mobileTunnelConfiguration(raw []byte) ([]byte, error) {
	var config map[string]any
	if err := json.Unmarshal(raw, &config); err != nil {
		return nil, fail("invalid_config", "隧道配置编译失败")
	}
	// Capture both families even when AAAA resolution is disabled, preventing
	// literal IPv6 destinations from bypassing the selected proxy policy.
	inbound := map[string]any{"type": "tun", "tag": "tun-in", "interface_name": "rainlink",
		"address": []string{"172.29.255.1/30", "fdfe:dcba:9876::1/126"},
		"mtu":     1500, "auto_route": true, "strict_route": true, "stack": "gvisor"}
	config["inbounds"] = append(config["inbounds"].([]any), inbound)
	route := config["route"].(map[string]any)
	// DNS must be intercepted before global/direct mode rules; otherwise DNS
	// could be sent to the synthetic Android DNS address as a normal outbound.
	route["rules"] = append([]any{
		map[string]any{"inbound": "tun-in", "action": "sniff"},
		map[string]any{"port": 53, "action": "hijack-dns"},
	}, route["rules"].([]any)...)
	return json.Marshal(config)
}

// ValidateMobileRules validates the same editable rule contract as desktop.
func ValidateMobileRules(raw []byte) error {
	if len(raw) == 0 || len(raw) > 1<<20 {
		return fail("invalid_rules", "规则请求大小无效")
	}
	var plan RoutingPlan
	if json.Unmarshal(raw, &plan) != nil {
		return fail("invalid_rules", "规则格式无效")
	}
	return plan.validate(false)
}
