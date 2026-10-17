//go:build linux && !android

package session

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"reflect"
	"strings"
	"testing"
	"time"

	"rainlink.local/host/internal/linuxipc"
)

func encodePermissionLogEvent(t *testing.T, logs *logBuffer, after int64) []byte {
	t.Helper()
	event, err := permissionLogEvent(logs.read(logs.id, after))
	if err != nil {
		t.Fatal(err)
	}
	data, err := json.Marshal(event)
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func collectPermissionLogMessages(logs *logBuffer) []string {
	var messages []string
	var cursor int64
	for {
		batch := logs.read(logs.id, cursor)
		for _, entry := range batch.Entries {
			messages = append(messages, entry.Message)
		}
		if !batch.More {
			return messages
		}
		cursor = batch.Cursor
	}
}

func TestLinuxTUNLogRedactionAndMonotonicClearBarrier(t *testing.T) {
	root, host := newLogBuffer(), newLogBuffer()
	writer := &coreLogWriter{logs: root, secrets: []string{"fixture-password", "fixture-username"}}
	writer.Write([]byte("ERROR[0001] fragmented fixture-pass"))
	writer.Write([]byte("word; https://fixture-username:fixture-password@example.test/private?token=raw-token\n"))
	writer.Write([]byte("WARN[0002] Authorization: Bearer fixture-bearer\n"))
	writer.Write([]byte(strings.Repeat("x", maxLogLineBytes+1) + "fixture-password\n"))
	writer.Write([]byte("INFO[0003] final partial output"))
	writer.finish()
	receiver := newLinuxTUNLogReceiver(host, MobileRequest{})
	raw := encodePermissionLogEvent(t, root, 0)
	for _, forbidden := range []string{"fixture-password", "fixture-username", "raw-token", "fixture-bearer", "example.test"} {
		if strings.Contains(string(raw), forbidden) {
			t.Fatal("secret entered the permission wire", forbidden)
		}
	}
	if event, err := receiver.receive(raw); err != nil || !event {
		t.Fatal("sanitized event was not ingested", err)
	}
	first := host.read(host.id, 0)
	if len(first.Entries) != 4 || first.Entries[0].Level != "error" || first.Entries[1].Level != "warning" || first.Stream == root.id || !strings.Contains(first.Entries[2].Message, "超出长度") {
		t.Fatal("levels, ownership, line bounds or partial flush lost")
	}
	root.append("info", "core", "queued-before-clear")
	checkpoint := host.clear()
	root.append("info", "core", "recorded-after-clear")
	// Force the display clock in opposite directions. Clear must compare the
	// common kernel clock, not wall time or the batch's eventual arrival time.
	root.mu.Lock()
	root.entries[4].At = time.Now().Add(24 * time.Hour).UnixMilli()
	root.entries[5].At = time.Now().Add(-24 * time.Hour).UnixMilli()
	root.mu.Unlock()
	raw = encodePermissionLogEvent(t, root, receiver.cursor)
	if _, err := receiver.receive(raw); err != nil {
		t.Fatal(err)
	}
	last := host.read(checkpoint.Stream, checkpoint.Cursor)
	if len(last.Entries) != 1 || last.Entries[0].Message != "recorded-after-clear" || receiver.cursor != 6 {
		t.Fatal("queued records replayed after clear or new records were lost")
	}
	if _, err := receiver.receive(raw); err == nil || len(collectPermissionLogMessages(host)) != 1 {
		t.Fatal("duplicate batch replayed")
	}
}

func TestLinuxTUNLogReceiverRejectsInvalidBatchesAtomically(t *testing.T) {
	root := newLogBuffer()
	root.append("info", "core", "first")
	root.append("error", "core", "second")
	base := encodePermissionLogEvent(t, root, 0)
	cases := map[string]func(*linuxTUNLogEvent){
		"version":       func(e *linuxTUNLogEvent) { e.Version++ },
		"event":         func(e *linuxTUNLogEvent) { e.Event = "command" },
		"empty":         func(e *linuxTUNLogEvent) { e.Batch.Entries = nil; e.Ticks = nil },
		"stream":        func(e *linuxTUNLogEvent) { e.Batch.Stream = "invalid" },
		"cursor":        func(e *linuxTUNLogEvent) { e.Batch.Cursor++ },
		"sequence":      func(e *linuxTUNLogEvent) { e.Batch.Entries[1].Seq = 1 },
		"identity":      func(e *linuxTUNLogEvent) { e.Batch.Entries[1].ID = "forged" },
		"level":         func(e *linuxTUNLogEvent) { e.Batch.Entries[1].Level = "execute" },
		"source":        func(e *linuxTUNLogEvent) { e.Batch.Entries[1].Source = "journal" },
		"length":        func(e *linuxTUNLogEvent) { e.Batch.Entries[1].Message = strings.Repeat("界", maxLogRunes+2) },
		"empty-message": func(e *linuxTUNLogEvent) { e.Batch.Entries[1].Message = "" },
		"timestamp":     func(e *linuxTUNLogEvent) { e.Batch.Entries[1].At = -1 },
		"missing-tick":  func(e *linuxTUNLogEvent) { e.Ticks = e.Ticks[:1] },
		"negative-tick": func(e *linuxTUNLogEvent) { e.Ticks[1] = -1 },
		"future-tick":   func(e *linuxTUNLogEvent) { e.Ticks[1] = int64(^uint64(0) >> 1) },
		"false-drop":    func(e *linuxTUNLogEvent) { e.Batch.Dropped = true },
		"batch-size": func(e *linuxTUNLogEvent) {
			for len(e.Batch.Entries) <= logBatchSize {
				e.Batch.Entries = append(e.Batch.Entries, e.Batch.Entries[0])
				e.Ticks = append(e.Ticks, e.Ticks[0])
			}
		},
	}
	for name, mutate := range cases {
		t.Run(name, func(t *testing.T) {
			var event linuxTUNLogEvent
			if err := json.Unmarshal(base, &event); err != nil {
				t.Fatal(err)
			}
			mutate(&event)
			raw, err := json.Marshal(event)
			if err != nil {
				t.Fatal(err)
			}
			host := newLogBuffer()
			receiver := newLinuxTUNLogReceiver(host, MobileRequest{})
			if _, err := receiver.receive(raw); err == nil || receiver.cursor != 0 || len(collectPermissionLogMessages(host)) != 0 {
				t.Fatal("invalid event was ingested or partially committed")
			}
		})
	}
	for name, raw := range map[string]string{
		"unknown":   strings.Replace(string(base), `"ticks":`, `"untrusted":1,"ticks":`, 1),
		"duplicate": strings.Replace(string(base), `"event":`, `"event":"logs","event":`, 1),
		"case":      strings.Replace(string(base), `"source":`, `"Source":`, 1),
	} {
		t.Run(name, func(t *testing.T) {
			receiver := newLinuxTUNLogReceiver(newLogBuffer(), MobileRequest{})
			if _, err := receiver.receive([]byte(raw)); err == nil || receiver.cursor != 0 {
				t.Fatal("invalid raw event accepted")
			}
		})
	}
	var legacy *linuxTUNLogReceiver
	if _, err := legacy.receive(base); err == nil {
		t.Fatal("unsolicited event accepted without opt-in")
	}
	if event, err := legacy.receive([]byte(`{"version":1,"id":3,"result":{"stopped":true}}`)); err != nil || event {
		t.Fatal("ordinary stop receipt was mistaken for logs", err)
	}
	host := newLogBuffer()
	receiver := newLinuxTUNLogReceiver(host, MobileRequest{Secrets: map[string]MobileCredentials{"fixture-cipher": {Password: "fixture-private-value"}}})
	root.append("info", "core", "bare fixture-private-value fixture-cipher")
	if _, err := receiver.receive(encodePermissionLogEvent(t, root, 0)); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(strings.Join(collectPermissionLogMessages(host), " "), "fixture-private-value") {
		t.Fatal("receiver did not apply its own credential redaction")
	}
}

func TestLinuxTUNLogFinalDrainIsBoundedAndReportsDrops(t *testing.T) {
	root, host := newLogBuffer(), newLogBuffer()
	for index := 0; index < maxBufferedLogs+50; index++ {
		root.append("info", "core", fmt.Sprintf("line-%d", index))
	}
	one, two := net.Pipe()
	defer one.Close()
	defer two.Close()
	ctx, cancel := context.WithTimeout(t.Context(), 4*time.Second)
	defer cancel()
	receiver := newLinuxTUNLogReceiver(host, MobileRequest{})
	readDone := make(chan error, 1)
	go func() {
		codec := linuxipc.NewCodec(two)
		for range permissionFinalLogBatches {
			raw, err := codec.Read(ctx)
			if err == nil {
				_, err = receiver.receive(raw)
			}
			if err != nil {
				readDone <- err
				return
			}
		}
		readDone <- nil
	}()
	sender := startLinuxTUNLogs(ctx, linuxipc.NewCodec(one), root, cancel)
	if err := sender.finish(ctx); err != nil {
		t.Fatal(err)
	}
	if err := <-readDone; err != nil {
		t.Fatal(err)
	}
	messages := collectPermissionLogMessages(host)
	if len(messages) != logBatchSize*permissionFinalLogBatches+1 || !strings.Contains(messages[0], "丢弃") || messages[len(messages)-1] != fmt.Sprintf("line-%d", maxBufferedLogs+49) || sender.cursor != int64(maxBufferedLogs+50) {
		t.Fatal("terminal drain lost newest diagnostics, lacked overflow or exceeded its budget")
	}
}

func TestLinuxTUNLogBackpressureDoesNotBlockCoreAndCancelsBrokenStream(t *testing.T) {
	one, two := net.Pipe()
	defer one.Close()
	defer two.Close()
	ctx, cancel := context.WithCancel(t.Context())
	defer cancel()
	root := newLogBuffer()
	root.append("info", "core", "first frame")
	sender := startLinuxTUNLogs(ctx, linuxipc.NewCodec(one), root, cancel)
	defer sender.stop()
	// Read only the first header byte. The sender is now blocked halfway
	// through a frame, while the core must continue consuming stdout/stderr.
	if err := two.SetReadDeadline(time.Now().Add(2 * time.Second)); err != nil {
		t.Fatal(err)
	}
	var header [1]byte
	if _, err := two.Read(header[:]); err != nil {
		t.Fatal(err)
	}
	coreDone := make(chan struct{})
	go func() {
		writer := &coreLogWriter{logs: root}
		for range 500 {
			writer.Write([]byte("INFO[0001] continued real core output\n"))
		}
		writer.finish()
		close(coreDone)
	}()
	select {
	case <-coreDone:
	case <-time.After(500 * time.Millisecond):
		t.Fatal("backpressure from IPC blocked core output")
	}
	select {
	case <-ctx.Done():
	case <-time.After(2 * time.Second):
		t.Fatal("broken log stream did not initiate session recovery")
	}
	if err := sender.finish(t.Context()); err == nil {
		t.Fatal("partial frame was reused for a successful terminal receipt")
	}
}

func TestLinuxTUNLogCancellationJoinsWriter(t *testing.T) {
	one, two := net.Pipe()
	defer one.Close()
	defer two.Close()
	ctx, cancel := context.WithCancel(t.Context())
	root := newLogBuffer()
	root.append("info", "core", "partial frame")
	sender := startLinuxTUNLogs(ctx, linuxipc.NewCodec(one), root, cancel)
	var first [1]byte
	if err := two.SetReadDeadline(time.Now().Add(2 * time.Second)); err != nil {
		t.Fatal(err)
	}
	if _, err := two.Read(first[:]); err != nil {
		t.Fatal(err)
	}
	cancel()
	sender.stop()
	if !errors.Is(sender.err, context.Canceled) {
		t.Fatal("cancelled partial writer lost cancellation", sender.err)
	}
	if !reflect.DeepEqual(collectPermissionLogMessages(root), []string{"partial frame"}) {
		t.Fatal("cancellation mutated the source buffer")
	}
}
