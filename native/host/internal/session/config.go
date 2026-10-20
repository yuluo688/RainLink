// Package session owns a desktop core session independently of Flutter pages.
package session

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net"
	"regexp"
	"strconv"
	"strings"
	"unicode/utf8"
)

// Node is an upstream snapshot. Credentials use platform-protected ciphertext.
type Node struct {
	ID         string      `json:"id"`
	Name       string      `json:"name"`
	Revision   int         `json:"revision"`
	Protocol   string      `json:"protocol"`
	Server     string      `json:"server"`
	Port       int         `json:"port"`
	TLS        bool        `json:"tls"`
	Credential string      `json:"credential"`
	Options    NodeOptions `json:"options"`
}

// NodeOptions contains public settings only. Secrets stay in Credential.
type NodeOptions struct {
	Method              string   `json:"method"`
	ServerName          string   `json:"serverName"`
	Insecure            bool     `json:"insecure"`
	Transport           string   `json:"transport"`
	Path                string   `json:"path"`
	Host                string   `json:"host"`
	ServiceName         string   `json:"serviceName"`
	Flow                string   `json:"flow"`
	Fingerprint         string   `json:"fingerprint"`
	CertificateSHA256   string   `json:"certificateSha256"`
	RealityPublicKey    string   `json:"realityPublicKey"`
	RealityShortID      string   `json:"realityShortId"`
	ALPN                []string `json:"alpn"`
	Obfs                string   `json:"obfs"`
	UpMbps              int      `json:"upMbps"`
	DownMbps            int      `json:"downMbps"`
	ServerPorts         []string `json:"serverPorts"`
	HopIntervalSeconds  int      `json:"hopIntervalSeconds"`
	VMessSecurity       string   `json:"vmessSecurity"`
	AlterID             int      `json:"alterId"`
	GlobalPadding       bool     `json:"globalPadding"`
	AuthenticatedLength bool     `json:"authenticatedLength"`
	PacketEncoding      string   `json:"packetEncoding"`
	CongestionControl   string   `json:"congestionControl"`
	UDPRelayMode        string   `json:"udpRelayMode"`
	UDPOverStream       bool     `json:"udpOverStream"`
	ZeroRTTHandshake    bool     `json:"zeroRttHandshake"`
	HeartbeatMillis     int      `json:"heartbeatMillis"`
	DisableSNI          bool     `json:"disableSni"`
}

type credentials struct {
	Username     string `json:"username"`
	Password     string `json:"password"`
	ObfsPassword string `json:"obfsPassword,omitempty"`
}

func (n Node) usesQUIC() bool { return n.Protocol == "hysteria2" || n.Protocol == "tuic" }

func (n Node) validate() error {
	if n.ID == "" || len(n.ID) > 128 || strings.TrimSpace(n.Name) == "" || !utf8.ValidString(n.Name) || utf8.RuneCountInString(n.Name) > 128 || n.Revision < 1 {
		return errors.New("节点标识或名称无效")
	}
	if n.Protocol != "http" && n.Protocol != "socks" && n.Protocol != "shadowsocks" && n.Protocol != "vless" && n.Protocol != "trojan" && !n.usesQUIC() && n.Protocol != "vmess" {
		return errors.New("暂不支持此节点协议")
	}
	if n.Port < 1 || n.Port > 65535 {
		return errors.New("端口必须在 1–65535 之间")
	}
	if n.Server == "" || len(n.Server) > 253 || strings.ContainsAny(n.Server, " /\\\r\n\t@?#\x00") {
		return errors.New("服务器地址应为域名或 IP，不包含协议或路径")
	}
	if strings.Contains(n.Server, ":") && net.ParseIP(n.Server) == nil {
		return errors.New("IPv6 地址无效")
	}
	if n.TLS && (n.Protocol == "socks" || n.Protocol == "shadowsocks") || (n.Protocol == "trojan" || n.usesQUIC()) && !n.TLS {
		return errors.New("节点 TLS 设置与协议不匹配")
	}
	return n.validateOptions()
}

