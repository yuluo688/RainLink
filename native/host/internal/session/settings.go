package session

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/url"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

const dnsTestTimeout = 6 * time.Second

// RuntimeSettings is validated at the host boundary and frozen per connection.
type RuntimeSettings struct {
	ProxyPort    int    `json:"proxyPort"`
	DNSMode      string `json:"dnsMode"`
	Resolver     string `json:"resolver"`
	BootstrapDNS string `json:"bootstrapDns"`
	IPv6         bool   `json:"ipv6"`
	LogLevel     string `json:"logLevel"`
	Advanced     string `json:"advanced,omitempty"`
}

func defaultRuntimeSettings() RuntimeSettings {
	return RuntimeSettings{DNSMode: "system", Resolver: "https://dns.alidns.com/dns-query", BootstrapDNS: "223.5.5.5", LogLevel: "info"}
}

func (s RuntimeSettings) validate() error {
	if s.ProxyPort < 0 || s.ProxyPort > 65535 {
		return fail("invalid_settings", "混合端口应为 1–65535，或使用 0 自动分配")
	}
	if s.DNSMode != "system" && s.DNSMode != "encrypted" && s.DNSMode != "custom" {
		return fail("invalid_settings", "DNS 模式无效")
	}
	if s.LogLevel != "debug" && s.LogLevel != "info" && s.LogLevel != "warn" && s.LogLevel != "error" {
		return fail("invalid_settings", "核心日志级别无效")
	}
	if len(s.Resolver) > 512 || len(s.BootstrapDNS) > 64 {
		return fail("invalid_settings", "DNS 地址过长")
	}
	if s.DNSMode != "system" {
		if net.ParseIP(s.BootstrapDNS) == nil {
			return fail("invalid_settings", "引导解析器应为 IPv4 或 IPv6 地址")
		}
		u, err := url.Parse(s.Resolver)
		if err != nil || u.Hostname() == "" || u.User != nil || u.RawQuery != "" || u.ForceQuery || u.Fragment != "" ||
			strings.ContainsAny(s.Resolver, " \r\n\t\x00") || (u.Scheme != "https" && u.Scheme != "udp") ||
			(s.DNSMode == "encrypted" && u.Scheme != "https") ||
			(u.Scheme == "udp" && (net.ParseIP(u.Hostname()) == nil || (u.Path != "" && u.Path != "/"))) {
			return fail("invalid_settings", "解析器应为 HTTPS 地址或 udp://IP:端口，不包含认证或查询参数")
		}
		if p := u.Port(); p != "" {
			port, err := strconv.Atoi(p)
			if err != nil || port < 1 || port > 65535 {
				return fail("invalid_settings", "DNS 端口无效")
			}
		}
	}
	_, err := parseAdvanced(s.Advanced, s.BootstrapDNS)
	return err
}

func selectedRuntimeSettings(values []RuntimeSettings) (RuntimeSettings, error) {
	settings := defaultRuntimeSettings()
	if len(values) > 0 {
		settings = values[0]
	}
	return settings, settings.validate()
}

func (s RuntimeSettings) dnsConfiguration(existing []any) (map[string]any, string) {
	strategy := "ipv4_only"
	if s.IPv6 {
		strategy = "prefer_ipv4"
	}
	final := "local-dns"
	if s.DNSMode != "system" {
		u, _ := url.Parse(s.Resolver) // validate precedes compilation.
		port := 443
		typeName := "https"
		if u.Scheme == "udp" {
			port, typeName = 53, "udp"
		}
		if u.Port() != "" {
			port, _ = strconv.Atoi(u.Port())
		}
		entry := map[string]any{"type": typeName, "tag": "user-dns", "server": u.Hostname(), "server_port": port}
		if typeName == "https" {
			path := u.EscapedPath()
			if path == "" {
				path = "/dns-query"
			}
			entry["path"] = path
			entry["tls"] = map[string]any{"enabled": true, "server_name": u.Hostname()}
			if net.ParseIP(u.Hostname()) == nil {
				existing = append(existing, map[string]any{"type": "udp", "tag": "bootstrap-dns", "server": s.BootstrapDNS, "server_port": 53})
				entry["domain_resolver"] = map[string]any{"server": "bootstrap-dns", "strategy": "ipv4_only"}
			}
		}
		existing = append(existing, entry)
		final = "user-dns"
	}
	return map[string]any{"servers": existing, "final": final, "strategy": strategy}, final
}

// ValidateRuntime checks the bundled core without starting a session or capture.
func (m *Manager) ValidateRuntime(ctx context.Context, settings RuntimeSettings) error {
	if err := settings.validate(); err != nil {
		return err
	}
	node := Node{ID: "settings-check", Name: "配置校验", Revision: 1, Protocol: "http", Server: "127.0.0.1", Port: 9}
	primary := preparedOutbound{RoutingOutbound: RoutingOutbound{Node: node}}
	config, err := targetConfiguration(primary, "rule", 17890, 17891, "validation", nil, nil, settings)
	if err != nil {
		return fail("invalid_settings", "网络配置无效")
	}
	command := exec.CommandContext(ctx, m.corePath, "check", "-c", "stdin")
	hideWindow(command)
	command.Stdin = bytes.NewReader(config)
	if err = command.Run(); err != nil {
		return fail("config_rejected", "核心未通过配置校验，原设置已保留")
	}
	return nil
}

// DNSTestResult reports an actual A-record lookup independent of live sessions.
type DNSTestResult struct {
	Addresses []string `json:"addresses"`
	Latency   int64    `json:"latency"`
}

