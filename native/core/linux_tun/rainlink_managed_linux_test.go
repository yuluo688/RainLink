//go:build linux && !android

package tun

import (
	"net/netip"
	"testing"

	"github.com/sagernet/netlink"
	"golang.org/x/sys/unix"
)

func rainLinkOptions() Options {
	return Options{RainLinkManaged: true, Name: "rl-core-test", MTU: 1500, AutoRoute: true, StrictRoute: true,
		IPRoute2TableIndex: 100003, IPRoute2RuleIndex: 31000,
		Inet4Address: []netip.Prefix{netip.MustParsePrefix("172.29.255.1/30")},
		Inet6Address: []netip.Prefix{netip.MustParsePrefix("fdfe:dcba:9876::1/126")}}
}

func TestRainLinkManagedPolicyValidation(t *testing.T) {
	if err := rainLinkValidate(rainLinkOptions()); err != nil {
		t.Fatal(err)
	}
	for _, mutate := range []func(*Options){
		func(o *Options) { o.Name = "eth0" }, func(o *Options) { o.Name = "rl-Upper" },
		func(o *Options) { o.IPRoute2TableIndex = 254 }, func(o *Options) { o.IPRoute2RuleIndex = 32760 },
		func(o *Options) { o.AutoRoute = false }, func(o *Options) { o.StrictRoute = false },
		func(o *Options) { o.FileDescriptor = 10 }, func(o *Options) { o.AutoRedirectMarkMode = true },
		func(o *Options) { o.Inet6Address = nil }, func(o *Options) { o.IncludeInterface = []string{"lo"} },
		func(o *Options) { o.Inet4Address = []netip.Prefix{netip.MustParsePrefix("192.0.2.1/24")} },
		func(o *Options) { o.Inet4RouteAddress = []netip.Prefix{netip.MustParsePrefix("0.0.0.0/0")} },
	} {
		options := rainLinkOptions()
		mutate(&options)
		if err := rainLinkValidate(options); err == nil {
			t.Fatal("uncontrolled policy accepted")
		}
	}
	if err := rainLinkValidate(Options{}); err != nil {
		t.Fatal("legacy behavior was changed", err)
	}
}

func TestRainLinkManagedPolicyNeverDeletesByRangeOrUpdatesInPlace(t *testing.T) {
	managed := &NativeTun{options: rainLinkOptions(), ruleIndex6: []int{1}}
	// No valid descriptor, interface or privileges: these operations must
	// refuse/return before reaching the upstream destructive network paths.
	if err := managed.unsetRules(); err != nil || len(managed.ruleIndex6) != 1 {
		t.Fatal("managed cleanup touched legacy rules", err)
	}
	if err := managed.UpdateRouteOptions(Options{}); err == nil {
		t.Fatal("managed mode allowed its ownership fields to be replaced")
	}
	if err := managed.resetRules(); err == nil {
		t.Fatal("managed mode duplicated its existing rules")
	}
}

func TestRainLinkManagedRuleConflictsIncludeBothFamiliesAndGotoTargets(t *testing.T) {
	options := rainLinkOptions()
	for _, rule := range []netlink.Rule{
		{Family: unix.AF_INET, Priority: options.IPRoute2RuleIndex},
		{Family: unix.AF_INET6, Priority: options.IPRoute2RuleIndex + 10},
		{Family: unix.AF_INET, Table: options.IPRoute2TableIndex},
		{Family: unix.AF_INET6, Goto: options.IPRoute2RuleIndex + 5},
	} {
		if err := rainLinkRulesFree(options, []netlink.Rule{rule}); err == nil {
			t.Fatal("occupied policy resources accepted", rule)
		}
	}
	if err := rainLinkRulesFree(options, []netlink.Rule{{Priority: 32766, Table: 254, Goto: -1}}); err != nil {
		t.Fatal("unrelated rule blocked dedicated allocation", err)
	}
}
