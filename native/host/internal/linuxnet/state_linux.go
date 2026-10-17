//go:build linux && !android

package linuxnet

import (
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"net/netip"

	"golang.org/x/sys/unix"
)

const (
	networkHeaderSize = 12 // rtmsg and fib_rule_hdr have the same fixed size.
	// Linux UAPI values not exported by the locked x/sys version.
	operNotPresent     = 1
	operDown           = 2
	operLowerLayerDown = 3
	operTesting        = 4
	operDormant        = 5
	operUp             = 6
	routeNextHopID     = 30 // RTA_NH_ID in linux/rtnetlink.h.
)

// Link describes a network interface, including its kernel-reported kind.
type Link struct {
	Index     uint32
	Name      string
	Flags     uint32
	Type      uint16
	Kind      string
	Master    uint32
	OperState uint8
}

// Up requires administrative readiness and rejects an explicitly unavailable
// operational state. UNKNOWN remains valid for PPP, containers and TUN.
func (l Link) Up() bool {
	return l.Flags&unix.IFF_UP != 0 && (l.OperState == 0 || l.OperState == operUp)
}

func parseLink(data []byte) (Link, error) {
	if len(data) < unix.SizeofIfInfomsg {
		return Link{}, errors.New("short link message")
	}
	index := int32(binary.NativeEndian.Uint32(data[4:]))
	if index <= 0 {
		return Link{}, errors.New("invalid link index")
	}
	attributes, err := parseAttributes(data[unix.SizeofIfInfomsg:])
	if err != nil {
		return Link{}, err
	}
	link := Link{Index: uint32(index), Type: binary.NativeEndian.Uint16(data[2:]), Flags: binary.NativeEndian.Uint32(data[8:])}
	if link.Name, err = stringAttribute(attributes, unix.IFLA_IFNAME); err != nil {
		return Link{}, err
	}
	if len(link.Name) == 0 || len(link.Name) >= unix.IFNAMSIZ {
		return Link{}, errors.New("invalid link name length")
	}
	if link.Master, err = uint32Attribute(attributes, unix.IFLA_MASTER, 0); err != nil {
		return Link{}, err
	}
	state, found, err := findAttribute(attributes, unix.IFLA_OPERSTATE)
	if err != nil {
		return Link{}, err
	}
	if found {
		if state.Type != unix.IFLA_OPERSTATE || len(state.Value) != 1 {
			return Link{}, errors.New("invalid link operational state")
		}
		link.OperState = state.Value[0]
	}
	info, found, err := findAttribute(attributes, unix.IFLA_LINKINFO)
	if err != nil {
		return Link{}, err
	}
	if found {
		if info.Type&unix.NLA_F_NET_BYTEORDER != 0 {
			return Link{}, errors.New("invalid link information flags")
		}
		nested, parseErr := parseAttributes(info.Value)
		if parseErr != nil {
			return Link{}, parseErr
		}
		if link.Kind, err = stringAttribute(nested, unix.IFLA_INFO_KIND); err != nil {
			return Link{}, err
		}
	}
	return link, nil
}

// NextHop is one rtnexthop in a multipath route. Weight is in the range 1–256.
type NextHop struct {
	Interface  uint32
	Gateway    netip.Addr
	Flags      uint8
	Weight     uint16
	Attributes []Attribute
}

// Route retains full-width routing table IDs; the rtmsg table byte is not
// sufficient for client-specific tables above 255.
type Route struct {
	Family      uint8
	Destination netip.Prefix
	Source      netip.Prefix
	TOS         uint8
	Table       uint32
	Protocol    uint8
	Scope       uint8
	Type        uint8
	Flags       uint32
	Priority    uint32
	Preference  uint8
	Interface   uint32
	Gateway     netip.Addr
	NextHops    []NextHop
	NextHopID   uint32
	Attributes  []Attribute
}

func addressAttribute(attributes []Attribute, kind uint16, family byte) (netip.Addr, error) {
	attribute, found, err := findAttribute(attributes, kind)
	if err != nil || !found {
		return netip.Addr{}, err
	}
	size := 4
	if family == unix.AF_INET6 {
		size = 16
	}
	if attribute.Type != kind || len(attribute.Value) != size {
		return netip.Addr{}, errors.New("invalid netlink address attribute")
	}
	address, ok := netip.AddrFromSlice(attribute.Value)
	if !ok {
		return netip.Addr{}, errors.New("invalid netlink address")
	}
	return address, nil
}

