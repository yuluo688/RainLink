//go:build linux && !android

package linuxnet

import (
	"context"
	"errors"

	"golang.org/x/sys/unix"
)

// usableUpstream excludes network tunnels rather than all software links.
// A bridge, bond, VLAN or container veth can be the actual default uplink.
func usableUpstream(link Link) bool {
	if !link.Up() || link.Name == "" || link.Flags&unix.IFF_LOOPBACK != 0 {
		return false
	}
	switch link.Type {
	case unix.ARPHRD_LOOPBACK, unix.ARPHRD_TUNNEL, unix.ARPHRD_TUNNEL6, unix.ARPHRD_SIT, unix.ARPHRD_IPGRE, unix.ARPHRD_IP6GRE,
		unix.ARPHRD_NONE, unix.ARPHRD_VOID:
		return false
	}
	switch link.Kind {
	case "tun", "wireguard", "ipip", "sit", "gre", "gretap", "ip6gre", "ip6gretap", "ip6tnl",
		"vti", "vti6", "xfrm", "vxlan", "geneve", "erspan", "ip6erspan", "bareudp", "dummy", "nlmon":
		return false
	}
	return true
}

func plainNextHop(attributes []Attribute) bool {
	for _, attribute := range attributes {
		switch attribute.Type & attributeTypeMask {
		case unix.RTA_VIA, unix.RTA_ENCAP_TYPE, unix.RTA_ENCAP, unix.RTA_NEWDST:
			return false
		}
	}
	return true
}

func preferenceOrder(value uint8) int {
	// ICMPv6 router preferences: HIGH=1, MEDIUM=0, LOW=3.
	if value == 1 {
		return 0
	}
	if value == 3 {
		return 2
	}
	return 1
}

// SelectUpstream chooses a usable default IP route in the main routing table.
// Non-default and source-specific routes cannot stand in for an uplink. This
// deliberately does not guess a device from VRF/policy-only routing setups.
func SelectUpstream(links []Link, routes []Route, ipv6 bool) (string, error) {
	family := uint8(unix.AF_INET)
	if ipv6 {
		family = unix.AF_INET6
	}
	devices := make(map[uint32]Link, len(links))
	for _, link := range links {
		if _, found := devices[link.Index]; found {
			return "", ErrChanged
		}
		devices[link.Index] = link
	}
	var selected Link
	bestMetric := ^uint32(0)
	var selectedRoute bool
	bestPreference := 0
	var unsupportedMetric uint32
	var unsupported bool
	for _, route := range routes {
		if route.Family != family || route.Table != unix.RT_TABLE_MAIN || route.Type != unix.RTN_UNICAST ||
			!route.Destination.IsValid() || route.Destination.Bits() != 0 || !route.Source.IsValid() || route.Source.Bits() != 0 || route.TOS != 0 {
			continue
		}
		if route.NextHopID != 0 || !plainNextHop(route.Attributes) {
			if !unsupported || route.Priority < unsupportedMetric {
				unsupportedMetric, unsupported = route.Priority, true
			}
			continue
		}
		hops := route.NextHops
		if len(hops) == 0 {
			hops = []NextHop{{Interface: route.Interface}}
		}
		for _, hop := range hops {
			if hop.Flags&(unix.RTNH_F_DEAD|unix.RTNH_F_LINKDOWN|unix.RTNH_F_UNRESOLVED) != 0 {
				continue
			}
			if !plainNextHop(hop.Attributes) {
				if !unsupported || route.Priority < unsupportedMetric {
					unsupportedMetric, unsupported = route.Priority, true
				}
				continue
			}
			device, found := devices[hop.Interface]
			if !found || !usableUpstream(device) {
				continue
			}
			preference := preferenceOrder(route.Preference)
			if !selectedRoute || route.Priority < bestMetric || route.Priority == bestMetric &&
				(preference < bestPreference || preference == bestPreference && device.Index < selected.Index) {
				selected, bestMetric, selectedRoute = device, route.Priority, true
				bestPreference = preference
			}
		}
	}
	if unsupported && (!selectedRoute || unsupportedMetric <= bestMetric) {
		return "", errors.New("default route requires unsupported nexthop resolution")
	}
	if !selectedRoute {
		return "", errors.New("no active non-tunnel default route in main table")
	}
	return selected.Name, nil
}

// Upstream reads current links/routes and selects the requested IP family's
// uplink. This is a read-only operation and does not require root privileges.
func Upstream(ctx context.Context, ipv6 bool) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, readTimeout)
	defer cancel()
	links, err := Links(ctx)
	if err != nil {
		return "", err
	}
	routes, err := Routes(ctx)
	if err != nil {
		return "", err
	}
	if err = ctx.Err(); err != nil {
		return "", err
	}
	selected, err := SelectUpstream(links, routes, ipv6)
	if err != nil {
		return "", err
	}
	// Link and route dumps are separate kernel observations. Do not bind a
	// reused or renamed index if the selected device changed between them.
	latest, err := Links(ctx)
	if err != nil {
		return "", err
	}
	var original Link
	for _, link := range links {
		if link.Name == selected {
			original = link
			break
		}
	}
	for _, link := range latest {
		if link.Index == original.Index && link.Name == original.Name && link.Type == original.Type &&
			link.Kind == original.Kind && link.Master == original.Master && usableUpstream(link) {
			return selected, nil
		}
	}
	return "", ErrChanged
}
