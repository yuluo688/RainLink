//go:build linux && !android

package linuxnet

import (
	"encoding/binary"
	"net/netip"
	"reflect"
	"strings"
	"testing"

	"golang.org/x/sys/unix"
)

func linkMessage(index uint32, name, kind string) []byte {
	data := make([]byte, unix.SizeofIfInfomsg)
	binary.NativeEndian.PutUint16(data[2:], unix.ARPHRD_ETHER)
	binary.NativeEndian.PutUint32(data[4:], index)
	binary.NativeEndian.PutUint32(data[8:], unix.IFF_UP|unix.IFF_RUNNING)
	data = append(data, wireAttribute(unix.IFLA_IFNAME, append([]byte(name), 0))...)
	data = append(data, wireAttribute(unix.IFLA_OPERSTATE, []byte{operUp})...)
	if kind != "" {
		info := wireAttribute(unix.IFLA_INFO_KIND, append([]byte(kind), 0))
		data = append(data, wireAttribute(unix.IFLA_LINKINFO|unix.NLA_F_NESTED, info)...)
	}
	return data
}

func routeMessage(family byte, table uint32) []byte {
	data := make([]byte, networkHeaderSize)
	data[0], data[4], data[5], data[6], data[7] = family, unix.RT_TABLE_MAIN, unix.RTPROT_STATIC, unix.RT_SCOPE_UNIVERSE, unix.RTN_UNICAST
	data = append(data, wireAttribute(unix.RTA_TABLE, wireInteger(table))...)
	return data
}

func TestLinkReadsKernelKindAndOperationalState(t *testing.T) {
	data := linkMessage(7, "rl-12345678", "tun")
	link, err := parseLink(data)
	if err != nil || link.Index != 7 || link.Name != "rl-12345678" || link.Kind != "tun" || !link.Up() {
		t.Fatal("kernel TUN identity not preserved", link, err)
	}
	for _, state := range []uint8{operNotPresent, operDown, operLowerLayerDown, operTesting, operDormant, 255} {
		link.OperState = state
		if link.Up() {
			t.Fatal("unavailable interface reported as up", state)
		}
	}
	link.OperState = 0
	if !link.Up() {
		t.Fatal("unknown operational state rejected for an administratively up TUN")
	}
	link.Flags = 0
	if link.Up() {
		t.Fatal("administratively down interface reported as up")
	}
}

func TestLinkRejectsAmbiguousOrInvalidIdentity(t *testing.T) {
	for _, invalid := range [][]byte{
		nil, make([]byte, unix.SizeofIfInfomsg), linkMessage(0, "eth0", ""),
		linkMessage(0xffffffff, "eth0", ""), linkMessage(1, strings.Repeat("a", unix.IFNAMSIZ), ""),
		append(linkMessage(1, "eth0", ""), wireAttribute(unix.IFLA_IFNAME, []byte("eth1\x00"))...),
		append(linkMessage(1, "eth0", ""), wireAttribute(unix.IFLA_LINKINFO, []byte{0, 0, 0, 0})...),
	} {
		if _, err := parseLink(invalid); err == nil {
			t.Fatal("invalid link identity accepted")
		}
	}
}

func TestRouteReadsBothFamiliesAndExtendedTableID(t *testing.T) {
	for _, family := range []byte{unix.AF_INET, unix.AF_INET6} {
		address := netip.MustParseAddr("203.0.113.0")
		gateway := netip.MustParseAddr("192.0.2.1")
		bits := byte(24)
		if family == unix.AF_INET6 {
			address, gateway, bits = netip.MustParseAddr("2001:db8::"), netip.MustParseAddr("2001:db8:1::1"), 48
		}
		data := routeMessage(family, 100001)
		data[1] = bits
		data = append(data, wireAttribute(unix.RTA_DST, address.AsSlice())...)
		data = append(data, wireAttribute(unix.RTA_GATEWAY, gateway.AsSlice())...)
		data = append(data, wireAttribute(unix.RTA_OIF, wireInteger(9))...)
		data = append(data, wireAttribute(unix.RTA_PRIORITY, wireInteger(^uint32(0)))...)
		route, err := parseRoute(data)
		if err != nil || route.Table != 100001 || route.Family != family || route.Interface != 9 ||
			route.Gateway != gateway || route.Priority != ^uint32(0) || route.Destination != netip.PrefixFrom(address, int(bits)) || route.Source.Bits() != 0 {
			t.Fatal("route fields lost or truncated", route, err)
		}
	}
}

func TestRouteDefaultWithoutDestinationAndImplicitTable(t *testing.T) {
	data := routeMessage(unix.AF_INET, unix.RT_TABLE_MAIN)[:networkHeaderSize]
	route, err := parseRoute(data)
	if err != nil || route.Table != unix.RT_TABLE_MAIN || route.Destination != netip.MustParsePrefix("0.0.0.0/0") || route.Priority != 0 {
		t.Fatal("omitted default-route attributes misread", route, err)
	}
	data = routeMessage(unix.AF_INET6, 98765)
	data = append(data, wireAttribute(routeNextHopID, wireInteger(123))...)
	route, err = parseRoute(data)
	if err != nil || route.NextHopID != 123 || route.Destination != netip.MustParsePrefix("::/0") {
		t.Fatal("nexthop-object identity lost", route, err)
	}
}

func nextHopMessage(index uint32, flags, weight byte, attributes []byte) []byte {
	data := make([]byte, unix.SizeofRtNexthop+len(attributes))
	binary.NativeEndian.PutUint16(data, uint16(len(data)))
	data[2], data[3] = flags, weight
	binary.NativeEndian.PutUint32(data[4:], index)
	copy(data[unix.SizeofRtNexthop:], attributes)
	return data
}

