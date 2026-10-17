package session

import (
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/netip"
	"regexp"
	"strconv"
	"strings"
)

const (
	maxAdvancedBytes        = 16 << 10
	maxAdvancedDepth        = 12
	maxAdvancedValues       = 2048
	maxAdvancedServers      = 8
	maxAdvancedRules        = 64
	maxAdvancedConditions   = 64
	maxAdvancedCacheEntries = 65536
)

type advancedPatch struct {
	Log   *advancedLog   `json:"log,omitempty"`
	DNS   *advancedDNS   `json:"dns,omitempty"`
	Route *advancedRoute `json:"route,omitempty"`
}

type advancedLog struct {
	Level     string `json:"level,omitempty"`
	Timestamp *bool  `json:"timestamp,omitempty"`
}

type advancedDNS struct {
	Servers          []advancedServer  `json:"servers,omitempty"`
	Final            string            `json:"final,omitempty"`
	Strategy         string            `json:"strategy,omitempty"`
	DisableCache     *bool             `json:"disable_cache,omitempty"`
	DisableExpire    *bool             `json:"disable_expire,omitempty"`
	IndependentCache *bool             `json:"independent_cache,omitempty"`
	CacheCapacity    *int              `json:"cache_capacity,omitempty"`
	Rules            []advancedDNSRule `json:"rules,omitempty"`
}

type advancedServer struct {
	Type       string       `json:"type"`
	Tag        string       `json:"tag,omitempty"`
	Server     string       `json:"server,omitempty"`
	ServerPort int          `json:"server_port,omitempty"`
	Path       string       `json:"path,omitempty"`
	TLS        *advancedTLS `json:"tls,omitempty"`
}

type advancedTLS struct {
	Enabled    *bool  `json:"enabled,omitempty"`
	ServerName string `json:"server_name,omitempty"`
}

type advancedDomainMatch struct {
	Domain        []string `json:"domain,omitempty"`
	DomainSuffix  []string `json:"domain_suffix,omitempty"`
	DomainKeyword []string `json:"domain_keyword,omitempty"`
}

type advancedDNSRule struct {
	advancedDomainMatch
	Action string `json:"action,omitempty"`
	Server string `json:"server,omitempty"`
}

type advancedRoute struct {
	Rules []advancedRouteRule `json:"rules,omitempty"`
}

type advancedRouteRule struct {
	advancedDomainMatch
	IPCIDR      []string `json:"ip_cidr,omitempty"`
	IPIsPrivate *bool    `json:"ip_is_private,omitempty"`
	Port        []int    `json:"port,omitempty"`
	Network     []string `json:"network,omitempty"`
	Action      string   `json:"action,omitempty"`
	Outbound    string   `json:"outbound,omitempty"`
}

func invalidAdvanced(message string) error { return fail("invalid_advanced", message) }

// Inspect tokens before decoding structs: encoding/json otherwise accepts
// duplicate keys and null scalar fields. Never quote input in public errors.
func inspectAdvanced(decoder *json.Decoder, depth int, count *int) error {
	(*count)++
	if depth > maxAdvancedDepth || *count > maxAdvancedValues {
		return errors.New("advanced configuration too complex")
	}
	token, err := decoder.Token()
	if err != nil || token == nil {
		return errors.New("invalid advanced token")
	}
	if delimiter, ok := token.(json.Delim); ok {
		switch delimiter {
		case '{':
			seen := map[string]bool{}
			for decoder.More() {
				key, err := decoder.Token()
				name, valid := key.(string)
				if err != nil || !valid || !advancedFieldPattern.MatchString(name) || seen[name] {
					return errors.New("duplicate advanced field")
				}
				seen[name] = true
				if err := inspectAdvanced(decoder, depth+1, count); err != nil {
					return err
				}
			}
		case '[':
			for decoder.More() {
				if err := inspectAdvanced(decoder, depth+1, count); err != nil {
					return err
				}
			}
		default:
			return errors.New("unexpected advanced delimiter")
		}
		_, err = decoder.Token()
		return err
	}
	return nil
}

