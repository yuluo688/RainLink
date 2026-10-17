//go:build linux && !android

// Package linuxnet observes kernel network state and provides narrowly scoped,
// acknowledged policy-rule deletion for TUN recovery, without invoking a shell.
package linuxnet

import (
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"time"

	"golang.org/x/sys/unix"
)

const (
	readTimeout       = 2 * time.Second
	pollInterval      = 25 * time.Millisecond
	maxDatagramBytes  = 64 << 10
	maxDumpBytes      = 8 << 20
	maxDumpMessages   = 16384
	netlinkHeaderSize = 16
	attributeTypeMask = 0x3fff
)

// ErrChanged means the kernel could not provide a complete dump during a
// concurrent network change. Callers must discard the entire observation.
var ErrChanged = errors.New("network state changed during netlink dump")

type message struct {
	kind    uint16
	flags   uint16
	seq     uint32
	port    uint32
	payload []byte
}

func align4(size int) int { return (size + 3) &^ 3 }

func parseMessages(data []byte) ([]message, error) {
	var messages []message
	for len(data) != 0 {
		if len(data) < netlinkHeaderSize {
			return nil, errors.New("short netlink header")
		}
		length := uint64(binary.NativeEndian.Uint32(data))
		if length < netlinkHeaderSize || length > uint64(len(data)) {
			return nil, errors.New("invalid netlink message length")
		}
		size := int(length)
		messages = append(messages, message{
			kind: binary.NativeEndian.Uint16(data[4:]), flags: binary.NativeEndian.Uint16(data[6:]),
			seq: binary.NativeEndian.Uint32(data[8:]), port: binary.NativeEndian.Uint32(data[12:]),
			payload: data[netlinkHeaderSize:size],
		})
		if size == len(data) {
			break
		}
		padded := align4(size)
		if padded > len(data) {
			return nil, errors.New("short netlink message padding")
		}
		data = data[padded:]
	}
	return messages, nil
}

type dump struct {
	port     uint32
	expected uint16
	bytes    int
	count    int
	complete bool
	ackOnly  bool
	values   [][]byte
}

func (d *dump) accept(data []byte) error {
	if d.complete {
		return errors.New("netlink data after completion")
	}
	if len(data) > maxDumpBytes-d.bytes {
		return errors.New("netlink dump exceeds byte limit")
	}
	d.bytes += len(data)
	messages, err := parseMessages(data)
	if err != nil {
		return err
	}
	for _, value := range messages {
		d.count++
		if d.count > maxDumpMessages {
			return errors.New("netlink dump exceeds message limit")
		}
		// This socket is neither shared nor subscribed to multicast. Unexpected
		// sequence/port IDs cannot be mixed into a successful observation.
		if d.complete || value.seq != 1 || value.port != d.port {
			return errors.New("unexpected netlink response identity")
		}
		if value.flags&unix.NLM_F_DUMP_INTR != 0 {
			return ErrChanged
		}
		switch value.kind {
		case unix.NLMSG_NOOP:
		case unix.NLMSG_OVERRUN:
			return ErrChanged
		case unix.NLMSG_ERROR, unix.NLMSG_DONE:
			if d.ackOnly && value.kind == unix.NLMSG_DONE {
				return errors.New("netlink completion cannot acknowledge a mutation")
			}
			if len(value.payload) != 0 {
				if len(value.payload) < 4 {
					return errors.New("short netlink result")
				}
				code := int32(binary.NativeEndian.Uint32(value.payload))
				if code < 0 {
					return fmt.Errorf("netlink request rejected: %w", unix.Errno(-int64(code)))
				}
				if code != 0 {
					return errors.New("invalid netlink result")
				}
			} else if value.kind == unix.NLMSG_ERROR {
				return errors.New("empty netlink error")
			}
			d.complete = value.kind == unix.NLMSG_DONE || d.ackOnly
		default:
			if d.ackOnly || value.kind != d.expected {
				return errors.New("unexpected netlink message type")
			}
			d.values = append(d.values, append([]byte(nil), value.payload...))
		}
	}
	return nil
}

func waitReadable(ctx context.Context, fd int) error {
	for {
		if err := ctx.Err(); err != nil {
			return err
		}
		wait := pollInterval
		if deadline, ok := ctx.Deadline(); ok {
			wait = min(wait, time.Until(deadline))
		}
		if wait <= 0 {
			return context.DeadlineExceeded
		}
		fds := []unix.PollFd{{Fd: int32(fd), Events: unix.POLLIN}}
		_, err := unix.Poll(fds, int((wait+time.Millisecond-1)/time.Millisecond))
		if errors.Is(err, unix.EINTR) {
			continue
		}
		if err != nil {
			return fmt.Errorf("poll netlink: %w", err)
		}
		if fds[0].Revents&unix.POLLIN != 0 {
			return nil
		}
		if fds[0].Revents&(unix.POLLERR|unix.POLLHUP|unix.POLLNVAL) != 0 {
			return errors.New("netlink socket closed or overrun")
		}
	}
}

func readDump(ctx context.Context, request uint16, family byte, headerSize int) ([][]byte, error) {
	payload := make([]byte, headerSize)
	payload[0] = family
	return exchange(ctx, request, unix.NLM_F_DUMP, payload, false)
}

