package session

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

const maxChainHops = 5
const chainProbeEndpoint = "https://www.gstatic.com/generate_204"

// ChainSnapshot contains ordered, immutable upstream snapshots.
type ChainSnapshot struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Revision int    `json:"revision"`
	Hops     []Node `json:"hops"`
}

// Target identifies the actual primary node or proxy chain in a live session.
type Target struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Revision int    `json:"revision"`
	Kind     string `json:"kind"`
}

type preparedHop struct {
	node    Node
	auth    credentials
	network upstreamNetwork
}

func (chain ChainSnapshot) validate() error {
	if !routeIDPattern.MatchString(chain.ID) || strings.TrimSpace(chain.Name) == "" ||
		!utf8.ValidString(chain.Name) || utf8.RuneCountInString(chain.Name) > 64 || chain.Revision < 1 ||
		len(chain.Hops) < 2 || len(chain.Hops) > maxChainHops {
		return fail("invalid_chain", "代理链名称或跳点无效，须包含 2–5 个节点")
	}
	seen := map[string]bool{}
	tcpOnly := false
	for index, node := range chain.Hops {
		if !routeIDPattern.MatchString(node.ID) {
			return fail("invalid_chain", "跳点标识无效")
		}
		if err := node.validate(); err != nil {
			return fail("invalid_chain", fmt.Sprintf("第 %d 跳节点参数无效", index+1))
		}
		if seen[node.ID] {
			return fail("invalid_chain", "同一节点不能在链中重复使用")
		}
		seen[node.ID] = true
		if tcpOnly && node.usesQUIC() {
			return fail("incompatible_chain", fmt.Sprintf("第 %d 跳需要 UDP，前面的 HTTP 节点仅支持 TCP", index+1))
		}
		tcpOnly = tcpOnly || node.Protocol == "http"
	}
	return nil
}

func chainFingerprint(chain ChainSnapshot) string {
	parts := make([]string, 0, len(chain.Hops))
	for _, node := range chain.Hops {
		parts = append(parts, node.ID+":"+strconv.Itoa(node.Revision))
	}
	digest := sha256.Sum256([]byte(strings.Join(parts, "|")))
	return hex.EncodeToString(digest[:])
}

func prepareTarget(ctx context.Context, target RoutingOutbound) (preparedOutbound, error) {
	prepared := preparedOutbound{RoutingOutbound: target}
	nodes := []Node{target.Node}
	if target.Chain != nil {
		nodes = target.Chain.Hops
	}
	for index, node := range nodes {
		auth, err := readNodeCredentials(ctx, node)
		if err != nil {
			return prepared, err
		}
		var network upstreamNetwork
		// Later hops must dial through the previous hop, never bind the physical
		// interface or use the direct bootstrap resolver of the chain's entry.
		if index == 0 {
			network, err = prepareUpstream(ctx, node)
			if err != nil {
				return prepared, err
			}
		}
		prepared.hops = append(prepared.hops, preparedHop{node: node, auth: auth, network: network})
	}
	return prepared, nil
}

func (target preparedOutbound) credentialsForLogs() []string {
	var secrets []string
	for _, hop := range target.allHops() {
		secrets = append(secrets, hop.auth.Username, hop.auth.Password, hop.auth.ObfsPassword)
	}
	return secrets
}

func (target preparedOutbound) allHops() []preparedHop {
	if len(target.hops) > 0 {
		return target.hops
	}
	return []preparedHop{{node: target.Node, auth: target.auth, network: target.network}}
}

func (target RoutingOutbound) bindings(key string, bindings map[string]RouteBinding) {
	if target.Chain == nil {
		bindings[key] = RouteBinding{ID: target.Node.ID, Revision: target.Node.Revision}
		return
	}
	if key != "proxy" {
		bindings[key] = RouteBinding{ID: target.Chain.ID, Revision: target.Chain.Revision}
	}
	for index, node := range target.Chain.Hops {
		bindings[key+"/hop/"+strconv.Itoa(index)] = RouteBinding{ID: node.ID, Revision: node.Revision}
	}
}

// ChainHopTest is an actual HTTPS test through a prefix of the chain. A failed
// prefix identifies a failing segment, not a proof that one server caused it.
type ChainHopTest struct {
	Hop     int    `json:"hop"`
	Latency int64  `json:"latency"`
	Passed  bool   `json:"passed"`
	Error   string `json:"error"`
}

// ChainTestResult never contains credentials, remote URLs or raw core errors.
type ChainTestResult struct {
	Fingerprint string         `json:"fingerprint"`
	CheckedAt   int64          `json:"checkedAt"`
	Passed      bool           `json:"passed"`
	Hops        []ChainHopTest `json:"hops"`
}

// TestChain uses isolated child cores with capture disabled. The calling
// manager must itself belong to serve-test's separate runtime directory.
func (m *Manager) TestChain(ctx context.Context, chain ChainSnapshot) (ChainTestResult, error) {
	if !m.isolated {
		return ChainTestResult{}, fail("isolated_probe", "请使用独立测试宿主")
	}
	return m.testChain(ctx, chain, chainProbeEndpoint)
}

// ValidateChain asks the bundled core to validate every hop without opening listeners.
func (m *Manager) ValidateChain(ctx context.Context, chain ChainSnapshot) error {
	if err := chain.validate(); err != nil {
		return err
	}
	prepared := preparedOutbound{RoutingOutbound: RoutingOutbound{Chain: &chain}}
	for _, node := range chain.Hops {
		auth, err := readNodeCredentials(ctx, node)
		if err != nil {
			return err
		}
		prepared.hops = append(prepared.hops, preparedHop{node: node, auth: auth})
	}
	config, err := targetConfiguration(prepared, "global", 0, 0, "check", nil, nil)
	if err != nil {
		return fail("invalid_chain", "节点协议凭据无效，请检查各跳节点")
	}
	check := exec.CommandContext(ctx, m.corePath, "check", "-c", "stdin")
	hideWindow(check)
	check.Stdin = bytes.NewReader(config)
	if err = check.Run(); err != nil {
		return fail("chain_rejected", "核心未通过链路校验，请检查各跳协议与传输参数")
	}
	return nil
}

func (m *Manager) testChain(ctx context.Context, chain ChainSnapshot, endpoint string) (ChainTestResult, error) {
	result := ChainTestResult{Fingerprint: chainFingerprint(chain), CheckedAt: time.Now().UnixMilli(), Hops: []ChainHopTest{}}
	if err := chain.validate(); err != nil {
		return result, err
	}
	for index := range chain.Hops {
		if ctx.Err() != nil {
			return result, fail("cancelled", "链路测试已取消")
		}
		var node Node
		var prefix *ChainSnapshot
		if index == 0 {
			node = chain.Hops[0]
		} else {
			current := chain
			current.Hops = chain.Hops[:index+1]
			prefix = &current
		}
		measurement, err := m.probePath(ctx, node, prefix, endpoint)
		if err != nil {
			return result, err
		}
		entry := ChainHopTest{Hop: index + 1, Latency: measurement.latency, Passed: measurement.passed}
		if !entry.Passed {
			entry.Error = fmt.Sprintf("到第 %d 跳的测试未通过；请检查该段认证、网络和目标可达性", index+1)
			result.Hops = append(result.Hops, entry)
			return result, nil
		}
		result.Hops = append(result.Hops, entry)
	}
	result.Passed = true
	return result, nil
}
