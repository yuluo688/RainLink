//go:build linux && !android

package linuxnet

import (
	"errors"
	"net/netip"
	"slices"
	"testing"

	"golang.org/x/sys/unix"
)

func testPolicyRule() Rule {
	return Rule{Family: unix.AF_INET, Source: netip.MustParsePrefix("0.0.0.0/0"), Destination: netip.MustParsePrefix("0.0.0.0/0"),
		Table: 100050, Priority: 32500, Action: unix.FR_ACT_TO_TBL,
		Attributes: []Attribute{{Type: unix.FRA_TABLE, Value: integerBytes(100050)}, {Type: unix.FRA_PRIORITY, Value: integerBytes(32500)}}}
}

func copyPolicyRule(rule Rule) Rule {
	rule.Attributes = slices.Clone(rule.Attributes)
	for index := range rule.Attributes {
		rule.Attributes[index].Value = slices.Clone(rule.Attributes[index].Value)
	}
	return rule
}

func TestRuleIdentityNormalizesOnlyKernelDefaults(t *testing.T) {
	expected := testPolicyRule()
	observed := copyPolicyRule(expected)
	observed.Attributes = append(observed.Attributes,
		Attribute{Type: unix.FRA_SUPPRESS_PREFIXLEN, Value: integerBytes(^uint32(0))},
		Attribute{Type: unix.FRA_SUPPRESS_IFGROUP, Value: integerBytes(^uint32(0))},
		Attribute{Type: unix.FRA_PROTOCOL, Value: []byte{0}},
		Attribute{Type: unix.FRA_SRC, Value: []byte{0, 0, 0, 0}})
	slices.Reverse(observed.Attributes)
	if same, err := SameRule(expected, observed); err != nil || !same {
		t.Fatal("attribute order or default changed identity", err)
	}
	for _, test := range []struct {
		name   string
		mutate func(*Rule)
	}{
		{"invert", func(rule *Rule) { rule.Flags |= unix.FIB_RULE_INVERT }},
		{"unknown-flag", func(rule *Rule) { rule.Flags |= 0x80000000 }},
		{"protocol", func(rule *Rule) {
			rule.Attributes = append(rule.Attributes, Attribute{Type: unix.FRA_PROTOCOL, Value: []byte{99}})
		}},
		{"mark", func(rule *Rule) {
			rule.Attributes = append(rule.Attributes, Attribute{Type: unix.FRA_FWMARK, Value: integerBytes(3)})
		}},
		{"suppress", func(rule *Rule) {
			rule.Attributes = append(rule.Attributes, Attribute{Type: unix.FRA_SUPPRESS_PREFIXLEN, Value: integerBytes(0)})
		}},
		{"unknown-attribute", func(rule *Rule) { rule.Attributes = append(rule.Attributes, Attribute{Type: 123, Value: []byte{1, 2}}) }},
		{"attribute-flags", func(rule *Rule) {
			rule.Attributes = append(rule.Attributes, Attribute{Type: 123 | unix.NLA_F_NESTED, Value: []byte{1, 2}})
		}},
	} {
		t.Run(test.name, func(t *testing.T) {
			changed := copyPolicyRule(expected)
			test.mutate(&changed)
			if same, err := SameRule(expected, changed); err != nil || same {
				t.Fatal("changed owner was treated as the expected rule", err)
			}
		})
	}
	input := copyPolicyRule(expected)
	input.Attributes = append(input.Attributes, Attribute{Type: unix.FRA_IIFNAME, Value: []byte("rl-gone\x00")})
	detached := copyPolicyRule(input)
	detached.Flags = unix.FIB_RULE_IIF_DETACHED
	if same, err := SameRule(input, detached); err != nil || !same {
		t.Fatal("kernel interface-detached bookkeeping changed ownership", err)
	}
	detached = copyPolicyRule(expected)
	detached.Flags = unix.FIB_RULE_IIF_DETACHED
	if same, err := SameRule(expected, detached); err != nil || same {
		t.Fatal("detached flag ignored without an interface", err)
	}
}

