package session

import (
	"context"
	"net"
	"net/netip"
	"runtime"
	"time"
)

const (
	upstreamDNSTag        = "upstream-dns"
	upstreamDNSServer     = "223.5.5.5"
	upstreamDNSServerName = "dns.alidns.com"
	upstreamLookupTimeout = 3 * time.Second
)

var fakeIPRange = netip.MustParsePrefix("198.18.0.0/15")

// Only the proxy's upstream uses this policy. Local destinations and the direct
// outbound retain the system's routes and DNS; no global network settings change.
type upstreamNetwork struct {
	InterfaceName string
	EncryptedDNS  bool
}

func localUpstream(address netip.Addr) bool {
	address = address.Unmap()
	return address.IsPrivate() || address.IsLoopback() || address.IsLinkLocalUnicast()
}

func upstreamAddressPolicy(addresses []netip.Addr) (local, fake, ipv6 bool) {
	local = len(addresses) > 0
	ipv6 = len(addresses) > 0
	for _, address := range addresses {
		address = address.Unmap()
		local = local && localUpstream(address)
		fake = fake || fakeIPRange.Contains(address)
		ipv6 = ipv6 && address.Is6()
	}
	return
}

func prepareUpstream(ctx context.Context, node Node) (upstreamNetwork, error) {
	if !node.usesQUIC() || runtime.GOOS != "windows" {
		return upstreamNetwork{}, nil
	}
	if err := ctx.Err(); err != nil {
		return upstreamNetwork{}, fail("cancelled", "连接已取消")
	}
	address, parseErr := netip.ParseAddr(node.Server)
	var addresses []netip.Addr
	if parseErr == nil {
		address = address.Unmap()
		if fakeIPRange.Contains(address) {
			return upstreamNetwork{}, fail("invalid_server_address", "节点地址是临时 Fake-IP，请使用原始域名或真实 IP")
		}
		addresses = []netip.Addr{address}
	} else {
		lookupCtx, cancel := context.WithTimeout(ctx, upstreamLookupTimeout)
		defer cancel()
		var err error
		addresses, err = net.DefaultResolver.LookupNetIP(lookupCtx, "ip", node.Server)
		if ctx.Err() != nil {
			return upstreamNetwork{}, fail("cancelled", "连接已取消")
		}
		if err != nil || len(addresses) == 0 {
			return upstreamNetwork{}, fail("upstream_dns_failed", "无法解析节点服务器，请检查网络或服务器地址")
		}
	}
	local, fake, ipv6 := upstreamAddressPolicy(addresses)
	if local && !fake {
		return upstreamNetwork{}, nil
	}
	interfaceName, err := defaultUpstreamInterface(ctx, ipv6)
	if err != nil {
		return upstreamNetwork{}, fail("upstream_network_unavailable", "未找到可用的上游网络，请检查网络连接后重试")
	}
	if err := ctx.Err(); err != nil {
		return upstreamNetwork{}, fail("cancelled", "连接已取消")
	}
	return upstreamNetwork{InterfaceName: interfaceName, EncryptedDNS: fake}, nil
}
