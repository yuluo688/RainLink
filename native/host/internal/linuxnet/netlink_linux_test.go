//go:build linux && !android

package linuxnet

import (
	"context"
	"encoding/binary"
	"errors"
	"reflect"
	"testing"
	"time"

	"golang.org/x/sys/unix"
)

func wireMessage(kind, flags uint16, seq, port uint32, payload []byte) []byte {
	size := netlinkHeaderSize + len(payload)
	data := make([]byte, align4(size))
	binary.NativeEndian.PutUint32(data, uint32(size))
	binary.NativeEndian.PutUint16(data[4:], kind)
	binary.NativeEndian.PutUint16(data[6:], flags)
	binary.NativeEndian.PutUint32(data[8:], seq)
	binary.NativeEndian.PutUint32(data[12:], port)
	copy(data[netlinkHeaderSize:], payload)
	return data
}

func wireAttribute(kind uint16, payload []byte) []byte {
	size := 4 + len(payload)
	data := make([]byte, align4(size))
	binary.NativeEndian.PutUint16(data, uint16(size))
	binary.NativeEndian.PutUint16(data[2:], kind)
	copy(data[4:], payload)
	return data
}

func wireInteger(value uint32) []byte {
	data := make([]byte, 4)
	binary.NativeEndian.PutUint32(data, value)
	return data
}

func TestDumpRequiresCompleteMatchingKernelResponse(t *testing.T) {
	value := wireMessage(unix.RTM_NEWROUTE, unix.NLM_F_MULTI, 1, 1024, []byte{1, 2, 3})
	complete := wireMessage(unix.NLMSG_DONE, unix.NLM_F_MULTI, 1, 1024, wireInteger(0))
	state := dump{port: 1024, expected: unix.RTM_NEWROUTE}
	if err := state.accept(value); err != nil || state.complete {
		t.Fatal("data without NLMSG_DONE became a completed observation", err)
	}
	if err := state.accept(complete); err != nil || !state.complete || !reflect.DeepEqual(state.values, [][]byte{{1, 2, 3}}) {
		t.Fatal("complete multipart response was not preserved", err)
	}
	if err := state.accept(value); err == nil {
		t.Fatal("data after completion accepted")
	}
	for _, test := range []struct {
		name string
		data []byte
	}{
		{"sequence", wireMessage(unix.RTM_NEWROUTE, 0, 2, 1024, nil)},
		{"port", wireMessage(unix.RTM_NEWROUTE, 0, 1, 999, nil)},
		{"type", wireMessage(unix.RTM_NEWLINK, 0, 1, 1024, nil)},
		{"after-done", append(append([]byte(nil), complete...), value...)},
		{"short-result", wireMessage(unix.NLMSG_DONE, 0, 1, 1024, []byte{0})},
		{"empty-error", wireMessage(unix.NLMSG_ERROR, 0, 1, 1024, nil)},
		{"positive-errno", wireMessage(unix.NLMSG_ERROR, 0, 1, 1024, wireInteger(1))},
	} {
		t.Run(test.name, func(t *testing.T) {
			state := dump{port: 1024, expected: unix.RTM_NEWROUTE}
			if err := state.accept(test.data); err == nil {
				t.Fatal("invalid response accepted")
			}
		})
	}
}

func TestDumpRejectsInterruptedOverrunAndKernelErrors(t *testing.T) {
	for _, data := range [][]byte{
		wireMessage(unix.NLMSG_DONE, unix.NLM_F_DUMP_INTR, 1, 7, wireInteger(0)),
		wireMessage(unix.RTM_NEWROUTE, unix.NLM_F_DUMP_INTR, 1, 7, nil),
		wireMessage(unix.NLMSG_OVERRUN, 0, 1, 7, nil),
	} {
		state := dump{port: 7, expected: unix.RTM_NEWROUTE}
		if err := state.accept(data); !errors.Is(err, ErrChanged) {
			t.Fatal("partial network state did not report interruption", err)
		}
	}
	code := -int32(unix.EPERM)
	state := dump{port: 7, expected: unix.RTM_NEWROUTE}
	err := state.accept(wireMessage(unix.NLMSG_ERROR, 0, 1, 7, wireInteger(uint32(code))))
	if !errors.Is(err, unix.EPERM) || state.complete {
		t.Fatal("kernel error became a successful observation", err)
	}
	ack := dump{port: 7, expected: unix.RTM_NEWROUTE}
	if err = ack.accept(wireMessage(unix.NLMSG_ERROR, 0, 1, 7, wireInteger(0))); err != nil || ack.complete {
		t.Fatal("ACK substituted for multipart completion", err)
	}
}

func TestDumpEnforcesAggregateResourceLimits(t *testing.T) {
	data := wireMessage(unix.RTM_NEWROUTE, unix.NLM_F_MULTI, 1, 1, nil)
	state := dump{port: 1, expected: unix.RTM_NEWROUTE, bytes: maxDumpBytes - len(data) + 1}
	if err := state.accept(data); err == nil {
		t.Fatal("byte limit not enforced")
	}
	state = dump{port: 1, expected: unix.RTM_NEWROUTE, count: maxDumpMessages}
	if err := state.accept(data); err == nil {
		t.Fatal("message limit not enforced")
	}
}

