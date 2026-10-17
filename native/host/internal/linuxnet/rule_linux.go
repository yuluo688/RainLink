//go:build linux && !android

package linuxnet

import (
	"bytes"
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"slices"

	"golang.org/x/sys/unix"
)

// ErrAmbiguousRule means the kernel deletion selector could identify more
// than one current rule. No deletion is sent in that case.
var ErrAmbiguousRule = errors.New("policy rule deletion would be ambiguous")

func integerBytes(value uint32) []byte {
	data := make([]byte, 4)
	binary.NativeEndian.PutUint32(data, value)
	return data
}

func encodeAttributes(attributes []Attribute) ([]byte, error) {
	var data []byte
	for _, attribute := range attributes {
		size := 4 + len(attribute.Value)
		if size > int(^uint16(0)) || attribute.Type&attributeTypeMask == 0 {
			return nil, errors.New("invalid policy rule attribute")
		}
		start := len(data)
		data = append(data, make([]byte, align4(size))...)
		binary.NativeEndian.PutUint16(data[start:], uint16(size))
		binary.NativeEndian.PutUint16(data[start+2:], attribute.Type)
		copy(data[start+4:], attribute.Value)
		if len(data) > maxDatagramBytes-networkHeaderSize-netlinkHeaderSize {
			return nil, errors.New("policy rule exceeds message limit")
		}
	}
	return data, nil
}

func encodeRule(rule Rule) ([]byte, error) {
	if rule.Family != unix.AF_INET && rule.Family != unix.AF_INET6 ||
		!rule.Source.IsValid() || !rule.Destination.IsValid() ||
		rule.Source != rule.Source.Masked() || rule.Destination != rule.Destination.Masked() ||
		(rule.Family == unix.AF_INET) != rule.Source.Addr().Is4() ||
		(rule.Family == unix.AF_INET) != rule.Destination.Addr().Is4() {
		return nil, errors.New("invalid policy rule family or prefixes")
	}
	attributes, err := encodeAttributes(rule.Attributes)
	if err != nil {
		return nil, err
	}
	data := make([]byte, networkHeaderSize, networkHeaderSize+len(attributes))
	data[0], data[1], data[2], data[3], data[7] = rule.Family, byte(rule.Destination.Bits()), byte(rule.Source.Bits()), rule.TOS, rule.Action
	if rule.Table <= 255 {
		data[4] = byte(rule.Table)
	}
	binary.NativeEndian.PutUint32(data[8:], rule.Flags)
	return append(data, attributes...), nil
}

func canonicalRule(rule Rule) (Rule, error) {
	raw, err := encodeRule(rule)
	if err != nil {
		return Rule{}, err
	}
	parsed, err := parseRule(raw)
	if err != nil {
		return Rule{}, err
	}
	if parsed.Table != rule.Table || parsed.Priority != rule.Priority || parsed.Source != rule.Source || parsed.Destination != rule.Destination {
		return Rule{}, errors.New("policy rule attributes disagree with header")
	}
	attributes := make(map[uint16]Attribute, len(rule.Attributes)+4)
	for _, attribute := range rule.Attributes {
		kind := attribute.Type & attributeTypeMask
		if _, found := attributes[kind]; found {
			return Rule{}, errors.New("duplicate policy rule ownership attribute")
		}
		attributes[kind] = attribute
	}
	// The kernel supplies these defaults on some versions and omits them on
	// others. Canonicalize only documented defaults; unknown matching fields
	// remain part of the identity and cannot be silently discarded.
	for kind, value := range map[uint16]uint32{
		unix.FRA_TABLE: rule.Table, unix.FRA_PRIORITY: rule.Priority,
		unix.FRA_SUPPRESS_PREFIXLEN: ^uint32(0), unix.FRA_SUPPRESS_IFGROUP: ^uint32(0),
	} {
		if _, present := attributes[kind]; !present {
			attributes[kind] = Attribute{Type: kind, Value: integerBytes(value)}
		} else if _, err = uint32Attribute(rule.Attributes, kind, value); err != nil {
			return Rule{}, err
		}
	}
	protocol, present, err := findAttribute(rule.Attributes, unix.FRA_PROTOCOL)
	if err != nil {
		return Rule{}, err
	}
	if present && (protocol.Type != unix.FRA_PROTOCOL || len(protocol.Value) != 1) {
		return Rule{}, errors.New("invalid policy rule protocol")
	}
	if !present {
		attributes[unix.FRA_PROTOCOL] = Attribute{Type: unix.FRA_PROTOCOL, Value: []byte{0}}
	}
	for kind, prefix := range map[uint16]int{unix.FRA_SRC: rule.Source.Bits(), unix.FRA_DST: rule.Destination.Bits()} {
		if prefix == 0 {
			delete(attributes, kind)
		}
	}
	input, err := stringAttribute(rule.Attributes, unix.FRA_IIFNAME)
	if err != nil {
		return Rule{}, err
	}
	output, err := stringAttribute(rule.Attributes, unix.FRA_OIFNAME)
	if err != nil {
		return Rule{}, err
	}
	if len(input) >= unix.IFNAMSIZ || len(output) >= unix.IFNAMSIZ {
		return Rule{}, errors.New("invalid policy rule interface length")
	}
	if input != "" {
		rule.Flags &^= unix.FIB_RULE_IIF_DETACHED
	}
	if output != "" {
		rule.Flags &^= unix.FIB_RULE_OIF_DETACHED
	}
	if rule.Action == unix.FR_ACT_GOTO {
		rule.Flags &^= unix.FIB_RULE_UNRESOLVED
	}
	rule.Attributes = make([]Attribute, 0, len(attributes))
	for _, attribute := range attributes {
		rule.Attributes = append(rule.Attributes, attribute)
	}
	slices.SortFunc(rule.Attributes, func(left, right Attribute) int { return int(left.Type) - int(right.Type) })
	return rule, nil
}

