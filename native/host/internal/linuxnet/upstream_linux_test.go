//go:build linux && !android

package linuxnet

import (
	"net/netip"
	"testing"

	"golang.org/x/sys/unix"
)

func defaultRoute(index, metric uint32, ipv6 bool) Route {
	family := uint8(unix.AF_INET)
	prefix := netip.MustParsePrefix("0.0.0.0/0")
	if ipv6 {
		family, prefix = unix.AF_INET6, netip.MustParsePrefix("::/0")
	}
	return Route{Family: family, Destination: prefix, Source: prefix, Table: unix.RT_TABLE_MAIN,
		Type: unix.RTN_UNICAST, Interface: index, Priority: metric}
}

func TestSelectUpstreamUsesFamilyMetricAndStableTie(t *testing.T) {
	links := []Link{
		{Index: 1, Name: "eth0", Flags: unix.IFF_UP, Type: unix.ARPHRD_ETHER},
		{Index: 2, Name: "wlan0", Flags: unix.IFF_UP, Type: unix.ARPHRD_ETHER},
	}
	routes := []Route{defaultRoute(1, 40, false), defaultRoute(2, 35, false), defaultRoute(1, 20, true)}
	if name, err := SelectUpstream(links, routes, false); err != nil || name != "wlan0" {
		t.Fatal("wrong IPv4 uplink", name, err)
	}
	if name, err := SelectUpstream(links, routes, true); err != nil || name != "eth0" {
		t.Fatal("IPv6 selected an IPv4-only route", name, err)
	}
	routes[1].Priority = 40
	if name, err := SelectUpstream(links, []Route{routes[1], routes[0]}, false); err != nil || name != "eth0" {
		t.Fatal("equal metrics depend on dump order", name, err)
	}
	routes[0].Priority = ^uint32(0)
	if name, err := SelectUpstream(links, routes[:1], false); err != nil || name != "eth0" {
		t.Fatal("valid maximum metric rejected or overflowed", name, err)
	}
	if _, err := SelectUpstream(append(links, links[0]), routes, false); err == nil {
		t.Fatal("duplicate interface identity accepted")
	}
}

func TestSelectUpstreamExcludesTunnelsAndUnavailableDevices(t *testing.T) {
	physical := Link{Index: 100, Name: "real0", Flags: unix.IFF_UP, Type: unix.ARPHRD_ETHER, OperState: operUp}
	for _, device := range []Link{
		{Name: "lo", Flags: unix.IFF_UP | unix.IFF_LOOPBACK},
		{Name: "loop", Flags: unix.IFF_UP, Type: unix.ARPHRD_LOOPBACK},
		{Name: "down", Flags: 0, Type: unix.ARPHRD_ETHER},
		{Name: "no-carrier", Flags: unix.IFF_UP, Type: unix.ARPHRD_ETHER, OperState: operDown},
		{Name: "tun0", Flags: unix.IFF_UP, Kind: "tun"},
		{Name: "wg0", Flags: unix.IFF_UP, Kind: "wireguard"},
		{Name: "sit0", Flags: unix.IFF_UP, Type: unix.ARPHRD_SIT},
		{Name: "gre0", Flags: unix.IFF_UP, Type: unix.ARPHRD_IPGRE},
		{Name: "vx0", Flags: unix.IFF_UP, Kind: "vxlan"},
		{Name: "dummy0", Flags: unix.IFF_UP, Kind: "dummy"},
	} {
		t.Run(device.Name, func(t *testing.T) {
			device.Index = 1
			links := []Link{device, physical}
			routes := []Route{defaultRoute(1, 0, false), defaultRoute(100, 100, false)}
			if name, err := SelectUpstream(links, routes, false); err != nil || name != "real0" {
				t.Fatal("tunnel/down interface captured upstream", name, err)
			}
			if _, err := SelectUpstream(links[:1], routes[:1], false); err == nil {
				t.Fatal("missing uplink reported as usable")
			}
		})
	}
	for _, kind := range []string{"bridge", "bond", "vlan", "veth", "ppp"} {
		physical.Kind = kind
		if name, err := SelectUpstream([]Link{physical}, []Route{defaultRoute(100, 0, false)}, false); err != nil || name != "real0" {
			t.Fatal("a valid software uplink was excluded", kind, name, err)
		}
	}
}