func resolverAt(address string) *net.Resolver {
	return resolverUsing(address, &net.Dialer{})
}

func resolverUsing(address string, dialer *net.Dialer) *net.Resolver {
	return &net.Resolver{PreferGo: true, Dial: func(ctx context.Context, network, _ string) (net.Conn, error) {
		return dialer.DialContext(ctx, network, address)
	}}
}

// TestDNS uses direct local network requests; it never changes the system DNS.
func (m *Manager) TestDNS(ctx context.Context, settings RuntimeSettings) (DNSTestResult, error) {
	return TestDNSWithDialer(ctx, settings, &net.Dialer{})
}

// TestDNSWithDialer lets mobile protect and bind every resolver and HTTPS socket
// to its physical network, while sharing the validated DNS test and decoder.
func TestDNSWithDialer(ctx context.Context, settings RuntimeSettings, physical *net.Dialer) (DNSTestResult, error) {
	if err := settings.validate(); err != nil {
		return DNSTestResult{}, err
	}
	ctx, cancel := context.WithTimeout(ctx, dnsTestTimeout)
	defer cancel()
	start := time.Now()
	var addresses []net.IP
	var err error
	if settings.DNSMode == "system" {
		addresses, err = net.DefaultResolver.LookupIP(ctx, "ip4", "example.com")
	} else {
		u, _ := url.Parse(settings.Resolver)
		if u.Scheme == "udp" {
			port := u.Port()
			if port == "" {
				port = "53"
			}
			addresses, err = resolverUsing(net.JoinHostPort(u.Hostname(), port), physical).LookupIP(ctx, "ip4", "example.com")
		} else {
			dialer := *physical
			dialer.Resolver = resolverUsing(net.JoinHostPort(settings.BootstrapDNS, "53"), physical)
			transport := &http.Transport{Proxy: nil, DialContext: dialer.DialContext, TLSHandshakeTimeout: 3 * time.Second}
			defer transport.CloseIdleConnections()
			if u.Path == "" {
				u.Path = "/dns-query"
			}
			addresses, err = testDoH(ctx, &http.Client{Transport: transport, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}, u.String())
		}
	}
	if err != nil || len(addresses) == 0 {
		return DNSTestResult{}, fail("dns_test_failed", "解析测试失败，请检查解析器、引导 DNS 和本机网络")
	}
	result := DNSTestResult{Latency: time.Since(start).Milliseconds()}
	seen := map[string]bool{}
	for _, ip := range addresses {
		if value := ip.String(); !seen[value] {
			result.Addresses = append(result.Addresses, value)
			seen[value] = true
		}
	}
	return result, nil
}

func testDoH(ctx context.Context, client *http.Client, endpoint string) ([]net.IP, error) {
	query := []byte{0x52, 0x4c, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 7, 'e', 'x', 'a', 'm', 'p', 'l', 'e', 3, 'c', 'o', 'm', 0, 0, 1, 0, 1}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(query))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/dns-message")
	req.Header.Set("Accept", "application/dns-message")
	response, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK || !strings.HasPrefix(response.Header.Get("Content-Type"), "application/dns-message") {
		return nil, errors.New("invalid DoH response")
	}
	packet, err := io.ReadAll(io.LimitReader(response.Body, 65537))
	if err != nil || len(packet) > 65536 {
		return nil, errors.New("invalid DNS body")
	}
	return dohAddresses(packet, query)
}

func dohAddresses(packet, query []byte) ([]net.IP, error) {
	invalid := errors.New("invalid DNS response")
	if len(packet) < len(query) || !bytes.Equal(packet[:2], query[:2]) || packet[2]&0x82 != 0x80 || packet[3]&0x0f != 0 || binary.BigEndian.Uint16(packet[4:6]) != 1 || !bytes.Equal(packet[12:len(query)], query[12:]) {
		return nil, invalid
	}
	count := int(binary.BigEndian.Uint16(packet[6:8]))
	if count > 256 {
		return nil, invalid
	}
	position := len(query)
	var addresses []net.IP
	for i := 0; i < count; i++ {
		labels := 0
		for {
			if position >= len(packet) || labels > 127 {
				return nil, invalid
			}
			length := int(packet[position])
			position++
			labels++
			if length == 0 {
				break
			}
			if length&0xc0 == 0xc0 {
				if position >= len(packet) || (length&0x3f)<<8|int(packet[position]) >= len(packet) {
					return nil, invalid
				}
				position++
				break
			}
			if length > 63 || position+length > len(packet) {
				return nil, invalid
			}
			position += length
		}
		if position+10 > len(packet) {
			return nil, invalid
		}
		typeID := binary.BigEndian.Uint16(packet[position : position+2])
		class := binary.BigEndian.Uint16(packet[position+2 : position+4])
		length := int(binary.BigEndian.Uint16(packet[position+8 : position+10]))
		position += 10
		if position+length > len(packet) {
			return nil, invalid
		}
		if typeID == 1 && class == 1 && length == 4 {
			addresses = append(addresses, net.IP(append([]byte(nil), packet[position:position+4]...)))
		}
		position += length
	}
	return addresses, nil
}

// Keep settings JSON independent from credentials and core configuration files.
func decodeRuntime(raw json.RawMessage) (RuntimeSettings, error) {
	settings := defaultRuntimeSettings()
	if len(raw) == 0 || bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
		return settings, fail("invalid_settings", "网络设置格式无效")
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&settings); err != nil {
		return settings, fail("invalid_settings", "网络设置格式无效")
	}
	return settings, settings.validate()
}