// SameRule compares complete rule identities, ignoring attribute order and
// documented kernel defaults/detached-interface bookkeeping. Unknown matching
// attributes, protocol, inversion and all other flags remain significant.
func SameRule(expected, observed Rule) (bool, error) {
	left, err := canonicalRule(expected)
	if err != nil {
		return false, err
	}
	right, err := canonicalRule(observed)
	if err != nil {
		return false, err
	}
	leftBytes, err := encodeRule(left)
	if err != nil {
		return false, err
	}
	rightBytes, err := encodeRule(right)
	return bytes.Equal(leftBytes, rightBytes), err
}

func deletionCouldMatch(request, candidate Rule) (bool, error) {
	if request.Family != candidate.Family || request.Priority != candidate.Priority || request.Action != candidate.Action ||
		request.Source != candidate.Source || request.Destination != candidate.Destination || request.TOS != candidate.TOS ||
		request.Table != 0 && request.Table != candidate.Table {
		return false, nil
	}
	// Keep this selector conservative: do not assume that a deletion filters
	// inversion, suppression, goto targets or unknown attributes. Table zero
	// is treated as a wildcard. These differences must not select an arbitrary
	// first rule when another owner shares the same priority.
	for _, kind := range []uint16{unix.FRA_IIFNAME, unix.FRA_OIFNAME, unix.FRA_PROTOCOL} {
		attribute, found, err := findAttribute(request.Attributes, kind)
		if err != nil {
			return false, err
		}
		if !found {
			continue
		}
		// fib_nl_delrule treats protocol zero as unspecified even when the
		// attribute was explicitly supplied. It cannot distinguish a second
		// owner's nonzero protocol at the same selector.
		if kind == unix.FRA_PROTOCOL && len(attribute.Value) == 1 && attribute.Value[0] == 0 {
			continue
		}
		other, present, err := findAttribute(candidate.Attributes, kind)
		if err != nil {
			return false, err
		}
		if !present && kind == unix.FRA_PROTOCOL {
			other, present = Attribute{Type: kind, Value: []byte{0}}, true
		}
		if !present || attribute.Type != other.Type || !bytes.Equal(attribute.Value, other.Value) {
			return false, nil
		}
	}
	return true, nil
}

// DeleteExactRule rereads policy rules, preserves a changed owner, refuses
// ambiguous kernel selectors and waits for an acknowledged RTM_DELRULE.
// It never flushes a priority range or a table. Callers must hold their capture
// lease, stop the producing core first, and verify final recovery themselves.
func DeleteExactRule(ctx context.Context, expected Rule) (bool, error) {
	if expected.Priority == 0 || expected.Action == 0 {
		return false, errors.New("refuse an incomplete policy rule deletion selector")
	}
	request, err := canonicalRule(expected)
	if err != nil {
		return false, err
	}
	current, err := Rules(ctx)
	if err != nil {
		return false, err
	}
	var selected *Rule
	for index := range current {
		matches, err := deletionCouldMatch(request, current[index])
		if err != nil {
			return false, err
		}
		if !matches {
			continue
		}
		if selected != nil {
			return false, ErrAmbiguousRule
		}
		selected = &current[index]
	}
	if selected == nil {
		return false, nil
	}
	matches, err := SameRule(request, *selected)
	if err != nil || !matches {
		return false, err
	}
	payload, err := encodeRule(request)
	if err != nil {
		return false, err
	}
	_, err = exchange(ctx, unix.RTM_DELRULE, unix.NLM_F_ACK, payload, true)
	if errors.Is(err, unix.ENOENT) || errors.Is(err, unix.ESRCH) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("delete owned policy rule: %w", err)
	}
	return true, nil
}