func parseAdvanced(raw string, bootstrap string) (advancedPatch, error) {
	var patch advancedPatch
	if raw == "" {
		return patch, nil
	}
	if len(raw) > maxAdvancedBytes || !strings.HasPrefix(strings.TrimSpace(raw), "{") {
		return patch, invalidAdvanced("高级配置应为不超过 16 KB 的对象")
	}
	decoder := json.NewDecoder(strings.NewReader(raw))
	decoder.UseNumber()
	count := 0
	if err := inspectAdvanced(decoder, 0, &count); err != nil {
		return patch, invalidAdvanced("高级配置包含无效值、重复字段，或结构过于复杂")
	}
	if _, err := decoder.Token(); err != io.EOF {
		return patch, invalidAdvanced("高级配置只能包含一个对象")
	}
	decoder = json.NewDecoder(strings.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&patch); err != nil {
		return patch, invalidAdvanced("高级配置包含未支持的字段或字段类型错误，请查看支持范围；监听、认证与控制接口由 RainLink 管理")
	}
	if patch.Log != nil && patch.Log.Level != "" && patch.Log.Level != "debug" && patch.Log.Level != "info" && patch.Log.Level != "warn" && patch.Log.Level != "error" {
		return patch, invalidAdvanced("log.level 应为 debug、info、warn 或 error")
	}
	if patch.DNS != nil {
		if err := patch.DNS.validate(bootstrap); err != nil {
			return patch, err
		}
	}
	if patch.Route != nil {
		if len(patch.Route.Rules) > maxAdvancedRules {
			return patch, invalidAdvanced("高级分流规则最多 64 条")
		}
		for _, rule := range patch.Route.Rules {
			if err := rule.validate(); err != nil {
				return patch, err
			}
		}
	}
	return patch, nil
}

func (match advancedDomainMatch) validate() error {
	for _, field := range []struct {
		values []string
		kind   string
	}{{match.Domain, "DOMAIN"}, {match.DomainSuffix, "DOMAIN-SUFFIX"}, {match.DomainKeyword, "KEYWORD"}} {
		if len(field.values) > maxAdvancedConditions {
			return invalidAdvanced("每条规则的同类匹配条件最多 64 项")
		}
		for _, value := range field.values {
			if field.kind == "KEYWORD" {
				if value == "" || len(value) > 253 || strings.ContainsAny(value, " \r\n\t\x00@/?#") {
					return invalidAdvanced("domain_keyword 应为不含地址、认证或空白的域名关键词")
				}
			} else if _, err := normalizeRouteValue(field.kind, value); err != nil {
				return invalidAdvanced("domain 或 domain_suffix 应为域名，不含协议、路径或通配符")
			}
		}
	}
	return nil
}

func (match advancedDomainMatch) hasConditions() bool {
	return len(match.Domain)+len(match.DomainSuffix)+len(match.DomainKeyword) > 0
}

func (match advancedDomainMatch) compile() map[string]any {
	value := map[string]any{}
	for key, values := range map[string][]string{"domain": match.Domain, "domain_suffix": match.DomainSuffix, "domain_keyword": match.DomainKeyword} {
		if len(values) > 0 {
			normalized := make([]string, len(values))
			for index, entry := range values {
				normalized[index] = strings.ToLower(strings.TrimSpace(entry))
				if key != "domain_keyword" {
					normalized[index] = strings.TrimSuffix(normalized[index], ".")
				}
			}
			value[key] = normalized
		}
	}
	return value
}

func (rule advancedRouteRule) validate() error {
	if err := rule.advancedDomainMatch.validate(); err != nil {
		return err
	}
	if len(rule.IPCIDR) > maxAdvancedConditions || len(rule.Port) > maxAdvancedConditions || len(rule.Network) > 2 {
		return invalidAdvanced("分流规则的匹配条件超出限制")
	}
	for _, prefix := range rule.IPCIDR {
		if _, err := netip.ParsePrefix(prefix); err != nil {
			return invalidAdvanced("ip_cidr 应为有效的 IPv4 或 IPv6 网段")
		}
	}
	for _, port := range rule.Port {
		if port < 1 || port > 65535 {
			return invalidAdvanced("规则端口应为 1–65535")
		}
	}
	for _, network := range rule.Network {
		if network != "tcp" && network != "udp" {
			return invalidAdvanced("network 仅支持 tcp 和 udp")
		}
	}
	private := rule.IPIsPrivate != nil && *rule.IPIsPrivate
	if (rule.IPIsPrivate != nil && !private) || (!rule.hasConditions() && !private && len(rule.IPCIDR)+len(rule.Port)+len(rule.Network) == 0) {
		return invalidAdvanced("高级分流规则必须指定匹配条件，兜底规则请在规则页管理")
	}
	if rule.Action == "reject" && rule.Outbound == "" {
		return nil
	}
	if (rule.Action == "" || rule.Action == "route") && (rule.Outbound == "proxy" || rule.Outbound == "direct") {
		return nil
	}
	return invalidAdvanced("分流规则仅支持 route 到 proxy/direct，或不含 outbound 的 reject")
}