func exchange(ctx context.Context, request, flags uint16, payload []byte, ackOnly bool) ([][]byte, error) {
	ctx, cancel := context.WithTimeout(ctx, readTimeout)
	defer cancel()
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	fd, err := unix.Socket(unix.AF_NETLINK, unix.SOCK_RAW|unix.SOCK_CLOEXEC|unix.SOCK_NONBLOCK, unix.NETLINK_ROUTE)
	if err != nil {
		return nil, fmt.Errorf("open netlink: %w", err)
	}
	defer unix.Close(fd)
	if err = unix.Bind(fd, &unix.SockaddrNetlink{Family: unix.AF_NETLINK}); err != nil {
		return nil, fmt.Errorf("bind netlink: %w", err)
	}
	address, err := unix.Getsockname(fd)
	if err != nil {
		return nil, fmt.Errorf("identify netlink socket: %w", err)
	}
	local, ok := address.(*unix.SockaddrNetlink)
	if !ok || local.Pid == 0 {
		return nil, errors.New("invalid netlink socket identity")
	}
	query := make([]byte, netlinkHeaderSize+len(payload))
	binary.NativeEndian.PutUint32(query, uint32(len(query)))
	binary.NativeEndian.PutUint16(query[4:], request)
	binary.NativeEndian.PutUint16(query[6:], unix.NLM_F_REQUEST|flags)
	binary.NativeEndian.PutUint32(query[8:], 1)
	binary.NativeEndian.PutUint32(query[12:], local.Pid)
	copy(query[netlinkHeaderSize:], payload)
	if err = unix.Sendto(fd, query, 0, &unix.SockaddrNetlink{Family: unix.AF_NETLINK}); err != nil {
		return nil, fmt.Errorf("request netlink dump: %w", err)
	}
	state := dump{port: local.Pid, expected: request - 2, ackOnly: ackOnly}
	if ackOnly {
		state.expected = 0 // No data message can substitute for a kernel ACK.
	}
	buffer := make([]byte, maxDatagramBytes)
	for !state.complete {
		if err = waitReadable(ctx, fd); err != nil {
			return nil, err
		}
		n, _, flags, sender, receiveErr := unix.Recvmsg(fd, buffer, nil, 0)
		if errors.Is(receiveErr, unix.EAGAIN) || errors.Is(receiveErr, unix.EINTR) {
			continue
		}
		if receiveErr != nil {
			return nil, fmt.Errorf("receive netlink dump: %w", receiveErr)
		}
		peer, valid := sender.(*unix.SockaddrNetlink)
		if !valid || peer.Pid != 0 || peer.Groups != 0 {
			return nil, errors.New("netlink response is not from the kernel")
		}
		if n == 0 || flags&(unix.MSG_TRUNC|unix.MSG_CTRUNC) != 0 {
			return nil, errors.New("truncated netlink datagram")
		}
		if err = state.accept(buffer[:n]); err != nil {
			return nil, err
		}
	}
	if err = ctx.Err(); err != nil {
		return nil, err
	}
	return state.values, nil
}

// Attribute preserves a kernel attribute, including flags and unknown types.
// Keeping these bytes is necessary for future exact ownership comparisons;
// a policy rule's priority alone is not an ownership identity.
type Attribute struct {
	Type  uint16
	Value []byte
}

func parseAttributes(data []byte) ([]Attribute, error) {
	var attributes []Attribute
	for len(data) != 0 {
		if len(data) < 4 {
			return nil, errors.New("short netlink attribute")
		}
		size := int(binary.NativeEndian.Uint16(data))
		if size < 4 || size > len(data) {
			return nil, errors.New("invalid netlink attribute length")
		}
		attributes = append(attributes, Attribute{Type: binary.NativeEndian.Uint16(data[2:]), Value: append([]byte(nil), data[4:size]...)})
		if size == len(data) {
			break
		}
		padded := align4(size)
		if padded > len(data) {
			return nil, errors.New("short netlink attribute padding")
		}
		data = data[padded:]
	}
	return attributes, nil
}

func findAttribute(attributes []Attribute, kind uint16) (Attribute, bool, error) {
	var selected Attribute
	var found bool
	for _, attribute := range attributes {
		if attribute.Type&attributeTypeMask != kind {
			continue
		}
		if found {
			return Attribute{}, false, errors.New("duplicate netlink attribute")
		}
		selected, found = attribute, true
	}
	return selected, found, nil
}

func uint32Attribute(attributes []Attribute, kind uint16, fallback uint32) (uint32, error) {
	attribute, found, err := findAttribute(attributes, kind)
	if err != nil || !found {
		return fallback, err
	}
	if attribute.Type != kind || len(attribute.Value) != 4 {
		return 0, errors.New("invalid netlink integer attribute")
	}
	return binary.NativeEndian.Uint32(attribute.Value), nil
}

func stringAttribute(attributes []Attribute, kind uint16) (string, error) {
	attribute, found, err := findAttribute(attributes, kind)
	if err != nil || !found {
		return "", err
	}
	if attribute.Type != kind || len(attribute.Value) < 2 || attribute.Value[len(attribute.Value)-1] != 0 {
		return "", errors.New("invalid netlink string attribute")
	}
	for _, value := range attribute.Value[:len(attribute.Value)-1] {
		if value == 0 || value < 0x20 || value == 0x7f {
			return "", errors.New("invalid netlink string value")
		}
	}
	return string(attribute.Value[:len(attribute.Value)-1]), nil
}