func (n Node) validateOptions() error {
	o := n.Options
	if len(o.ServerName) > 253 || strings.ContainsAny(o.ServerName, " /\\\r\n\t\x00") || len(o.Host) > 512 || strings.ContainsAny(o.Host, "\r\n\x00") || len(o.Path) > 2048 || strings.ContainsAny(o.Path, "\r\n\x00") || len(o.ServiceName) > 256 || strings.ContainsAny(o.ServiceName, "\r\n\x00") {
		return errors.New("TLS 或传输参数无效")
	}
	switch o.Transport {
	case "", "tcp":
	case "quic":
		if !n.usesQUIC() {
			return errors.New("QUIC 仅用于 Hysteria2 和 TUIC")
		}
	case "ws", "grpc":
		if n.Protocol != "vless" && n.Protocol != "trojan" && n.Protocol != "vmess" {
			return errors.New("此协议不支持附加传输")
		}
	default:
		return errors.New("暂不支持此传输方式")
	}
	if n.usesQUIC() {
		if o.CertificateSHA256 != "" && !regexp.MustCompile(`^[a-fA-F0-9]{64}$`).MatchString(o.CertificateSHA256) {
			return errors.New("证书 SHA-256 指纹无效")
		}
		if o.Transport != "quic" || o.Fingerprint != "" {
			return errors.New("QUIC 传输或 TLS 指纹设置无效")
		}
	} else if o.CertificateSHA256 != "" {
		return errors.New("QUIC 证书指纹选项与协议不匹配")
	}
	if n.Protocol == "hysteria2" {
		if o.Obfs != "" && o.Obfs != "salamander" {
			return errors.New("Hysteria2 混淆设置无效")
		}
		if o.UpMbps < 0 || o.DownMbps < 0 || o.UpMbps > 1000000 || o.DownMbps > 1000000 {
			return errors.New("Hysteria2 带宽超出范围")
		}
		if len(o.ServerPorts) > 64 {
			return errors.New("跳跃端口数量超出限制")
		}
		for _, span := range o.ServerPorts {
			parts := strings.Split(span, ":")
			if len(parts) > 2 {
				return errors.New("跳跃端口无效")
			}
			start, err := strconv.Atoi(parts[0])
			if err != nil || start < 1 || start > 65535 {
				return errors.New("跳跃端口无效")
			}
			if len(parts) == 2 {
				end, err := strconv.Atoi(parts[1])
				if err != nil || end < start || end > 65535 {
					return errors.New("跳跃端口范围无效")
				}
			}
		}
		if o.HopIntervalSeconds != 0 && (len(o.ServerPorts) == 0 || o.HopIntervalSeconds < 5 || o.HopIntervalSeconds > 86400) {
			return errors.New("端口跳跃间隔无效")
		}
	} else if o.Obfs != "" || o.UpMbps != 0 || o.DownMbps != 0 || len(o.ServerPorts) != 0 || o.HopIntervalSeconds != 0 {
		return errors.New("Hysteria2 选项与协议不匹配")
	}
	if n.Protocol == "tuic" {
		switch o.CongestionControl {
		case "", "cubic", "new_reno", "bbr":
		default:
			return errors.New("TUIC 拥塞控制算法无效")
		}
		if o.UDPRelayMode != "" && o.UDPRelayMode != "native" && o.UDPRelayMode != "quic" || o.UDPOverStream && o.UDPRelayMode == "quic" || o.HeartbeatMillis != 0 && (o.HeartbeatMillis < 1000 || o.HeartbeatMillis > 3600000) {
			return errors.New("TUIC UDP 中继或心跳间隔无效")
		}
	} else if o.CongestionControl != "" && o.CongestionControl != "cubic" || o.UDPRelayMode != "" && o.UDPRelayMode != "native" || o.UDPOverStream || o.ZeroRTTHandshake || o.HeartbeatMillis != 0 && o.HeartbeatMillis != 10000 || o.DisableSNI {
		return errors.New("TUIC 选项与协议不匹配")
	}
	if n.Protocol == "vmess" {
		switch o.VMessSecurity {
		case "", "auto", "none", "zero", "aes-128-gcm", "chacha20-poly1305":
		default:
			return errors.New("VMess 加密方式无效")
		}
		if o.AlterID < 0 || o.AlterID > 65535 {
			return errors.New("VMess Alter ID 超出范围")
		}
	} else if o.VMessSecurity != "" && o.VMessSecurity != "auto" || o.AlterID != 0 || o.GlobalPadding || o.AuthenticatedLength {
		return errors.New("VMess 选项与协议不匹配")
	}
	if o.PacketEncoding != "" && ((n.Protocol != "vmess" && n.Protocol != "vless") || (o.PacketEncoding != "packetaddr" && o.PacketEncoding != "xudp")) {
		return errors.New("UDP 包编码无效或与协议不匹配")
	}
	if o.Transport == "ws" && o.Path != "" && !strings.HasPrefix(o.Path, "/") {
		return errors.New("WebSocket 路径无效")
	}
	switch o.Fingerprint {
	case "", "chrome", "firefox", "safari", "ios", "android", "edge", "random", "randomized":
	default:
		return errors.New("TLS 指纹无效")
	}
	if o.Flow != "" && (n.Protocol != "vless" || !n.TLS || o.Flow != "xtls-rprx-vision" || (o.Transport != "" && o.Transport != "tcp")) {
		return errors.New("Vision 参数无效")
	}
	if len(o.ALPN) > 8 {
		return errors.New("ALPN 参数无效")
	}
	for _, v := range o.ALPN {
		if v == "" || len(v) > 64 || strings.ContainsAny(v, "\r\n\x00") {
			return errors.New("ALPN 参数无效")
		}
	}
	if o.RealityPublicKey != "" {
		key, err := base64.RawURLEncoding.DecodeString(strings.TrimRight(o.RealityPublicKey, "="))
		if err != nil || len(key) != 32 || !n.TLS || n.Protocol != "vless" || o.Fingerprint == "" || !regexp.MustCompile(`^(?:[a-fA-F0-9]{2}){0,8}$`).MatchString(o.RealityShortID) {
			return errors.New("Reality 参数无效")
		}
	}
	if o.RealityShortID != "" && o.RealityPublicKey == "" {
		return errors.New("Reality Short ID 需要公钥")
	}
	return nil
}