func (rule advancedRouteRule) compile() map[string]any {
	value := rule.advancedDomainMatch.compile()
	if len(rule.IPCIDR) > 0 {
		value["ip_cidr"] = rule.IPCIDR
	}
	if rule.IPIsPrivate != nil {
		value["ip_is_private"] = *rule.IPIsPrivate
	}
	if len(rule.Port) > 0 {
		value["port"] = rule.Port
	}
	if len(rule.Network) > 0 {
		value["network"] = rule.Network
	}
	if rule.Action == "reject" {
		value["action"] = "reject"
	} else {
		value["action"], value["outbound"] = "route", rule.Outbound
	}
	return value
}

var advancedTagPattern = regexp.MustCompile(`^[a-zA-Z0-9_-]{1,32}$`)
var advancedFieldPattern = regexp.MustCompile(`^[a-z_]{1,64}$`)

func advancedServerTag(server advancedServer, index int) string {
	if server.Tag != "" {
		return server.Tag
	}
	return "server-" + strconv.Itoa(index+1)
}

func (dns advancedDNS) tags() map[string]string {
	tags := map[string]string{"system": "local-dns", "default": ""}
	for index, server := range dns.Servers {
		tag := advancedServerTag(server, index)
		tags[tag] = "advanced-dns-" + tag
	}
	return tags
}

func (dns advancedDNS) validate(bootstrap string) error {
	if len(dns.Servers) > maxAdvancedServers || len(dns.Rules) > maxAdvancedRules {
		return invalidAdvanced("最多 8 个 DNS 服务器和 64 条 DNS 规则")
	}
	if dns.Strategy != "" && dns.Strategy != "prefer_ipv4" && dns.Strategy != "prefer_ipv6" && dns.Strategy != "ipv4_only" && dns.Strategy != "ipv6_only" {
		return invalidAdvanced("dns.strategy 应为 prefer_ipv4、prefer_ipv6、ipv4_only 或 ipv6_only")
	}
	if dns.CacheCapacity != nil && (*dns.CacheCapacity < 0 || *dns.CacheCapacity > maxAdvancedCacheEntries) {
		return invalidAdvanced("DNS 缓存容量应为 0–65536，0 使用核心默认值")
	}
	seen := map[string]bool{"system": true, "default": true}
	for index, server := range dns.Servers {
		tag := advancedServerTag(server, index)
		if !advancedTagPattern.MatchString(tag) || seen[tag] {
			return invalidAdvanced("DNS 标签应为 1–32 位字母、数字、下划线或连字符，不能重复或使用 system/default")
		}
		seen[tag] = true
		if server.Type == "local" {
			if server.Server != "" || server.ServerPort != 0 || server.Path != "" || server.TLS != nil {
				return invalidAdvanced("local DNS 不接受服务器、端口、路径或 TLS 设置")
			}
			continue
		}
		if server.Type != "udp" && server.Type != "tcp" && server.Type != "tls" && server.Type != "https" {
			return invalidAdvanced("DNS 类型支持 local、udp、tcp、tls 和 https")
		}
		if net.ParseIP(server.Server) == nil {
			if _, err := normalizeRouteValue("DOMAIN", server.Server); err != nil || net.ParseIP(bootstrap) == nil {
				return invalidAdvanced("DNS 服务器应为纯域名或 IP；域名服务器需要有效的引导 DNS")
			}
		}
		if server.ServerPort < 0 || server.ServerPort > 65535 {
			return invalidAdvanced("DNS server_port 应为 1–65535，省略或 0 使用协议默认值")
		}
		if server.Path != "" && (server.Type != "https" || len(server.Path) > 512 || !strings.HasPrefix(server.Path, "/") || strings.ContainsAny(server.Path, "?@#\\ \r\n\t\x00")) {
			return invalidAdvanced("仅 HTTPS DNS 支持 path，路径不包含认证、查询参数或片段")
		}
		if server.TLS != nil {
			if (server.Type != "https" && server.Type != "tls") || server.TLS.Enabled != nil && !*server.TLS.Enabled {
				return invalidAdvanced("TLS 仅用于 HTTPS/TLS DNS，且必须启用")
			}
			if server.TLS.ServerName != "" {
				if _, err := normalizeRouteValue("DOMAIN", server.TLS.ServerName); err != nil {
					return invalidAdvanced("TLS server_name 应为有效域名")
				}
			}
		}
	}
	tags := dns.tags()
	if dns.Final != "" {
		if _, ok := tags[dns.Final]; !ok {
			return invalidAdvanced("dns.final 引用了未定义的 DNS 标签")
		}
	}
	for _, rule := range dns.Rules {
		if err := rule.advancedDomainMatch.validate(); err != nil {
			return err
		}
		if !rule.hasConditions() {
			return invalidAdvanced("DNS 规则必须包含域名匹配条件")
		}
		if rule.Action == "reject" && rule.Server == "" {
			continue
		}
		if _, ok := tags[rule.Server]; !ok || rule.Action != "" && rule.Action != "route" {
			return invalidAdvanced("DNS 规则仅支持 route 到已定义标签，或不含 server 的 reject")
		}
	}
	return nil
}

