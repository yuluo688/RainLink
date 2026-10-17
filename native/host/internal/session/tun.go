package session

import (
	"context"
	"encoding/json"
	"net"
	"net/netip"
	"runtime"
	"strings"
	"time"

	"rainlink.local/host/internal/tunconfig"
)

const tunInterfacePrefix = "RainLink-"

type tunPlan struct {
	Name     string
	Upstream string
}

// configureTUN extends the controlled compiler. No raw inbound, route or
// interface settings are accepted from the UI or a subscription.
func configureTUN(config []byte, plan tunPlan) ([]byte, error) {
	var value map[string]any
	if err := json.Unmarshal(config, &value); err != nil {
		return nil, err
	}
	addresses := []string{tunconfig.IPv4Address}
	// Capture both families even with IPv6 DNS disabled. Otherwise applications
	// using literal IPv6 addresses could silently bypass the selected route.
	addresses = append(addresses, tunconfig.IPv6Address)
	inbound := map[string]any{
		"type": "tun", "tag": "rainlink-tun", "interface_name": plan.Name,
		"address": addresses, "mtu": 1500, "stack": "system",
		"auto_route": true, "strict_route": true,
	}
	inbounds := value["inbounds"].([]any)
	value["inbounds"] = append(inbounds, inbound)
	route := value["route"].(map[string]any)
	route["default_interface"] = plan.Upstream
	// DNS interception must precede global/direct mode and user rules. Explicit
	// DNS packets entering TUN are resolved by the configured DNS policy.
	rules := route["rules"].([]any)
	route["rules"] = append([]any{
		map[string]any{"inbound": []string{"rainlink-tun"}, "port": []int{53}, "action": "hijack-dns"},
	}, rules...)
	// All resolver sockets bypass our virtual interface as well as proxy entry
	// sockets; later detour hops still use their previous hop.
	dns := value["dns"].(map[string]any)
	for _, raw := range dns["servers"].([]any) {
		server := raw.(map[string]any)
		if server["type"] != "local" {
			server["bind_interface"] = plan.Upstream
		}
	}
	for _, raw := range value["outbounds"].([]any) {
		outbound := raw.(map[string]any)
		if _, detoured := outbound["detour"]; !detoured {
			if _, alreadyBound := outbound["bind_interface"]; !alreadyBound {
				outbound["bind_interface"] = plan.Upstream
			}
		}
	}
	return json.Marshal(value)
}

func newTUNPlan(ctx context.Context) (tunPlan, error) {
	if ctx.Err() != nil {
		return tunPlan{}, fail("cancelled", "连接已取消")
	}
	upstream, err := defaultUpstreamInterface(ctx, false)
	if err != nil {
		if ctx.Err() != nil {
			return tunPlan{}, fail("cancelled", "连接已取消")
		}
		upstream, err = defaultUpstreamInterface(ctx, true)
	}
	if err != nil {
		return tunPlan{}, fail("tun_upstream_unavailable", "未找到可用的上游网络，请检查网络连接后重试")
	}
	interfaces, err := net.Interfaces()
	if err != nil {
		return tunPlan{}, fail("tun_network_unavailable", "无法读取网络接口，请重试")
	}
	addresses := []netip.Prefix{netip.MustParsePrefix(tunconfig.IPv4Address).Masked(), netip.MustParsePrefix(tunconfig.IPv6Address).Masked()}
	for _, device := range interfaces {
		if ctx.Err() != nil {
			return tunPlan{}, fail("cancelled", "连接已取消")
		}
		if device.Flags&net.FlagUp == 0 {
			continue
		}
		entries, addressErr := device.Addrs()
		if addressErr != nil {
			return tunPlan{}, fail("tun_network_unavailable", "无法读取网络接口地址，请重试")
		}
		for _, entry := range entries {
			prefix, parseErr := netip.ParsePrefix(entry.String())
			if parseErr != nil {
				continue
			}
			for _, reserved := range addresses {
				if prefix.Overlaps(reserved) {
					return tunPlan{}, fail("tun_address_conflict", "TUN 地址与现有网络重叠，请先断开其他 TUN 连接")
				}
			}
		}
	}
	if ctx.Err() != nil {
		return tunPlan{}, fail("cancelled", "连接已取消")
	}
	return tunPlan{Name: newTUNInterfaceName(), Upstream: upstream}, nil
}

func newTUNInterfaceName() string {
	prefix := tunInterfacePrefix
	if runtime.GOOS == "linux" {
		// Linux IFNAMSIZ includes the trailing NUL (15 visible bytes maximum).
		// The lease allocator accepts lowercase names; rand.Text uses uppercase
		// base32, so normalize before asking it to reserve the device.
		return "rl-" + strings.ToLower(randomID()[:8])
	}
	return prefix + randomID()[:8]
}

func (m *Manager) cleanupTUNLocked() error {
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Second)
	defer cancel()
	return m.cleanupTUNContextLocked(ctx)
}

func (m *Manager) cleanupTUNContextLocked(ctx context.Context) error {
	if m.pendingManaged != nil {
		if err := m.pendingManaged.stop(ctx); err != nil {
			m.lastError = "TUN 网络恢复尚未确认，请重试断开"
			return err
		}
		m.pendingManaged.close()
		m.pendingManaged = nil
		m.lastError = ""
	}
	if m.pendingTUN == "" {
		return nil
	}
	if err := waitTUN(ctx, m.pendingTUN, false); err != nil {
		m.lastError = "TUN 网卡尚未清理完成，请重试断开"
		return fail("tun_restore_failed", m.lastError)
	}
	m.pendingTUN = ""
	return nil
}
