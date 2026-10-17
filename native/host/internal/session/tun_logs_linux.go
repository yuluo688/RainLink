//go:build linux && !android

package session

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"strconv"
	"sync"
	"time"
	"unicode/utf8"

	"rainlink.local/host/internal/linuxipc"
)

const (
	permissionLogHello        = "hello-logs"
	permissionLogInterval     = 100 * time.Millisecond
	permissionLogWriteTimeout = time.Second
	permissionFinalLogBatches = 2
)

// Opt-in keeps v1 hello/start clients free of unsolicited frames. No journal,
// shared file or other user's buffer is read. Ticks use the kernel's common
// CLOCK_MONOTONIC, so clear remains correct when the wall clock changes.
type linuxTUNLogEvent struct {
	Version int      `json:"version"`
	Event   string   `json:"event"`
	Batch   LogBatch `json:"batch"`
	Ticks   []int64  `json:"ticks"`
}

func permissionStageFailure(stage string, err error) string {
	if errors.Is(err, linuxipc.ErrPermissionDenied) {
		return "TUN 系统授权已取消，未启用网络接管"
	}
	if errors.Is(err, linuxipc.ErrAuthorizationUnavailable) {
		return "TUN 系统授权不可用，请检查 polkit 与桌面认证服务"
	}
	if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
		return "TUN 启动已取消或超时，正在清理本次会话"
	}
	labels := map[string]string{
		"authorization": "系统授权", "trusted-binaries": "权限程序校验", "watchdog": "恢复保护",
		"resource-lease": "网络资源申请", "compiler": "配置生成", "core-validation": "核心配置校验",
		"core-start": "核心启动", "core-binding": "核心恢复登记", "core-input": "配置传递",
		"api-readiness": "核心接口就绪检查", "capture-readiness": "网卡与路由就绪检查",
	}
	label, exists := labels[stage]
	if !exists {
		label = "权限服务"
	}
	return "TUN 启动失败：" + label + "。请检查核心日志与权限服务状态"
}

func permissionLogEvent(batch LogBatch) (linuxTUNLogEvent, error) {
	if batch.clockErr != nil {
		return linuxTUNLogEvent{}, batch.clockErr
	}
	event := linuxTUNLogEvent{Version: linuxipc.ProtocolVersion, Event: "logs", Batch: batch, Ticks: make([]int64, len(batch.Entries))}
	for index, entry := range batch.Entries {
		if entry.recordedTick <= 0 {
			return linuxTUNLogEvent{}, errors.New("permission log timestamp missing")
		}
		event.Ticks[index] = entry.recordedTick
	}
	return event, nil
}

type linuxTUNLogSender struct {
	codec  *linuxipc.Codec
	logs   *logBuffer
	ctx    context.Context
	cancel context.CancelFunc
	quit   chan struct{}
	done   chan struct{}
	once   sync.Once
	cursor int64
	err    error // Written by the sender; read only after done closes.
}

func startLinuxTUNLogs(ctx context.Context, codec *linuxipc.Codec, logs *logBuffer, cancel context.CancelFunc) *linuxTUNLogSender {
	sender := &linuxTUNLogSender{codec: codec, logs: logs, ctx: ctx, cancel: cancel, quit: make(chan struct{}), done: make(chan struct{})}
	go sender.run()
	return sender
}

func (sender *linuxTUNLogSender) run() {
	defer close(sender.done)
	ticker := time.NewTicker(permissionLogInterval)
	defer ticker.Stop()
	for {
		select {
		case <-sender.ctx.Done():
			return
		case <-sender.quit:
			return
		case <-ticker.C:
			if err := sender.flush(sender.ctx, false); err != nil {
				sender.err = err
				// A partial frame cannot be reused for a stop receipt. Closing the
				// session starts recovery independently of this blocked log stream.
				sender.cancel()
				return
			}
		}
	}
}

func (sender *linuxTUNLogSender) stop() {
	if sender == nil {
		return
	}
	sender.once.Do(func() { close(sender.quit) })
	<-sender.done
}

func (sender *linuxTUNLogSender) flush(ctx context.Context, final bool) error {
	after := sender.cursor
	if final {
		sender.logs.mu.Lock()
		// Terminal diagnostics have a fixed drain budget. Keep the newest tail
		// rather than delaying resource restoration for an arbitrary backlog.
		after = max(after, sender.logs.seq-int64(logBatchSize*permissionFinalLogBatches))
		sender.logs.mu.Unlock()
	}
	count := 1
	if final {
		count = permissionFinalLogBatches
	}
	for range count {
		batch := sender.logs.read(sender.logs.id, after)
		if batch.clockErr != nil {
			return batch.clockErr
		}
		if len(batch.Entries) == 0 {
			return nil
		}
		batch.Dropped = batch.Entries[0].Seq > sender.cursor+1
		event, err := permissionLogEvent(batch)
		if err != nil {
			return err
		}
		write, cancel := context.WithTimeout(ctx, permissionLogWriteTimeout)
		err = sender.codec.Write(write, event)
		cancel()
		if err != nil {
			return err
		}
		sender.cursor, after = batch.Cursor, batch.Cursor
		if !batch.More {
			return nil
		}
	}
	return nil
}

