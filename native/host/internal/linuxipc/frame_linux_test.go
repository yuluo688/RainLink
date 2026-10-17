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
	"strings"
	"sync"
	"testing"
	"time"
)

func TestJSONBoundaryRejectsAmbiguityWithoutEchoingSecrets(t *testing.T) {
	for name, raw := range map[string][]byte{
		"empty":             nil,
		"duplicate":         []byte(`{"password":"fixture-secret","password":"other"}`),
		"escaped-duplicate": []byte(`{"\u0074un":true,"tun":false}`),
		"nested-duplicate":  []byte(`{"node":{"port":80,"port":443}}`),
		"trailing":          []byte(`{} {}`),
		"trailing-junk":     []byte(`{} fixture-secret`),
		"broken":            []byte(`{"password":"fixture-secret"`),
		"utf8":              {'"', 0xff, '"'},
		"depth":             []byte(strings.Repeat("[", maxJSONDepth+1) + "0" + strings.Repeat("]", maxJSONDepth+1)),
		"size":              bytes.Repeat([]byte(" "), MaxMessageBytes+1),
	} {
		t.Run(name, func(t *testing.T) {
			err := ValidateJSON(raw)
			if !errors.Is(err, ErrFrame) || strings.Contains(err.Error(), "fixture-secret") {
				t.Fatal("invalid request was accepted or echoed", err)
			}
		})
	}
	// Ciphertext map keys are case sensitive. Separate objects may reuse keys.
	for _, raw := range []string{`{"secrets":{"Ab":null,"ab":null}}`, `[{"x":1},{"x":2}]`, `null`, `{"name":"节点"}`} {
		if err := ValidateJSON([]byte(raw)); err != nil {
			t.Fatal("valid JSON was rejected", err)
		}
	}
	boundary := []byte(`"` + strings.Repeat("x", MaxMessageBytes-2) + `"`)
	if err := ValidateJSON(boundary); err != nil {
		t.Fatal("maximum size frame was rejected", err)
	}
}

func pipeCodecs(t *testing.T) (*Codec, *Codec) {
	t.Helper()
	left, right := net.Pipe()
	t.Cleanup(func() { _ = left.Close(); _ = right.Close() })
	return NewCodec(left), NewCodec(right)
}

func TestCodecConcurrentFramesRemainWhole(t *testing.T) {
	writer, reader := pipeCodecs(t)
	ctx, cancel := context.WithTimeout(t.Context(), 3*time.Second)
	defer cancel()
	const total = 32
	errorsOut := make(chan error, total)
	var group sync.WaitGroup
	for index := range total {
		group.Add(1)
		go func() { defer group.Done(); errorsOut <- writer.Write(ctx, map[string]int{"index": index}) }()
	}
	seen := make(map[int]bool)
	for range total {
		raw, err := reader.Read(ctx)
		if err != nil {
			t.Fatal(err)
		}
		var message struct {
			Index int `json:"index"`
		}
		if err = json.Unmarshal(raw, &message); err != nil || seen[message.Index] {
			t.Fatal("frames interleaved", err)
		}
		seen[message.Index] = true
	}
	group.Wait()
	close(errorsOut)
	for err := range errorsOut {
		if err != nil {
			t.Fatal(err)
		}
	}
	if len(seen) != total {
		t.Fatal("frames lost")
	}
}

func TestCodecIdleCancellationDoesNotPoisonNextRead(t *testing.T) {
	writer, reader := pipeCodecs(t)
	for range 50 {
		ctx, cancel := context.WithCancel(t.Context())
		done := make(chan error, 1)
		go func() { _, err := reader.Read(ctx); done <- err }()
		cancel()
		if err := <-done; !errors.Is(err, context.Canceled) {
			t.Fatal("idle cancellation failed", err)
		}
		ctx, finish := context.WithTimeout(t.Context(), time.Second)
		write := make(chan error, 1)
		go func() { write <- writer.Write(ctx, map[string]bool{"ok": true}) }()
		raw, err := reader.Read(ctx)
		writeErr := <-write
		finish()
		if err != nil || writeErr != nil || string(raw) != `{"ok":true}` {
			t.Fatal("cancelled deadline poisoned the next read", err, writeErr)
		}
	}
}