func (n Node) validateCredentials(auth credentials) error {
	if len(auth.Username) > 4096 || len(auth.Password) > 4096 || len(auth.ObfsPassword) > 4096 {
		return errors.New("凭据超过长度限制")
	}
	switch n.Protocol {
	case "hysteria2":
		if auth.Username != "" || auth.Password == "" || n.Options.Obfs != "" && auth.ObfsPassword == "" {
			return errors.New("Hysteria2 认证或混淆密码无效")
		}
	case "tuic":
		if !validNodeUUID(auth.Username) || auth.ObfsPassword != "" {
			return errors.New("TUIC v5 UUID 或凭据无效")
		}
	case "vless", "vmess":
		if !validNodeUUID(auth.Password) {
			return errors.New("VLESS / VMess UUID 无效")
		}
	case "trojan":
		if auth.Password == "" {
			return errors.New("Trojan 密码不能为空")
		}
	case "shadowsocks":
		if auth.Password == "" {
			return errors.New("Shadowsocks 密码不能为空")
		}
		switch n.Options.Method {
		case "aes-128-gcm", "aes-256-gcm", "chacha20-ietf-poly1305":
		case "2022-blake3-aes-128-gcm", "2022-blake3-aes-256-gcm", "2022-blake3-chacha20-poly1305":
			size := 32
			if n.Options.Method == "2022-blake3-aes-128-gcm" {
				size = 16
			}
			for _, part := range strings.Split(auth.Password, ":") {
				decoded, err := base64.StdEncoding.DecodeString(part)
				if err != nil || len(decoded) != size {
					return errors.New("Shadowsocks 2022 密钥无效")
				}
			}
		default:
			return errors.New("暂不支持此 Shadowsocks 加密方式")
		}
	}
	return nil
}

func validNodeUUID(value string) bool {
	return regexp.MustCompile(`^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$`).MatchString(value)
}

func validMode(mode string) bool   { return mode == "rule" || mode == "global" || mode == "direct" }
func clashMode(mode string) string { return mode }

func randomID() string {
	return rand.Text()
}

func freePort() (int, error) {
	l, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	port := l.Addr().(*net.TCPAddr).Port
	return port, l.Close()
}