func (sender *linuxTUNLogSender) finish(ctx context.Context) error {
	if sender == nil {
		return nil
	}
	sender.stop()
	if sender.err != nil {
		return sender.err
	}
	drain, cancel := context.WithTimeout(ctx, permissionFinalLogBatches*permissionLogWriteTimeout)
	defer cancel()
	return sender.flush(drain, true)
}

type linuxTUNLogReceiver struct {
	logs    *logBuffer
	secrets []string
	stream  string
	cursor  int64
}

func newLinuxTUNLogReceiver(logs *logBuffer, request MobileRequest) *linuxTUNLogReceiver {
	if logs == nil {
		return nil
	}
	receiver := &linuxTUNLogReceiver{logs: logs}
	for key, auth := range request.Secrets {
		receiver.secrets = append(receiver.secrets, key, auth.Username, auth.Password, auth.ObfsPassword)
	}
	return receiver
}

func exactLogFields(raw json.RawMessage, names ...string) bool {
	var fields map[string]json.RawMessage
	if json.Unmarshal(raw, &fields) != nil || len(fields) != len(names) {
		return false
	}
	for _, name := range names {
		if _, exists := fields[name]; !exists {
			return false
		}
	}
	return true
}

func validPermissionLogStream(stream string) bool {
	if len(stream) < 16 || len(stream) > 64 {
		return false
	}
	for _, value := range stream {
		if !(value >= 'a' && value <= 'z' || value >= 'A' && value <= 'Z' || value >= '0' && value <= '9' || value == '-' || value == '_') {
			return false
		}
	}
	return true
}

// receive returns false for an ordinary reply. It validates the entire batch
// before ingesting anything and advances its private cursor even when clear
// suppresses old buffered events. Public IDs always come from the local host.
func (receiver *linuxTUNLogReceiver) receive(raw []byte) (bool, error) {
	if linuxipc.ValidateJSON(raw) != nil {
		return false, linuxipc.ErrFrame
	}
	var fields map[string]json.RawMessage
	if json.Unmarshal(raw, &fields) != nil {
		return false, linuxipc.ErrFrame
	}
	if _, exists := fields["event"]; !exists {
		return false, nil
	}
	if receiver == nil || !exactLogFields(raw, "version", "event", "batch", "ticks") ||
		!exactLogFields(fields["batch"], "stream", "cursor", "more", "dropped", "entries") {
		return true, linuxipc.ErrFrame
	}
	var event linuxTUNLogEvent
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if decoder.Decode(&event) != nil || event.Version != linuxipc.ProtocolVersion || event.Event != "logs" {
		return true, linuxipc.ErrFrame
	}
	batch := event.Batch
	if !validPermissionLogStream(batch.Stream) || receiver.stream != "" && receiver.stream != batch.Stream ||
		len(batch.Entries) == 0 || len(batch.Entries) > logBatchSize || len(event.Ticks) != len(batch.Entries) || batch.Cursor <= receiver.cursor {
		return true, linuxipc.ErrFrame
	}
	var batchFields map[string]json.RawMessage
	var rawEntries []json.RawMessage
	if json.Unmarshal(fields["batch"], &batchFields) != nil || json.Unmarshal(batchFields["entries"], &rawEntries) != nil {
		return true, linuxipc.ErrFrame
	}
	tick, err := logClockTick()
	if err != nil {
		return true, err
	}
	last := receiver.cursor
	for index, entry := range batch.Entries {
		if !exactLogFields(rawEntries[index], "id", "seq", "at", "level", "source", "message") ||
			entry.Seq <= last || (index > 0 && entry.Seq != last+1) || entry.ID != batch.Stream+":"+strconv.FormatInt(entry.Seq, 10) ||
			entry.At <= 0 || entry.At > 253402300799999 || entry.Message == "" || !utf8.ValidString(entry.Message) || utf8.RuneCountInString(entry.Message) > maxLogRunes+1 ||
			event.Ticks[index] <= 0 || event.Ticks[index] > tick {
			return true, linuxipc.ErrFrame
		}
		switch entry.Level {
		case "debug", "info", "warning", "error":
		default:
			return true, linuxipc.ErrFrame
		}
		if entry.Source != "core" && entry.Source != "host" {
			return true, linuxipc.ErrFrame
		}
		last = entry.Seq
	}
	if last != batch.Cursor || batch.Dropped != (batch.Entries[0].Seq > receiver.cursor+1) {
		return true, linuxipc.ErrFrame
	}
	for index, entry := range batch.Entries {
		if index == 0 && batch.Dropped {
			receiver.logs.appendForwarded(LogEntry{At: entry.At, Level: "warning", Source: "host", Message: "权限核心日志缓冲已满，部分记录已丢弃", recordedTick: event.Ticks[index]})
		}
		entry.Message = safeLogText(entry.Message, receiver.secrets)
		entry.recordedTick = event.Ticks[index]
		if entry.Message != "" {
			receiver.logs.appendForwarded(entry)
		}
	}
	receiver.stream, receiver.cursor = batch.Stream, batch.Cursor
	return true, nil
}