func TestCodecQueuedOperationsCancelAndPartialFramesAreBounded(t *testing.T) {
	for _, operation := range []string{"read", "write"} {
		t.Run(operation, func(t *testing.T) {
			codec, _ := pipeCodecs(t)
			gate := codec.readGate
			if operation == "write" {
				gate = codec.writeGate
			}
			gate <- struct{}{}
			ctx, cancel := context.WithTimeout(t.Context(), 10*time.Millisecond)
			defer cancel()
			var err error
			if operation == "read" {
				_, err = codec.Read(ctx)
			} else {
				err = codec.Write(ctx, true)
			}
			<-gate
			if !errors.Is(err, context.DeadlineExceeded) {
				t.Fatal("queued operation ignored cancellation", err)
			}
		})
	}
	for name, data := range map[string][]byte{
		"zero": {0, 0, 0, 0}, "too-large": {0, 2, 0, 1},
		"header": {0, 0}, "body": {0, 0, 0, 3, '{'},
		"bad-json": {0, 0, 0, 2, 'x', 'x'},
	} {
		t.Run(name, func(t *testing.T) {
			left, right := net.Pipe()
			defer left.Close()
			defer right.Close()
			go func() { _, _ = right.Write(data); _ = right.Close() }()
			ctx, cancel := context.WithTimeout(t.Context(), time.Second)
			defer cancel()
			if raw, err := NewCodec(left).Read(ctx); err == nil || raw != nil {
				t.Fatal("invalid frame returned data")
			}
		})
	}
	left, right := net.Pipe()
	defer left.Close()
	defer right.Close()
	go func() { _, _ = right.Write([]byte{0}) }()
	ctx, cancel := context.WithTimeout(t.Context(), 20*time.Millisecond)
	defer cancel()
	if raw, err := NewCodec(left).Read(ctx); !errors.Is(err, context.DeadlineExceeded) || raw != nil {
		t.Fatal("partial header ignored its deadline", err)
	}
	ctx, cancelWrite := context.WithTimeout(t.Context(), 20*time.Millisecond)
	defer cancelWrite()
	if err := NewCodec(left).Write(ctx, true); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal("blocked writer ignored its deadline", err)
	}
}

type deadlineConn struct {
	net.Conn
	readDeadlines []time.Time
}

func (connection *deadlineConn) SetReadDeadline(deadline time.Time) error {
	connection.readDeadlines = append(connection.readDeadlines, deadline)
	return connection.Conn.SetReadDeadline(deadline)
}

func TestCodecIdleHasNoPeriodicDeadlineAndFrameHasOneSharedLimit(t *testing.T) {
	left, right := net.Pipe()
	defer left.Close()
	defer right.Close()
	connection := &deadlineConn{Conn: left}
	write := make(chan error, 1)
	go func() { write <- NewCodec(right).Write(t.Context(), true) }()
	before := time.Now()
	if _, err := NewCodec(connection).Read(context.Background()); err != nil {
		t.Fatal(err)
	}
	if err := <-write; err != nil {
		t.Fatal(err)
	}
	if len(connection.readDeadlines) != 2 || !connection.readDeadlines[0].IsZero() ||
		connection.readDeadlines[1].Before(before.Add(frameTimeout)) || connection.readDeadlines[1].After(time.Now().Add(frameTimeout)) {
		t.Fatal("idle or shared frame deadline changed", connection.readDeadlines)
	}
}

func TestCodecRejectsOversizeOutputAndReadsSplitWireFrame(t *testing.T) {
	writer, reader := pipeCodecs(t)
	for _, value := range []any{make(chan int), json.RawMessage(`{"x":1,"x":2}`), strings.Repeat("x", MaxMessageBytes)} {
		if err := writer.Write(t.Context(), value); !errors.Is(err, ErrFrame) {
			t.Fatal("invalid output was accepted", err)
		}
	}
	ctx, cancel := context.WithTimeout(t.Context(), time.Second)
	defer cancel()
	done := make(chan error, 1)
	go func() {
		payload := []byte(`{"节点":"香港"}`)
		var header [4]byte
		binary.BigEndian.PutUint32(header[:], uint32(len(payload)))
		for _, one := range append(header[:], payload...) {
			if _, err := writer.connection.Write([]byte{one}); err != nil {
				done <- err
				return
			}
		}
		done <- nil
	}()
	raw, err := reader.Read(ctx)
	if err != nil || string(raw) != `{"节点":"香港"}` {
		t.Fatal("split wire frame failed", err)
	}
	if err = <-done; err != nil {
		t.Fatal(err)
	}
	if _, err = (*Codec)(nil).Read(ctx); !errors.Is(err, ErrFrame) {
		t.Fatal(err)
	}
	if err = (*Codec)(nil).Write(ctx, true); !errors.Is(err, ErrFrame) {
		t.Fatal(err)
	}
	_ = writer.connection.Close()
	if _, err = reader.Read(ctx); !errors.Is(err, io.ErrClosedPipe) {
		t.Fatal("closed pipe error not surfaced", err)
	}
}
