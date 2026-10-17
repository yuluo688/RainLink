//go:build linux && !android

package linuxipc

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"net"
	"time"
	"unicode/utf8"
)

const (
	// MaxMessageBytes is also the ordinary host's maximum request size.
	MaxMessageBytes = 128 << 10
	frameTimeout    = 10 * time.Second
	maxJSONDepth    = 32
	maxJSONTokens   = 65536
)

// ErrFrame reports invalid framing without including credentials or input text.
var ErrFrame = errors.New("invalid private protocol frame")

// Codec serializes reads and writes independently. Context cancellation wakes
// socket I/O and queued operations. Closing the socket remains the owner's job.
type Codec struct {
	connection net.Conn
	readGate   chan struct{}
	writeGate  chan struct{}
}

// NewCodec wraps a connected private transport without granting authorization.
func NewCodec(connection net.Conn) *Codec {
	return &Codec{connection: connection, readGate: make(chan struct{}, 1), writeGate: make(chan struct{}, 1)}
}

func acquire(ctx context.Context, gate chan struct{}) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	select {
	case gate <- struct{}{}:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func ioDeadline(ctx context.Context, bound bool) time.Time {
	deadline, present := ctx.Deadline()
	if bound {
		limit := time.Now().Add(frameTimeout)
		if !present || limit.Before(deadline) {
			return limit
		}
	}
	return deadline
}

func interrupt(ctx context.Context, setDeadline func(time.Time) error) func() {
	finished := make(chan struct{})
	stop := context.AfterFunc(ctx, func() {
		defer close(finished)
		_ = setDeadline(time.Now())
	})
	return func() {
		if !stop() {
			<-finished
		}
	}
}

func contextIOError(ctx context.Context, err error) error {
	if ctx.Err() != nil {
		return ctx.Err()
	}
	// A socket deadline can wake its waiter before context's timer publishes
	// Err. Preserve the caller's deadline category in that scheduler race.
	var timeout net.Error
	if errors.As(err, &timeout) && timeout.Timeout() {
		if deadline, ok := ctx.Deadline(); ok && !time.Now().Before(deadline) {
			return context.DeadlineExceeded
		}
	}
	return err
}

// Read waits for a frame's first byte until the caller's deadline. Once a frame
// starts, its remaining header and body have a shared ten-second bound, so idle
// sessions remain idle without allowing partial-frame clients to hold the helper.
func (codec *Codec) Read(ctx context.Context) ([]byte, error) {
	if codec == nil || codec.connection == nil {
		return nil, ErrFrame
	}
	if err := acquire(ctx, codec.readGate); err != nil {
		return nil, err
	}
	defer func() { <-codec.readGate }()
	if err := codec.connection.SetReadDeadline(ioDeadline(ctx, false)); err != nil {
		return nil, err
	}
	stop := interrupt(ctx, codec.connection.SetReadDeadline)
	defer stop()
	var header [4]byte
	if _, err := io.ReadFull(codec.connection, header[:1]); err != nil {
		return nil, contextIOError(ctx, err)
	}
	if err := codec.connection.SetReadDeadline(ioDeadline(ctx, true)); err != nil {
		return nil, err
	}
	// Cancellation may have fired between the first read and changing this
	// deadline. Never replace its wakeup with a future deadline and then block.
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if _, err := io.ReadFull(codec.connection, header[1:]); err != nil {
		return nil, contextIOError(ctx, err)
	}
	size := binary.BigEndian.Uint32(header[:])
	if size == 0 || size > MaxMessageBytes {
		return nil, ErrFrame
	}
	data := make([]byte, size)
	if _, err := io.ReadFull(codec.connection, data); err != nil {
		clear(data)
		return nil, contextIOError(ctx, err)
	}
	if err := ctx.Err(); err != nil {
		clear(data)
		return nil, err
	}
	if err := ValidateJSON(data); err != nil {
		clear(data)
		return nil, err
	}
	return data, nil
}

// Write sends one bounded JSON value. A failed partial write makes the stream
// unusable; the session owner must close it and perform ordinary cleanup.
func (codec *Codec) Write(ctx context.Context, value any) error {
	if codec == nil || codec.connection == nil {
		return ErrFrame
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	data, err := json.Marshal(value)
	if err != nil {
		return ErrFrame
	}
	defer clear(data)
	if len(data) > MaxMessageBytes || ValidateJSON(data) != nil {
		return ErrFrame
	}
	if err = acquire(ctx, codec.writeGate); err != nil {
		return err
	}
	defer func() { <-codec.writeGate }()
	if err = codec.connection.SetWriteDeadline(ioDeadline(ctx, true)); err != nil {
		return err
	}
	stop := interrupt(ctx, codec.connection.SetWriteDeadline)
	defer stop()
	if err = ctx.Err(); err != nil {
		return err
	}
	var header [4]byte
	binary.BigEndian.PutUint32(header[:], uint32(len(data)))
	for _, part := range [][]byte{header[:], data} {
		for len(part) != 0 {
			count, err := codec.connection.Write(part)
			if err != nil {
				return contextIOError(ctx, err)
			}
			if count == 0 {
				return io.ErrShortWrite
			}
			part = part[count:]
		}
	}
	return nil
}

// ValidateJSON rejects duplicate decoded keys, invalid UTF-8, trailing values
// and unbounded nesting before a typed controlled-command decoder runs.
// Null remains available for explicitly optional domain fields.
func ValidateJSON(data []byte) error {
	if len(data) == 0 || len(data) > MaxMessageBytes || !utf8.Valid(data) {
		return ErrFrame
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.UseNumber()
	count := 0
	if err := inspectJSON(decoder, 0, &count); err != nil {
		return ErrFrame
	}
	if _, err := decoder.Token(); err != io.EOF {
		return ErrFrame
	}
	return nil
}

func inspectJSON(decoder *json.Decoder, depth int, count *int) error {
	(*count)++
	if depth > maxJSONDepth || *count > maxJSONTokens {
		return ErrFrame
	}
	token, err := decoder.Token()
	if err != nil {
		return err
	}
	opening, container := token.(json.Delim)
	if !container {
		return nil
	}
	closing := json.Delim(']')
	switch opening {
	case '{':
		closing = '}'
		seen := make(map[string]bool)
		for decoder.More() {
			key, err := decoder.Token()
			name, valid := key.(string)
			if err != nil || !valid || seen[name] {
				return ErrFrame
			}
			seen[name] = true
			if err = inspectJSON(decoder, depth+1, count); err != nil {
				return err
			}
		}
	case '[':
		for decoder.More() {
			if err = inspectJSON(decoder, depth+1, count); err != nil {
				return err
			}
		}
	default:
		return ErrFrame
	}
	end, err := decoder.Token()
	if err != nil || end != closing {
		return ErrFrame
	}
	return nil
}