func prefixAttribute(attributes []Attribute, kind uint16, family, bits byte) (netip.Prefix, error) {
	address, err := addressAttribute(attributes, kind, family)
	if err != nil {
		return netip.Prefix{}, err
	}
	if !address.IsValid() {
		if bits != 0 {
			return netip.Prefix{}, errors.New("netlink prefix address is missing")
		}
		address = netip.IPv4Unspecified()
		if family == unix.AF_INET6 {
			address = netip.IPv6Unspecified()
		}
	}
	prefix := netip.PrefixFrom(address, int(bits))
	if !prefix.IsValid() || prefix != prefix.Masked() {
		return netip.Prefix{}, errors.New("invalid netlink prefix")
	}
	return prefix, nil
}

func parseNextHops(data []byte, family byte) ([]NextHop, error) {
	if len(data) == 0 {
		return nil, errors.New("empty multipath route")
	}
	var hops []NextHop
	for len(data) != 0 {
		if len(data) < unix.SizeofRtNexthop {
			return nil, errors.New("short route nexthop")
		}
		size := int(binary.NativeEndian.Uint16(data))
		if size < unix.SizeofRtNexthop || size > len(data) {
			return nil, errors.New("invalid route nexthop length")
		}
		index := int32(binary.NativeEndian.Uint32(data[4:]))
		if index <= 0 {
			return nil, errors.New("invalid route nexthop interface")
		}
		attributes, err := parseAttributes(data[unix.SizeofRtNexthop:size])
		if err != nil {
			return nil, err
		}
		hop := NextHop{Interface: uint32(index), Flags: data[2], Weight: uint16(data[3]) + 1, Attributes: attributes}
		if hop.Gateway, err = addressAttribute(attributes, unix.RTA_GATEWAY, family); err != nil {
			return nil, err
		}
		hops = append(hops, hop)
		if size == len(data) {
			break
		}
		padded := align4(size)
		if padded > len(data) {
			return nil, errors.New("short route nexthop padding")
		}
		data = data[padded:]
	}
	return hops, nil
}

func parseRoute(data []byte) (Route, error) {
	if len(data) < networkHeaderSize {
		return Route{}, errors.New("short route message")
	}
	family := data[0]
	if family != unix.AF_INET && family != unix.AF_INET6 {
		return Route{}, errors.New("unsupported route family")
	}
	attributes, err := parseAttributes(data[networkHeaderSize:])
	if err != nil {
		return Route{}, err
	}
	route := Route{Family: family, TOS: data[3], Protocol: data[5], Scope: data[6], Type: data[7],
		Flags: binary.NativeEndian.Uint32(data[8:]), Attributes: attributes}
	if route.Destination, err = prefixAttribute(attributes, unix.RTA_DST, family, data[1]); err != nil {
		return Route{}, err
	}
	if route.Source, err = prefixAttribute(attributes, unix.RTA_SRC, family, data[2]); err != nil {
		return Route{}, err
	}
	if route.Table, err = uint32Attribute(attributes, unix.RTA_TABLE, uint32(data[4])); err != nil {
		return Route{}, err
	}
	if route.Priority, err = uint32Attribute(attributes, unix.RTA_PRIORITY, 0); err != nil {
		return Route{}, err
	}
	if route.Interface, err = uint32Attribute(attributes, unix.RTA_OIF, 0); err != nil {
		return Route{}, err
	}
	if route.NextHopID, err = uint32Attribute(attributes, routeNextHopID, 0); err != nil {
		return Route{}, err
	}
	if route.Gateway, err = addressAttribute(attributes, unix.RTA_GATEWAY, family); err != nil {
		return Route{}, err
	}
	preference, found, err := findAttribute(attributes, unix.RTA_PREF)
	if err != nil {
		return Route{}, err
	}
	if found {
		if preference.Type != unix.RTA_PREF || len(preference.Value) != 1 ||
			(preference.Value[0] != 0 && preference.Value[0] != 1 && preference.Value[0] != 3) {
			return Route{}, errors.New("invalid IPv6 router preference")
		}
		route.Preference = preference.Value[0]
	}
	multipath, found, err := findAttribute(attributes, unix.RTA_MULTIPATH)
	if err != nil {
		return Route{}, err
	}
	if found {
		if multipath.Type != unix.RTA_MULTIPATH || route.Interface != 0 || route.NextHopID != 0 || route.Gateway.IsValid() {
			return Route{}, errors.New("conflicting route nexthops")
		}
		if route.NextHops, err = parseNextHops(multipath.Value, family); err != nil {
			return Route{}, err
		}
	}
	return route, nil
}

// Rule retains the full matching attributes. Priority and table are useful for
// conflict detection, but are not sufficient to authorize deletion of a rule.
type Rule struct {
	Family      uint8
	Destination netip.Prefix
	Source      netip.Prefix
	TOS         uint8
	Table       uint32
	Action      uint8
	Flags       uint32
	Priority    uint32
	Attributes  []Attribute
}