func configuration(node Node, auth credentials, mode string, proxyPort, apiPort int, secret string, network upstreamNetwork) ([]byte, error) {
	return routingConfiguration(node, auth, mode, proxyPort, apiPort, secret, network, nil, nil)
}

func outboundDNSKey(tag string) string {
	if tag == "proxy" {
		return upstreamDNSTag
	}
	return upstreamDNSTag + "-" + tag
}

func compileOutbound(node Node, auth credentials, tag string, network upstreamNetwork) (map[string]any, error) {
	if err := node.validateCredentials(auth); err != nil {
		return nil, err
	}
	out := map[string]any{"type": node.Protocol, "tag": tag, "server": node.Server, "server_port": node.Port}
	if network.InterfaceName != "" {
		out["bind_interface"] = network.InterfaceName
	}
	if network.EncryptedDNS {
		out["domain_resolver"] = map[string]any{"server": outboundDNSKey(tag), "strategy": "prefer_ipv4"}
	}
	if auth.Username != "" && (node.Protocol == "http" || node.Protocol == "socks") {
		out["username"] = auth.Username
	}
	if node.Protocol == "vless" || node.Protocol == "vmess" {
		out["uuid"] = auth.Password
		if node.Options.Flow != "" {
			out["flow"] = node.Options.Flow
		}
	} else if auth.Password != "" {
		out["password"] = auth.Password
	}
	if node.Protocol == "vmess" {
		security := node.Options.VMessSecurity
		if security == "" {
			security = "auto"
		}
		out["security"] = security
		out["alter_id"] = node.Options.AlterID
		out["global_padding"] = node.Options.GlobalPadding
		out["authenticated_length"] = node.Options.AuthenticatedLength
	}
	if node.Options.PacketEncoding != "" {
		out["packet_encoding"] = node.Options.PacketEncoding
	}
	if node.Protocol == "tuic" {
		out["uuid"] = auth.Username
		if node.Options.CongestionControl != "" {
			out["congestion_control"] = node.Options.CongestionControl
		}
		if node.Options.UDPOverStream {
			out["udp_over_stream"] = true
		} else if node.Options.UDPRelayMode != "" {
			out["udp_relay_mode"] = node.Options.UDPRelayMode
		}
		out["zero_rtt_handshake"] = node.Options.ZeroRTTHandshake
		if node.Options.HeartbeatMillis > 0 {
			out["heartbeat"] = strconv.Itoa(node.Options.HeartbeatMillis) + "ms"
		}
	}
	if node.Protocol == "socks" {
		out["version"] = "5"
	}
	if node.Protocol == "shadowsocks" {
		out["method"] = node.Options.Method
	}
	if node.Protocol == "hysteria2" {
		if node.Options.UpMbps > 0 {
			out["up_mbps"] = node.Options.UpMbps
		}
		if node.Options.DownMbps > 0 {
			out["down_mbps"] = node.Options.DownMbps
		}
		if node.Options.Obfs != "" {
			out["obfs"] = map[string]any{"type": node.Options.Obfs, "password": auth.ObfsPassword}
		}
		if len(node.Options.ServerPorts) > 0 {
			ports := make([]string, 0, len(node.Options.ServerPorts))
			for _, span := range node.Options.ServerPorts {
				if !strings.Contains(span, ":") {
					span += ":" + span
				}
				ports = append(ports, span)
			}
			out["server_ports"] = ports
		}
		if node.Options.HopIntervalSeconds > 0 {
			out["hop_interval"] = strconv.Itoa(node.Options.HopIntervalSeconds) + "s"
		}
	}
	if node.TLS {
		sni := node.Options.ServerName
		if sni == "" {
			sni = node.Server
		}
		tls := map[string]any{"enabled": true, "server_name": sni, "insecure": node.Options.Insecure}
		if node.Options.DisableSNI {
			tls["disable_sni"] = true
		}
		if node.Options.CertificateSHA256 != "" {
			tls["rainlink_certificate_sha256"] = node.Options.CertificateSHA256
		}
		if len(node.Options.ALPN) > 0 {
			tls["alpn"] = node.Options.ALPN
		}
		if node.Options.Fingerprint != "" {
			tls["utls"] = map[string]any{"enabled": true, "fingerprint": node.Options.Fingerprint}
		}
		if node.Options.RealityPublicKey != "" {
			tls["reality"] = map[string]any{"enabled": true, "public_key": node.Options.RealityPublicKey, "short_id": node.Options.RealityShortID}
		}
		out["tls"] = tls
	}
	if node.Options.Transport == "ws" {
		path := node.Options.Path
		if path == "" {
			path = "/"
		}
		transport := map[string]any{"type": "ws", "path": path}
		if node.Options.Host != "" {
			transport["headers"] = map[string]string{"Host": node.Options.Host}
		}
		out["transport"] = transport
	} else if node.Options.Transport == "grpc" {
		out["transport"] = map[string]any{"type": "grpc", "service_name": node.Options.ServiceName}
	}
	return out, nil
}