func TestNetlinkMessageFramingRejectsTruncationAndOverflow(t *testing.T) {
	data := wireMessage(unix.RTM_NEWLINK, 0, 1, 2, []byte{7})
	for _, invalid := range [][]byte{
		{0}, data[:15], data[:16], data[:18], append(append([]byte(nil), data...), 0),
		append(wireInteger(^uint32(0)), data[4:]...), append(wireInteger(4), data[4:]...),
	} {
		if _, err := parseMessages(invalid); err == nil {
			t.Fatal("malformed message framing accepted")
		}
	}
	// A final message need not include alignment bytes. Any following message
	// must start at the aligned boundary.
	if messages, err := parseMessages(data[:17]); err != nil || len(messages) != 1 {
		t.Fatal("valid unpadded final message rejected", err)
	}
}

func TestNetlinkAttributesValidateLengthsDuplicatesAndEncoding(t *testing.T) {
	valid := wireAttribute(unix.RTA_TABLE, wireInteger(90001))
	attributes, err := parseAttributes(valid)
	if err != nil {
		t.Fatal(err)
	}
	if value, err := uint32Attribute(attributes, unix.RTA_TABLE, 0); err != nil || value != 90001 {
		t.Fatal("wide table ID truncated", err)
	}
	for _, test := range []struct {
		name string
		data []byte
	}{
		{"short-header", []byte{4, 0, 0}},
		{"short-value", valid[:7]},
		{"length-too-small", []byte{3, 0, 0, 0}},
		{"length-too-large", []byte{255, 255, 0, 0}},
		{"short-padding", wireAttribute(1, []byte{1})[:6]},
	} {
		t.Run(test.name, func(t *testing.T) {
			if _, err := parseAttributes(test.data); err == nil {
				t.Fatal("invalid attribute framing accepted")
			}
		})
	}
	for _, invalid := range [][]byte{
		append(append([]byte(nil), valid...), valid...),
		wireAttribute(unix.RTA_TABLE, []byte{1}),
		wireAttribute(unix.RTA_TABLE|unix.NLA_F_NET_BYTEORDER, wireInteger(90001)),
	} {
		attributes, err = parseAttributes(invalid)
		if err != nil {
			t.Fatal(err)
		}
		if _, err = uint32Attribute(attributes, unix.RTA_TABLE, 0); err == nil {
			t.Fatal("invalid integer attribute accepted")
		}
	}
	for _, invalid := range [][]byte{nil, {'x'}, {'x', 0, 'y', 0}, {'x', '\n', 0}} {
		attributes, _ = parseAttributes(wireAttribute(unix.IFLA_IFNAME, invalid))
		if _, err = stringAttribute(attributes, unix.IFLA_IFNAME); err == nil {
			t.Fatal("invalid NUL-terminated string accepted")
		}
	}
}

func TestNetlinkCancellationAndSilentSocketDeadline(t *testing.T) {
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	if _, err := Read(ctx); !errors.Is(err, context.Canceled) {
		t.Fatal("cancelled request started or succeeded", err)
	}
	fds, err := unix.Socketpair(unix.AF_UNIX, unix.SOCK_STREAM|unix.SOCK_CLOEXEC|unix.SOCK_NONBLOCK, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer unix.Close(fds[0])
	defer func() {
		if fds[1] >= 0 {
			_ = unix.Close(fds[1])
		}
	}()
	ctx, cancel = context.WithTimeout(t.Context(), 30*time.Millisecond)
	defer cancel()
	start := time.Now()
	if err = waitReadable(ctx, fds[0]); !errors.Is(err, context.DeadlineExceeded) || time.Since(start) > time.Second {
		t.Fatal("silent socket did not honor deadline", err)
	}
	ctx, cancel = context.WithCancel(t.Context())
	timer := time.AfterFunc(10*time.Millisecond, cancel)
	defer timer.Stop()
	defer cancel()
	if err = waitReadable(ctx, fds[0]); !errors.Is(err, context.Canceled) {
		t.Fatal("pending read ignored cancellation", err)
	}
	closedFD := fds[1]
	if err = unix.Close(closedFD); err != nil {
		t.Fatal(err)
	}
	fds[1] = -1
	if err = waitReadable(t.Context(), closedFD); err == nil {
		t.Fatal("invalid socket falsely became readable")
	}
}

func FuzzNetlinkFraming(f *testing.F) {
	f.Add(wireMessage(unix.RTM_NEWLINK, unix.NLM_F_MULTI, 1, 1, make([]byte, 16)))
	f.Add(wireAttribute(unix.IFLA_IFNAME, []byte("eth0\x00")))
	f.Add([]byte{})
	f.Fuzz(func(t *testing.T, data []byte) {
		_, _ = parseMessages(data)
		_, _ = parseAttributes(data)
		_, _ = parseLink(data)
		_, _ = parseRoute(data)
		_, _ = parseRule(data)
	})
}