func TestRouteMultipathPreservesDeadFlagsAndUnknownAttributes(t *testing.T) {
	first := nextHopMessage(7, unix.RTNH_F_DEAD, 255, wireAttribute(unix.RTA_GATEWAY, []byte{192, 0, 2, 1}))
	second := nextHopMessage(8, 0, 0, wireAttribute(250, []byte{9, 8, 7}))
	data := append(routeMessage(unix.AF_INET, 90001), wireAttribute(unix.RTA_MULTIPATH, append(first, second...))...)
	route, err := parseRoute(data)
	if err != nil || len(route.NextHops) != 2 || route.NextHops[0].Flags != unix.RTNH_F_DEAD ||
		route.NextHops[0].Weight != 256 || route.NextHops[1].Weight != 1 || route.NextHops[1].Attributes[0].Type != 250 {
		t.Fatal("multipath identity changed", route, err)
	}
	for _, invalid := range [][]byte{
		nil, {0}, make([]byte, unix.SizeofRtNexthop), nextHopMessage(0, 0, 0, nil),
		append(nextHopMessage(1, 0, 0, nil), 0), nextHopMessage(1, 0, 0, []byte{0}),
	} {
		if _, err = parseNextHops(invalid, unix.AF_INET); err == nil {
			t.Fatal("malformed multipath accepted")
		}
	}
	conflict := append(data, wireAttribute(unix.RTA_OIF, wireInteger(1))...)
	if _, err = parseRoute(conflict); err == nil {
		t.Fatal("conflicting scalar/multipath nexthops accepted")
	}
}

func TestRouteRejectsMalformedPrefixesAndAttributes(t *testing.T) {
	invalidFamily := routeMessage(unix.AF_INET, 1)
	invalidFamily[0] = unix.AF_UNIX
	missingAddress := routeMessage(unix.AF_INET, 1)
	missingAddress[1] = 24
	nonNetwork := append(routeMessage(unix.AF_INET, 1), wireAttribute(unix.RTA_DST, []byte{192, 0, 2, 1})...)
	nonNetwork[1] = 24
	oversizedPrefix := routeMessage(unix.AF_INET, 1)
	oversizedPrefix[1] = 33
	for _, invalid := range [][]byte{
		nil, invalidFamily, missingAddress, nonNetwork, oversizedPrefix,
		append(routeMessage(unix.AF_INET6, 1), wireAttribute(unix.RTA_GATEWAY, []byte{192, 0, 2, 1})...),
		append(routeMessage(unix.AF_INET, 1), wireAttribute(unix.RTA_PRIORITY, []byte{1})...),
		append(routeMessage(unix.AF_INET, 1), wireAttribute(unix.RTA_TABLE, wireInteger(2))...),
	} {
		if _, err := parseRoute(invalid); err == nil {
			t.Fatal("invalid route accepted")
		}
	}
}

func TestRuleRetainsAllMatchingFieldsAndUnknownAttributeBytes(t *testing.T) {
	data := make([]byte, networkHeaderSize)
	data[0], data[1], data[2], data[3], data[4], data[7] = unix.AF_INET6, 64, 1, 8, unix.RT_TABLE_MAIN, unix.FR_ACT_TO_TBL
	binary.NativeEndian.PutUint32(data[8:], unix.FIB_RULE_INVERT)
	data = append(data, wireAttribute(unix.FRA_SRC, netip.MustParseAddr("8000::").AsSlice())...)
	data = append(data, wireAttribute(unix.FRA_DST, netip.MustParseAddr("2001:db8::").AsSlice())...)
	data = append(data, wireAttribute(unix.FRA_TABLE, wireInteger(100001))...)
	data = append(data, wireAttribute(unix.FRA_PRIORITY, wireInteger(30010))...)
	unknown := Attribute{Type: 250 | unix.NLA_F_NET_BYTEORDER, Value: []byte{1, 2, 3}}
	data = append(data, wireAttribute(unknown.Type, unknown.Value)...)
	rule, err := parseRule(data)
	if err != nil || rule.Family != unix.AF_INET6 || rule.Table != 100001 || rule.Priority != 30010 ||
		rule.Source != netip.MustParsePrefix("8000::/1") || rule.Destination != netip.MustParsePrefix("2001:db8::/64") ||
		rule.TOS != 8 || rule.Flags != unix.FIB_RULE_INVERT || rule.Action != unix.FR_ACT_TO_TBL ||
		!reflect.DeepEqual(rule.Attributes[len(rule.Attributes)-1], unknown) {
		t.Fatal("policy ownership identity was simplified", rule, err)
	}
	// The ordinary priority-zero local rule may omit FRA_PRIORITY entirely.
	data = make([]byte, networkHeaderSize)
	data[0], data[4], data[7] = unix.AF_INET, unix.RT_TABLE_LOCAL, unix.FR_ACT_TO_TBL
	if rule, err = parseRule(data); err != nil || rule.Priority != 0 || rule.Table != unix.RT_TABLE_LOCAL {
		t.Fatal("priority-zero local rule not preserved", rule, err)
	}
	for _, invalid := range [][]byte{
		nil, make([]byte, networkHeaderSize),
		append(append([]byte(nil), data...), wireAttribute(unix.FRA_PRIORITY, []byte{0})...),
		append(append(append([]byte(nil), data...), wireAttribute(unix.FRA_TABLE, wireInteger(1))...), wireAttribute(unix.FRA_TABLE, wireInteger(2))...),
	} {
		if _, err = parseRule(invalid); err == nil {
			t.Fatal("malformed rule accepted")
		}
	}
}