func routingConfiguration(node Node, auth credentials, mode string, proxyPort, apiPort int, secret string, network upstreamNetwork, plan *RoutingPlan, prepared []preparedOutbound) ([]byte, error) {
	return targetConfiguration(preparedOutbound{RoutingOutbound: RoutingOutbound{Node: node}, auth: auth, network: network}, mode, proxyPort, apiPort, secret, plan, prepared)
}

func targetConfiguration(primary preparedOutbound, mode string, proxyPort, apiPort int, secret string, plan *RoutingPlan, prepared []preparedOutbound, values ...RuntimeSettings) ([]byte, error) {
	settings, err := selectedRuntimeSettings(values)
	if err != nil {
		return nil, err
	}
	outbounds := []any{}
	dnsServers := []any{map[string]any{"type": "local", "tag": "local-dns"}}
	appendDNS := func(tag string, upstream upstreamNetwork) {
		if !upstream.EncryptedDNS {
			return
		}
		dnsServers = append(dnsServers, map[string]any{
			"type": "https", "tag": outboundDNSKey(tag), "server": upstreamDNSServer, "server_port": 443, "path": "/dns-query",
			"tls": map[string]any{"enabled": true, "server_name": upstreamDNSServerName}, "bind_interface": upstream.InterfaceName,
		})
	}
	appendTarget := func(tag string, target preparedOutbound) error {
		hops := target.allHops()
		previous := ""
		for index, hop := range hops {
			hopTag := tag
			if index < len(hops)-1 {
				hopTag = tag + "-hop-" + strconv.Itoa(index)
			}
			compiled, compileErr := compileOutbound(hop.node, hop.auth, hopTag, hop.network)
			if compileErr != nil {
				return compileErr
			}
			if previous != "" {
				compiled["detour"] = previous
				delete(compiled, "bind_interface")
				delete(compiled, "domain_resolver")
			} else {
				appendDNS(hopTag, hop.network)
			}
			outbounds = append(outbounds, compiled)
			previous = hopTag
		}
		return nil
	}
	if err := appendTarget("proxy", primary); err != nil {
		return nil, err
	}
	outbounds = append(outbounds, map[string]any{"type": "direct", "tag": "direct"})
	tags := map[string]string{}
	for index, target := range prepared {
		tag := "route-" + strconv.Itoa(index)
		if err := appendTarget(tag, target); err != nil {
			return nil, err
		}
		tags[target.Key] = tag
	}
	rules, err := compileRouteRules(plan, tags)
	if err != nil {
		return nil, err
	}
	dns, resolver := settings.dnsConfiguration(dnsServers)
	config := map[string]any{
		"log":          map[string]any{"level": settings.LogLevel},
		"dns":          dns,
		"inbounds":     []any{map[string]any{"type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": proxyPort}},
		"outbounds":    outbounds,
		"route":        map[string]any{"default_domain_resolver": resolver, "rules": rules, "final": "proxy", "find_process": true},
		"experimental": map[string]any{"clash_api": map[string]any{"external_controller": net.JoinHostPort("127.0.0.1", strconv.Itoa(apiPort)), "secret": secret, "default_mode": clashMode(mode)}},
	}
	if err := applyAdvanced(config, settings); err != nil {
		return nil, err
	}
	return json.Marshal(config)
}