func parseRule(data []byte) (Rule, error) {
	if len(data) < networkHeaderSize {
		return Rule{}, errors.New("short policy rule message")
	}
	family := data[0]
	if family != unix.AF_INET && family != unix.AF_INET6 {
		return Rule{}, errors.New("unsupported policy rule family")
	}
	attributes, err := parseAttributes(data[networkHeaderSize:])
	if err != nil {
		return Rule{}, err
	}
	rule := Rule{Family: family, TOS: data[3], Action: data[7], Flags: binary.NativeEndian.Uint32(data[8:]), Attributes: attributes}
	if rule.Destination, err = prefixAttribute(attributes, unix.FRA_DST, family, data[1]); err != nil {
		return Rule{}, err
	}
	if rule.Source, err = prefixAttribute(attributes, unix.FRA_SRC, family, data[2]); err != nil {
		return Rule{}, err
	}
	if rule.Table, err = uint32Attribute(attributes, unix.FRA_TABLE, uint32(data[4])); err != nil {
		return Rule{}, err
	}
	if rule.Priority, err = uint32Attribute(attributes, unix.FRA_PRIORITY, 0); err != nil {
		return Rule{}, err
	}
	return rule, nil
}

// Links reads a complete link dump from the caller's network namespace.
func Links(ctx context.Context) ([]Link, error) {
	ctx, cancel := context.WithTimeout(ctx, readTimeout)
	defer cancel()
	values, err := readDump(ctx, unix.RTM_GETLINK, unix.AF_UNSPEC, unix.SizeofIfInfomsg)
	if err != nil {
		return nil, err
	}
	links := make([]Link, 0, len(values))
	seen := make(map[uint32]bool)
	for _, value := range values {
		if err = ctx.Err(); err != nil {
			return nil, err
		}
		link, parseErr := parseLink(value)
		if parseErr != nil {
			return nil, parseErr
		}
		if seen[link.Index] {
			return nil, ErrChanged
		}
		seen[link.Index] = true
		links = append(links, link)
	}
	return links, nil
}

// Routes reads both IP families and every routing table, including local and
// client-specific tables. A failed family never returns a partial success.
func Routes(ctx context.Context) ([]Route, error) {
	ctx, cancel := context.WithTimeout(ctx, readTimeout)
	defer cancel()
	var routes []Route
	for _, family := range []byte{unix.AF_INET, unix.AF_INET6} {
		values, err := readDump(ctx, unix.RTM_GETROUTE, family, networkHeaderSize)
		if err != nil {
			return nil, err
		}
		for _, value := range values {
			if err = ctx.Err(); err != nil {
				return nil, err
			}
			route, parseErr := parseRoute(value)
			if parseErr != nil {
				return nil, parseErr
			}
			if route.Family != family {
				return nil, errors.New("route dump family mismatch")
			}
			routes = append(routes, route)
		}
	}
	return routes, nil
}

// Rules reads all IPv4 and IPv6 policy rules without changing their order.
func Rules(ctx context.Context) ([]Rule, error) {
	ctx, cancel := context.WithTimeout(ctx, readTimeout)
	defer cancel()
	var rules []Rule
	for _, family := range []byte{unix.AF_INET, unix.AF_INET6} {
		values, err := readDump(ctx, unix.RTM_GETRULE, family, networkHeaderSize)
		if err != nil {
			return nil, err
		}
		for _, value := range values {
			if err = ctx.Err(); err != nil {
				return nil, err
			}
			rule, parseErr := parseRule(value)
			if parseErr != nil {
				return nil, parseErr
			}
			if rule.Family != family {
				return nil, errors.New("policy rule dump family mismatch")
			}
			rules = append(rules, rule)
		}
	}
	return rules, nil
}

// State consists of individually complete dumps, not an atomic kernel
// transaction. Capture transitions must recheck it after acquiring a lease.
type State struct {
	Links  []Link
	Routes []Route
	Rules  []Rule
}

// Read obtains bounded observations for both families. Interrupted or
// incomplete dumps return no state, so they cannot authorize capture cleanup.
func Read(ctx context.Context) (State, error) {
	ctx, cancel := context.WithTimeout(ctx, readTimeout)
	defer cancel()
	var state State
	var err error
	if state.Links, err = Links(ctx); err != nil {
		return State{}, fmt.Errorf("read links: %w", err)
	}
	if state.Routes, err = Routes(ctx); err != nil {
		return State{}, fmt.Errorf("read routes: %w", err)
	}
	if state.Rules, err = Rules(ctx); err != nil {
		return State{}, fmt.Errorf("read policy rules: %w", err)
	}
	return state, nil
}
