package session

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/netip"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"unicode/utf8"
)

const maxRouteRules = 256
const maxRouteTargets = 32

// RouteRule is an ordered rule. Only MATCH may omit its value.
type RouteRule struct {
	ID      string `json:"id"`
	Type    string `json:"type"`
	Value   string `json:"value"`
	Target  string `json:"target"`
	Enabled bool   `json:"enabled"`
}

// RoutingOutbound freezes a referenced group's or node's actual upstream.
type RoutingOutbound struct {
	Key   string         `json:"key"`
	Name  string         `json:"name"`
	Node  Node           `json:"node"`
	Chain *ChainSnapshot `json:"chain,omitempty"`
}

// RoutingPlan is validated and compiled before any system state is changed.
type RoutingPlan struct {
	Revision  int               `json:"revision"`
	Rules     []RouteRule       `json:"rules"`
	Outbounds []RoutingOutbound `json:"outbounds"`
}

// RouteBinding exposes only the applied target's public identity and revision.
type RouteBinding struct {
	ID       string `json:"id"`
	Revision int    `json:"revision"`
}

type preparedOutbound struct {
	RoutingOutbound
	auth    credentials
	network upstreamNetwork
	hops    []preparedHop
}

var routeIDPattern = regexp.MustCompile(`^[a-zA-Z0-9_-]{1,128}$`)
var domainLabelPattern = regexp.MustCompile(`^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$`)

func validRouteTarget(target string) bool {
	if target == "proxy" || target == "direct" || target == "reject" {
		return true
	}
	kind, id, found := strings.Cut(target, ":")
	return found && (kind == "node" || kind == "group" || kind == "chain") && routeIDPattern.MatchString(id)
}

func normalizeRouteValue(kind, input string) (string, error) {
	value := strings.ToLower(strings.TrimSpace(input))
	switch kind {
	case "MATCH":
		if value != "" {
			return "", errors.New("兜底规则不需要匹配条件")
		}
		return "", nil
	case "IP-CIDR":
		prefix, err := netip.ParsePrefix(value)
		if err != nil {
			return "", errors.New("IP 网段格式无效")
		}
		return prefix.Masked().String(), nil
	case "DOMAIN", "DOMAIN-SUFFIX":
		value = strings.TrimSuffix(value, ".")
		if value == "" || len(value) > 253 {
			return "", errors.New("域名格式无效")
		}
		if _, err := netip.ParseAddr(value); err == nil {
			return "", errors.New("域名规则不能填写 IP 地址")
		}
		for _, label := range strings.Split(value, ".") {
			if !domainLabelPattern.MatchString(label) {
				return "", errors.New("请输入域名，不含协议、路径或通配符")
			}
		}
		return value, nil
	default:
		return "", errors.New("规则类型无效")
	}
}

func (plan *RoutingPlan) validate(requireNodes bool) error {
	if plan == nil {
		return nil
	}
	if plan.Revision < 0 || len(plan.Rules) < 1 || len(plan.Rules) > maxRouteRules || len(plan.Outbounds) > maxRouteTargets {
		return fail("invalid_rules", "规则或出站数量超出限制")
	}
	ids, refs := map[string]bool{}, map[string]bool{}
	matchCount := 0
	for index := range plan.Rules {
		rule := &plan.Rules[index]
		if !routeIDPattern.MatchString(rule.ID) || ids[rule.ID] || !validRouteTarget(rule.Target) {
			return fail("invalid_rules", "规则标识重复或出站目标无效")
		}
		ids[rule.ID] = true
		value, err := normalizeRouteValue(rule.Type, rule.Value)
		if err != nil {
			return fail("invalid_rules", err.Error())
		}
		rule.Value = value
		if rule.Type == "MATCH" {
			matchCount++
			if index != len(plan.Rules)-1 || !rule.Enabled {
				return fail("invalid_rules", "兜底规则须启用并位于最后")
			}
		}
		if rule.Enabled && strings.Contains(rule.Target, ":") {
			refs[rule.Target] = true
		}
	}
	if matchCount != 1 || len(refs) > maxRouteTargets {
		return fail("invalid_rules", "须保留唯一兜底规则，独立出站最多 32 个")
	}
	if !requireNodes {
		return nil
	}
	seen := map[string]bool{}
	for _, target := range plan.Outbounds {
		if !refs[target.Key] || seen[target.Key] || strings.TrimSpace(target.Name) == "" || !utf8.ValidString(target.Name) || utf8.RuneCountInString(target.Name) > 128 {
			return fail("invalid_rules", "规则出站重复或无效")
		}
		if target.Chain != nil {
			if target.Node.ID != "" || target.Key != "chain:"+target.Chain.ID {
				return fail("invalid_rules", "规则代理链标识不匹配")
			}
			if err := target.Chain.validate(); err != nil {
				return err
			}
		} else if strings.HasPrefix(target.Key, "chain:") || target.Node.validate() != nil {
			return fail("invalid_rules", "规则引用的节点或代理链参数无效")
		}
		if strings.HasPrefix(target.Key, "node:") && strings.TrimPrefix(target.Key, "node:") != target.Node.ID {
			return fail("invalid_rules", "规则节点标识不匹配")
		}
		seen[target.Key] = true
	}
	if len(seen) != len(refs) {
		return fail("invalid_rules", "规则出站节点缺失，请检查分组和节点")
	}
	return nil
}

