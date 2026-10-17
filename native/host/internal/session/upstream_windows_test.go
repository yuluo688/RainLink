package session

import (
	"testing"

	"golang.org/x/sys/windows"
)

func TestSelectUpstreamInterface(t *testing.T) {
	route := func(index, metric uint32, ipv6 bool) windows.MibIpForwardRow2 {
		family := uint16(windows.AF_INET)
		if ipv6 {
			family = windows.AF_INET6
		}
		return windows.MibIpForwardRow2{InterfaceIndex: index, Metric: metric, ValidLifetime: ^uint32(0),
			DestinationPrefix: windows.IpAddressPrefix{Prefix: windows.RawSockaddrInet{Family: family}}}
	}
	adapters := map[uint32]upstreamAdapter{
		1: {name: "loopback", kind: windows.IF_TYPE_SOFTWARE_LOOPBACK, up: true},
		2: {name: "ethernet", kind: windows.IF_TYPE_ETHERNET_CSMACD, up: true, ipv4Metric: 40, ipv6Metric: 20},
		3: {name: "wireless", kind: windows.IF_TYPE_IEEE80211, up: true, ipv4Metric: 35},
		4: {name: "tun", kind: interfaceTypeVirtual, up: true},
		5: {name: "tunnel", kind: windows.IF_TYPE_TUNNEL, up: true},
		6: {name: "disconnected", kind: windows.IF_TYPE_ETHERNET_CSMACD},
		7: {name: "high-metric", kind: windows.IF_TYPE_ETHERNET_CSMACD, up: true, ipv4Metric: ^uint32(0) - 1},
	}
	routes := []windows.MibIpForwardRow2{route(1, 0, false), route(2, 0, false), route(3, 0, false),
		route(4, 0, false), route(5, 0, false), route(6, 0, false), route(7, 100, false), route(2, 0, true)}
	selected, err := selectUpstreamInterface(routes, adapters, false)
	if err != nil || selected != "wireless" {
		t.Fatalf("TUN/default route metrics did not select the uplink: %q %v", selected, err)
	}
	selected, err = selectUpstreamInterface(routes, adapters, true)
	if err != nil || selected != "ethernet" {
		t.Fatalf("IPv6 used an IPv4-only interface: %q %v", selected, err)
	}
	tie := route(2, 0, false)
	routes[2].Metric = 5 // Both have total metric 40: stable tie by index.
	selected, err = selectUpstreamInterface([]windows.MibIpForwardRow2{routes[2], tie}, adapters, false)
	if err != nil || selected != "ethernet" {
		t.Fatal("equal metric selection depends on enumeration order")
	}
	nonDefault := route(3, 0, false)
	nonDefault.DestinationPrefix.PrefixLength = 1
	expired := route(2, 0, false)
	expired.ValidLifetime = 0
	for _, unusable := range [][]windows.MibIpForwardRow2{
		{routes[0], routes[3], routes[4], routes[5]},
		{nonDefault, expired},
		nil,
	} {
		if _, err = selectUpstreamInterface(unusable, adapters, false); err == nil {
			t.Fatal("missing uplink falsely reported as usable")
		}
	}
}