func TestSelectUpstreamRequiresMainTableUnicastDefault(t *testing.T) {
	link := Link{Index: 1, Name: "eth0", Flags: unix.IFF_UP}
	base := defaultRoute(1, 0, false)
	for _, mutate := range []func(*Route){
		func(r *Route) { r.Table = 100001 },
		func(r *Route) { r.Type = unix.RTN_UNREACHABLE },
		func(r *Route) { r.Destination = netip.MustParsePrefix("0.0.0.0/1") },
		func(r *Route) { r.Source = netip.MustParsePrefix("192.0.2.0/24") },
		func(r *Route) { r.TOS = 4 },
		func(r *Route) { r.Interface = 2 },
	} {
		route := base
		mutate(&route)
		if _, err := SelectUpstream([]Link{link}, []Route{route}, false); err == nil {
			t.Fatal("unusable default route accepted", route)
		}
	}
	if _, err := SelectUpstream(nil, nil, false); err == nil {
		t.Fatal("empty route table reported as usable")
	}
}

func TestSelectUpstreamMultipathSkipsDeadAndUnresolvedHops(t *testing.T) {
	links := []Link{{Index: 1, Name: "eth0", Flags: unix.IFF_UP}, {Index: 2, Name: "eth1", Flags: unix.IFF_UP}}
	route := defaultRoute(0, 100, false)
	for _, flags := range []uint8{unix.RTNH_F_DEAD, unix.RTNH_F_LINKDOWN, unix.RTNH_F_UNRESOLVED} {
		route.NextHops = []NextHop{{Interface: 1, Flags: flags}, {Interface: 2}}
		if name, err := SelectUpstream(links, []Route{route}, false); err != nil || name != "eth1" {
			t.Fatal("dead nexthop selected", name, err)
		}
	}
	route.NextHops = []NextHop{{Interface: 2}, {Interface: 1}}
	if name, err := SelectUpstream(links, []Route{route}, false); err != nil || name != "eth0" {
		t.Fatal("ECMP tie is not stable", name, err)
	}
}

func TestSelectUpstreamDoesNotGuessUnsupportedDefaultNexthops(t *testing.T) {
	link := Link{Index: 1, Name: "eth0", Flags: unix.IFF_UP}
	good := defaultRoute(1, 40, false)
	for _, route := range []Route{
		{Family: good.Family, Destination: good.Destination, Source: good.Source, Table: good.Table, Type: good.Type, NextHopID: 1},
		{Family: good.Family, Destination: good.Destination, Source: good.Source, Table: good.Table, Type: good.Type,
			Interface: 1, Attributes: []Attribute{{Type: unix.RTA_ENCAP}}},
	} {
		if _, err := SelectUpstream([]Link{link}, []Route{route, good}, false); err == nil {
			t.Fatal("unsupported preferred route silently replaced")
		}
		route.Priority = 41
		if name, err := SelectUpstream([]Link{link}, []Route{route, good}, false); err != nil || name != "eth0" {
			t.Fatal("lower-priority unsupported route hid an ordinary default", name, err)
		}
	}
}

func TestSelectUpstreamHonorsIPv6RouterPreferenceAtEqualMetric(t *testing.T) {
	links := []Link{{Index: 1, Name: "eth0", Flags: unix.IFF_UP}, {Index: 2, Name: "eth1", Flags: unix.IFF_UP}}
	first, second := defaultRoute(1, 40, true), defaultRoute(2, 40, true)
	first.Preference, second.Preference = 3, 1
	if name, err := SelectUpstream(links, []Route{first, second}, true); err != nil || name != "eth1" {
		t.Fatal("high-preference IPv6 router lost to interface index", name, err)
	}
	first.Priority = 39
	if name, err := SelectUpstream(links, []Route{first, second}, true); err != nil || name != "eth0" {
		t.Fatal("router preference overrode the route metric", name, err)
	}
}