func TestRuleIdentityRejectsMalformedAndConflictingAttributes(t *testing.T) {
	for _, mutate := range []func(*Rule){
		func(rule *Rule) { rule.Table++ },
		func(rule *Rule) { rule.Priority++ },
		func(rule *Rule) { rule.Family = unix.AF_INET6 },
		func(rule *Rule) { rule.Attributes = append(rule.Attributes, rule.Attributes[0]) },
		func(rule *Rule) {
			rule.Attributes = append(rule.Attributes, Attribute{Type: unix.FRA_PROTOCOL, Value: []byte{0, 1}})
		},
		func(rule *Rule) {
			rule.Attributes = append(rule.Attributes, Attribute{Type: unix.FRA_IIFNAME, Value: []byte("without-nul")})
		},
		func(rule *Rule) {
			rule.Attributes = append(rule.Attributes, Attribute{Type: unix.FRA_SUPPRESS_IFGROUP, Value: []byte{0}})
		},
	} {
		expected := testPolicyRule()
		mutate(&expected)
		if _, err := SameRule(expected, testPolicyRule()); err == nil {
			t.Fatal("invalid ownership attributes accepted")
		}
	}
}

func TestRuleDeletionSelectorIsConservative(t *testing.T) {
	request, err := canonicalRule(testPolicyRule())
	if err != nil {
		t.Fatal(err)
	}
	other := testPolicyRule()
	other.Flags = unix.FIB_RULE_INVERT
	other.Attributes = append(other.Attributes, Attribute{Type: unix.FRA_SUPPRESS_PREFIXLEN, Value: integerBytes(0)})
	if matches, err := deletionCouldMatch(request, other); err != nil || !matches {
		t.Fatal("deletion incorrectly assumes inversion/suppression filter", err)
	}
	other.Attributes = append(other.Attributes, Attribute{Type: unix.FRA_PROTOCOL, Value: []byte{99}})
	if matches, err := deletionCouldMatch(request, other); err != nil || !matches {
		t.Fatal("protocol zero was incorrectly treated as a kernel filter", err)
	}
	request.Attributes = append([]Attribute(nil), request.Attributes...)
	for index := range request.Attributes {
		if request.Attributes[index].Type == unix.FRA_PROTOCOL {
			request.Attributes[index].Value = []byte{98}
		}
	}
	if matches, err := deletionCouldMatch(request, other); err != nil || matches {
		t.Fatal("nonzero protocol did not distinguish the kernel selector", err)
	}
	other = testPolicyRule()
	other.Table++
	other.Attributes[0].Value = integerBytes(other.Table)
	if matches, err := deletionCouldMatch(request, other); err != nil || matches {
		t.Fatal("table did not distinguish selector", err)
	}
}

func TestMutationRequiresSuccessfulErrorACK(t *testing.T) {
	for _, test := range []struct {
		name    string
		kind    uint16
		payload []byte
		success bool
		cause   error
	}{
		{"ack", unix.NLMSG_ERROR, wireInteger(0), true, nil},
		{"done", unix.NLMSG_DONE, wireInteger(0), false, nil},
		{"empty-ack", unix.NLMSG_ERROR, nil, false, nil},
		{"data", unix.RTM_NEWRULE, make([]byte, 12), false, nil},
		{"reserved-type", 0, nil, false, nil},
		{"positive-errno", unix.NLMSG_ERROR, wireInteger(1), false, nil},
		{"denied", unix.NLMSG_ERROR, wireInteger(^uint32(unix.EPERM - 1)), false, unix.EPERM},
	} {
		t.Run(test.name, func(t *testing.T) {
			state := dump{port: 7, ackOnly: true}
			err := state.accept(wireMessage(test.kind, 0, 1, 7, test.payload))
			if (err == nil) != test.success || state.complete != test.success || test.cause != nil && !errors.Is(err, test.cause) {
				t.Fatal("invalid mutation result", state.complete, err)
			}
		})
	}
}
