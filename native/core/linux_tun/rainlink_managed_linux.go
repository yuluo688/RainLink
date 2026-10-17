//go:build linux && !android

package tun

import (
	"errors"
	"net/netip"
	"strings"
	"time"

	"github.com/sagernet/netlink"
	"golang.org/x/sys/unix"
)

// rainLinkRuleProtocol must match the resource guardian's expected rules.
// It scopes kernel deletion; a priority alone is never an ownership token.
const rainLinkRuleProtocol = 242

func rainLinkValidate(options Options) error {
	if !options.RainLinkManaged {
		return nil
	}
	if !strings.HasPrefix(options.Name, "rl-") || len(options.Name) < 4 || len(options.Name) >= unix.IFNAMSIZ ||
		options.IPRoute2TableIndex < 65536 || options.IPRoute2TableIndex > 0x7fffffff ||
		options.IPRoute2RuleIndex < 10000 || options.IPRoute2RuleIndex > 32755 ||
		!options.AutoRoute || !options.StrictRoute || options.MTU != 1500 || options.FileDescriptor != 0 || options.GSO ||
		options.AutoRedirectMarkMode || options.AutoRedirectInputMark != 0 && options.AutoRedirectInputMark != DefaultAutoRedirectInputMark ||
		options.AutoRedirectOutputMark != 0 && options.AutoRedirectOutputMark != DefaultAutoRedirectOutputMark {
		return errors.New("invalid RainLink-managed TUN resource configuration")
	}
	for _, value := range options.Name[3:] {
		if !(value >= 'a' && value <= 'z' || value >= '0' && value <= '9' || value == '-') {
			return errors.New("invalid RainLink-managed TUN name")
		}
	}
	if len(options.Inet4Address) != 1 || options.Inet4Address[0] != netip.MustParsePrefix("172.29.255.1/30") ||
		len(options.Inet6Address) != 1 || options.Inet6Address[0] != netip.MustParsePrefix("fdfe:dcba:9876::1/126") ||
		options.Inet4Gateway.IsValid() || options.Inet6Gateway.IsValid() || len(options.DNSServers) != 0 || options.InterfaceScope ||
		len(options.Inet4LoopbackAddress) != 0 || len(options.Inet6LoopbackAddress) != 0 ||
		len(options.Inet4RouteAddress) != 0 || len(options.Inet6RouteAddress) != 0 ||
		len(options.Inet4RouteExcludeAddress) != 0 || len(options.Inet6RouteExcludeAddress) != 0 ||
		len(options.IncludeInterface) != 0 || len(options.ExcludeInterface) != 0 ||
		len(options.IncludeUID) != 0 || len(options.ExcludeUID) != 0 || len(options.IncludeAndroidUser) != 0 ||
		len(options.IncludePackage) != 0 || len(options.ExcludePackage) != 0 {
		return errors.New("RainLink-managed TUN requires the fixed dual-stack policy")
	}
	return nil
}

func rainLinkRulesFree(options Options, rules []netlink.Rule) error {
	for _, rule := range rules {
		if rule.Table == options.IPRoute2TableIndex ||
			rule.Priority >= options.IPRoute2RuleIndex && rule.Priority <= options.IPRoute2RuleIndex+10 ||
			rule.Goto >= options.IPRoute2RuleIndex && rule.Goto <= options.IPRoute2RuleIndex+10 {
			return errors.New("RainLink-managed TUN policy resources are already in use")
		}
	}
	return nil
}

func rainLinkCheckResources(options Options, initial bool) error {
	handle, err := netlink.NewHandle(unix.NETLINK_ROUTE)
	if err != nil {
		return err
	}
	defer handle.Close()
	if err = handle.SetSocketTimeout(2 * time.Second); err != nil {
		return err
	}
	rules, err := handle.RuleList(netlink.FAMILY_ALL)
	if err != nil {
		return err
	}
	if err = rainLinkRulesFree(options, rules); err != nil {
		return err
	}
	if !initial {
		return nil
	}
	links, err := handle.LinkList()
	if err != nil {
		return err
	}
	for _, link := range links {
		if link.Attrs().Name == options.Name {
			return errors.New("RainLink-managed TUN interface already exists")
		}
	}
	routes, err := handle.RouteListFiltered(netlink.FAMILY_ALL, &netlink.Route{Table: options.IPRoute2TableIndex}, netlink.RT_FILTER_TABLE)
	if err != nil {
		return err
	}
	if len(routes) != 0 {
		return errors.New("RainLink-managed TUN table already contains routes")
	}
	return nil
}

func rainLinkInstallRules(options Options, rules []*netlink.Rule) error {
	if len(rules) != 16 {
		return errors.New("unexpected RainLink-managed TUN policy size")
	}
	if err := rainLinkCheckResources(options, false); err != nil {
		return err
	}
	handle, err := netlink.NewHandle(unix.NETLINK_ROUTE)
	if err != nil {
		return err
	}
	defer handle.Close()
	if err = handle.SetSocketTimeout(2 * time.Second); err != nil {
		return err
	}
	for _, rule := range rules {
		rule.Protocol = rainLinkRuleProtocol
		if err = handle.RuleAdd(rule); err != nil {
			return err
		}
	}
	return nil
}
