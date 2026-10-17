//go:build linux && !android

package linuxnet

import (
	"errors"
	"os"
	"reflect"
	"testing"

	"golang.org/x/sys/unix"
)

func TestIsolatedExactPolicyDeletionPreservesOtherOwners(t *testing.T) {
	if os.Getenv("RAINLINK_TEST_ROOT_TUN_NAMESPACE") != "isolated" {
		t.Skip("requires root in a disposable network namespace")
	}
	requireNetworkFixture(t)
	if os.Geteuid() != 0 {
		t.Fatal("requires isolated root")
	}
	before, err := Rules(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	for _, rule := range before {
		if rule.Priority == 32500 || rule.Priority == 32501 {
			t.Fatal("fixture priority already occupied")
		}
	}
	mutate := func(t *testing.T, rule Rule, remove bool) {
		t.Helper()
		payload, err := encodeRule(rule)
		if err != nil {
			t.Fatal(err)
		}
		kind, flags := uint16(unix.RTM_NEWRULE), uint16(unix.NLM_F_ACK|unix.NLM_F_CREATE|unix.NLM_F_EXCL)
		if remove {
			kind, flags = unix.RTM_DELRULE, unix.NLM_F_ACK
		}
		if _, err = exchange(t.Context(), kind, flags, payload, true); err != nil {
			t.Fatal("isolated fixture mutation", err)
		}
	}
	read := func(t *testing.T) []Rule {
		t.Helper()
		rules, err := Rules(t.Context())
		if err != nil {
			t.Fatal(err)
		}
		return rules
	}
	for _, difference := range []string{"protocol-zero", "protocol", "table"} {
		t.Run(difference, func(t *testing.T) {
			own := testPolicyRule()
			own.Attributes = append(own.Attributes, Attribute{Type: unix.FRA_PROTOCOL, Value: []byte{0}})
			foreign := copyPolicyRule(own)
			if difference == "protocol" || difference == "protocol-zero" {
				foreign.Attributes[len(foreign.Attributes)-1].Value = []byte{99}
				if difference == "protocol" {
					own.Attributes[len(own.Attributes)-1].Value = []byte{98}
				}
			} else {
				foreign.Table++
				foreign.Attributes[0].Value = integerBytes(foreign.Table)
			}
			// Foreign is inserted first. A kernel ignoring the supplied selector
			// would delete it, which this test must detect rather than hide.
			mutate(t, foreign, false)
			withForeign := read(t)
			mutate(t, own, false)
			if difference == "protocol-zero" {
				both := read(t)
				if deleted, err := DeleteExactRule(t.Context(), own); !errors.Is(err, ErrAmbiguousRule) || deleted {
					t.Fatal("protocol-zero deletion did not refuse ambiguity", deleted, err)
				}
				if !reflect.DeepEqual(read(t), both) {
					t.Fatal("ambiguous protocol deletion changed either owner")
				}
				if deleted, err := DeleteExactRule(t.Context(), foreign); err != nil || !deleted {
					t.Fatal("nonzero fixture protocol could not be deleted", err)
				}
				if deleted, err := DeleteExactRule(t.Context(), own); err != nil || !deleted {
					t.Fatal("unique protocol-zero rule could not be deleted", err)
				}
				return
			}
			deleted, err := DeleteExactRule(t.Context(), own)
			if err != nil || !deleted {
				t.Fatal("owned rule not acknowledged", deleted, err)
			}
			if !reflect.DeepEqual(read(t), withForeign) {
				t.Fatal("another owner's rule changed")
			}
			if deleted, err = DeleteExactRule(t.Context(), own); err != nil || deleted {
				t.Fatal("absent rule reported deleted", err)
			}
			mutate(t, foreign, true)
		})
	}
	t.Run("ambiguous-suppression", func(t *testing.T) {
		first := testPolicyRule()
		first.Attributes = append(first.Attributes, Attribute{Type: unix.FRA_SUPPRESS_PREFIXLEN, Value: integerBytes(0)})
		second := testPolicyRule()
		mutate(t, first, false)
		mutate(t, second, false)
		both := read(t)
		if deleted, err := DeleteExactRule(t.Context(), second); !errors.Is(err, ErrAmbiguousRule) || deleted {
			t.Fatal("ambiguous deletion did not stop", deleted, err)
		}
		if !reflect.DeepEqual(read(t), both) {
			t.Fatal("ambiguous deletion changed kernel state")
		}
		// These are both disposable fixture rules. Production never uses this
		// raw deletion path or flushes their shared priority.
		mutate(t, first, true)
		mutate(t, second, true)
	})
	t.Run("changed-owner", func(t *testing.T) {
		expected := testPolicyRule()
		changed := copyPolicyRule(expected)
		changed.Flags = unix.FIB_RULE_INVERT
		mutate(t, changed, false)
		state := read(t)
		if deleted, err := DeleteExactRule(t.Context(), expected); err != nil || deleted {
			t.Fatal("changed owner deleted", err)
		}
		if !reflect.DeepEqual(read(t), state) {
			t.Fatal("changed owner was not preserved")
		}
		mutate(t, changed, true)
	})
	t.Run("nop-table-zero", func(t *testing.T) {
		rule := testPolicyRule()
		rule.Priority, rule.Table, rule.Action = 32501, 0, unix.FR_ACT_NOP
		rule.Attributes = []Attribute{{Type: unix.FRA_PRIORITY, Value: integerBytes(rule.Priority)}, {Type: unix.FRA_TABLE, Value: integerBytes(0)}}
		mutate(t, rule, false)
		if deleted, err := DeleteExactRule(t.Context(), rule); err != nil || !deleted {
			t.Fatal("NOP deletion failed", err)
		}
	})
	if !reflect.DeepEqual(read(t), before) {
		t.Fatal("fixture did not restore its exact initial policy state")
	}
}