func compileRouteRules(plan *RoutingPlan, tags map[string]string) ([]any, error) {
	rules := []any{
		map[string]any{"clash_mode": "direct", "action": "route", "outbound": "direct"},
		map[string]any{"clash_mode": "global", "action": "route", "outbound": "proxy"},
	}
	if plan == nil {
		return append(rules, map[string]any{"ip_is_private": true, "action": "route", "outbound": "direct"},
			map[string]any{"clash_mode": "rule", "action": "route", "outbound": "proxy"}), nil
	}
	for _, rule := range plan.Rules {
		if !rule.Enabled {
			continue
		}
		entry := map[string]any{}
		switch rule.Type {
		case "DOMAIN":
			entry["domain"] = []string{rule.Value}
		case "DOMAIN-SUFFIX":
			entry["domain_suffix"] = []string{rule.Value}
		case "IP-CIDR":
			entry["ip_cidr"] = []string{rule.Value}
		case "MATCH":
			entry["clash_mode"] = "rule"
		default:
			return nil, fail("invalid_rules", "规则类型无效")
		}
		if rule.Target == "reject" {
			entry["action"] = "reject"
		} else {
			tag := rule.Target
			if strings.Contains(tag, ":") {
				tag = tags[tag]
			}
			if tag == "" {
				return nil, fail("invalid_rules", "规则出站未解析")
			}
			entry["action"], entry["outbound"] = "route", tag
		}
		rules = append(rules, entry)
	}
	return rules, nil
}

func readNodeCredentials(ctx context.Context, node Node) (credentials, error) {
	var auth credentials
	if err := ctx.Err(); err != nil {
		return auth, credentialFailure(err, "credential_unavailable", "无法读取节点凭据")
	}
	if node.Credential == "" {
		return auth, nil
	}
	plain, err := unseal(ctx, node.Credential, node.ID)
	if err != nil {
		return auth, credentialFailure(err, "credential_unavailable", "无法读取节点凭据，请重新编辑节点")
	}
	defer clear(plain)
	if err = json.Unmarshal(plain, &auth); err != nil {
		return auth, fail("credential_unavailable", "节点凭据格式无效")
	}
	return auth, nil
}

// ValidateRules checks the controlled rule compiler with the bundled core,
// without replacing the active session or opening a listener.
func (m *Manager) ValidateRules(ctx context.Context, plan RoutingPlan) error {
	if err := plan.validate(false); err != nil {
		return err
	}
	tags := map[string]string{}
	for _, rule := range plan.Rules {
		if rule.Enabled && strings.Contains(rule.Target, ":") && tags[rule.Target] == "" {
			tags[rule.Target] = "check-" + strconv.Itoa(len(tags))
		}
	}
	rules, err := compileRouteRules(&plan, tags)
	if err != nil {
		return err
	}
	outbounds := []any{map[string]any{"type": "direct", "tag": "proxy"}, map[string]any{"type": "direct", "tag": "direct"}}
	for _, tag := range tags {
		outbounds = append(outbounds, map[string]any{"type": "direct", "tag": tag})
	}
	config, err := json.Marshal(map[string]any{"route": map[string]any{"rules": rules, "final": "proxy"}, "outbounds": outbounds})
	if err != nil {
		return fail("invalid_rules", "规则配置无法编译")
	}
	check := exec.CommandContext(ctx, m.corePath, "check", "-c", "stdin")
	hideWindow(check)
	check.Stdin = bytes.NewReader(config)
	if err = check.Run(); err != nil {
		return fail("rules_rejected", "核心未通过规则校验，原规则已保留")
	}
	return nil
}