func (patch advancedPatch) apply(config map[string]any, bootstrap string) {
	if patch.Log != nil {
		log := config["log"].(map[string]any)
		if patch.Log.Level != "" {
			log["level"] = patch.Log.Level
		}
		if patch.Log.Timestamp != nil {
			log["timestamp"] = *patch.Log.Timestamp
		}
	}
	if patch.Route != nil && len(patch.Route.Rules) > 0 {
		route := config["route"].(map[string]any)
		managed := route["rules"].([]any)
		// Direct/global modes retain priority. TUN DNS interception is prepended
		// after this merge. Advanced rules precede the regular rule-page entries.
		rules := append([]any{}, managed[:2]...)
		for _, rule := range patch.Route.Rules {
			rules = append(rules, rule.compile())
		}
		route["rules"] = append(rules, managed[2:]...)
	}
	if patch.DNS == nil {
		return
	}
	dns := config["dns"].(map[string]any)
	servers := dns["servers"].([]any)
	tags := patch.DNS.tags()
	tags["default"] = dns["final"].(string)
	if len(patch.DNS.Servers) > 0 {
		for _, server := range patch.DNS.Servers {
			if server.Type != "local" && net.ParseIP(server.Server) == nil {
				servers = append(servers, map[string]any{"type": "udp", "tag": "advanced-bootstrap", "server": bootstrap, "server_port": 53})
				break
			}
		}
		for index, server := range patch.DNS.Servers {
			tag := tags[advancedServerTag(server, index)]
			entry := map[string]any{"type": server.Type, "tag": tag}
			if server.Type != "local" {
				entry["server"] = server.Server
				if server.ServerPort > 0 {
					entry["server_port"] = server.ServerPort
				}
				if net.ParseIP(server.Server) == nil {
					entry["domain_resolver"] = map[string]any{"server": "advanced-bootstrap", "strategy": "ipv4_only"}
				}
				if server.Type == "https" || server.Type == "tls" {
					name := server.Server
					if server.TLS != nil && server.TLS.ServerName != "" {
						name = server.TLS.ServerName
					}
					entry["tls"] = map[string]any{"enabled": true, "server_name": name}
				}
				if server.Type == "https" {
					path := server.Path
					if path == "" {
						path = "/dns-query"
					}
					entry["path"] = path
				}
			}
			servers = append(servers, entry)
		}
		dns["final"] = tags[advancedServerTag(patch.DNS.Servers[0], 0)]
	}
	dns["servers"] = servers
	if patch.DNS.Final != "" {
		dns["final"] = tags[patch.DNS.Final]
	}
	if patch.DNS.Strategy != "" {
		dns["strategy"] = patch.DNS.Strategy
	}
	for key, value := range map[string]*bool{"disable_cache": patch.DNS.DisableCache, "disable_expire": patch.DNS.DisableExpire, "independent_cache": patch.DNS.IndependentCache} {
		if value != nil {
			dns[key] = *value
		}
	}
	if patch.DNS.CacheCapacity != nil {
		dns["cache_capacity"] = *patch.DNS.CacheCapacity
	}
	if len(patch.DNS.Rules) > 0 {
		rules := []any{}
		for _, rule := range patch.DNS.Rules {
			value := rule.advancedDomainMatch.compile()
			if rule.Action == "reject" {
				value["action"] = "reject"
			} else {
				value["action"], value["server"] = "route", tags[rule.Server]
			}
			rules = append(rules, value)
		}
		dns["rules"] = rules
	}
	config["route"].(map[string]any)["default_domain_resolver"] = dns["final"]
}

func applyAdvanced(config map[string]any, settings RuntimeSettings) error {
	patch, err := parseAdvanced(settings.Advanced, settings.BootstrapDNS)
	if err != nil {
		return err
	}
	patch.apply(config, settings.BootstrapDNS)
	return nil
}
