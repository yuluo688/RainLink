package session

import (
	"bytes"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode"
)

const (
	maxBufferedLogs = 2000
	logBatchSize    = 16
	maxLogLineBytes = 8192
	maxLogRunes     = 1024
)

// LogEntry is sanitized before it enters memory, IPC or persistent storage.
type LogEntry struct {
	ID           string `json:"id"`
	Seq          int64  `json:"seq"`
	At           int64  `json:"at"`
	Level        string `json:"level"`
	Source       string `json:"source"`
	Message      string `json:"message"`
	recordedTick int64  // Private common-clock timestamp; never public IPC.
}

// LogBatch uses a host-specific stream and a monotonic cursor across sessions.
type LogBatch struct {
	Stream   string     `json:"stream"`
	Cursor   int64      `json:"cursor"`
	More     bool       `json:"more"`
	Dropped  bool       `json:"dropped"`
	Entries  []LogEntry `json:"entries"`
	clockErr error
}

type logBuffer struct {
	mu          sync.Mutex
	id          string
	seq         int64
	entries     []LogEntry
	clearedTick int64
	clockErr    error
}

func newLogBuffer() *logBuffer { return &logBuffer{id: randomID()} }

func (b *logBuffer) append(level, source, message string) {
	b.mu.Lock()
	defer b.mu.Unlock()
	now := time.Now()
	tick, err := logClockTick()
	if err != nil {
		b.clockErr = err
		return
	}
	b.appendLocked(LogEntry{At: now.UnixMilli(), Level: level, Source: source, Message: message, recordedTick: tick})
}

// appendForwarded preserves the original display time but assigns host-owned IDs.
// The native receiver validates the common kernel clock before this call.
// Pending batches recorded before clear must not reappear as new local events.
func (b *logBuffer) appendForwarded(entry LogEntry) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.clockErr != nil || entry.recordedTick <= b.clearedTick {
		return
	}
	b.appendLocked(entry)
}

func (b *logBuffer) appendLocked(entry LogEntry) {
	b.seq++
	entry.ID, entry.Seq = b.id+":"+strconv.FormatInt(b.seq, 10), b.seq
	cutoff := time.Now().Add(-7 * 24 * time.Hour).UnixMilli()
	start := 0
	for start < len(b.entries) && (b.entries[start].At < cutoff || len(b.entries)-start >= maxBufferedLogs) {
		start++
	}
	if start > 0 {
		b.entries = append([]LogEntry(nil), b.entries[start:]...)
	}
	b.entries = append(b.entries, entry)
}

func (b *logBuffer) read(stream string, after int64) LogBatch {
	b.mu.Lock()
	defer b.mu.Unlock()
	if stream != b.id {
		after = 0
	}
	result := LogBatch{Stream: b.id, Cursor: max(after, b.seq), Entries: []LogEntry{}, clockErr: b.clockErr}
	cutoff := time.Now().Add(-7 * 24 * time.Hour).UnixMilli()
	for _, entry := range b.entries {
		if entry.Seq <= after || entry.At < cutoff {
			continue
		}
		if len(result.Entries) == logBatchSize {
			result.More = true
			break
		}
		result.Entries = append(result.Entries, entry)
		result.Cursor = entry.Seq
	}
	if len(result.Entries) > 0 {
		result.Dropped = result.Entries[0].Seq > after+1
	}
	return result
}

func (b *logBuffer) clear() LogBatch {
	b.mu.Lock()
	defer b.mu.Unlock()
	tick, err := logClockTick()
	if err != nil {
		// Keep existing records and report failure through the ordinary host.
		return LogBatch{clockErr: err}
	}
	b.entries = nil
	b.clearedTick = tick
	b.clockErr = nil
	return LogBatch{Stream: b.id, Cursor: b.seq, Entries: []LogEntry{}}
}

var (
	ansiPattern   = regexp.MustCompile(`\x1b\[[0-9;]*[A-Za-z]`)
	urlPattern    = regexp.MustCompile(`(?i)(?:https?|socks5?|ss|vless|vmess|trojan|hysteria2?|hy2|tuic)://[^\s<>"']+`)
	secretPattern = regexp.MustCompile(`(?i)(?:authorization|proxy-authorization|password|passwd|token|secret|uuid|username|obfs-password|api[_-]?key)["']?\s*[:=]\s*["']?[^\s,;]+`)
	authPattern   = regexp.MustCompile(`(?i)(?:proxy-)?authorization["']?\s*[:=]\s*.*`)
	uuidPattern   = regexp.MustCompile(`(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b`)
	levelPattern  = regexp.MustCompile(`^(TRACE|DEBUG|INFO|WARN|ERROR|FATAL|PANIC)(?:\[[^\]]*\])?\s*`)
)

func safeLogText(message string, secrets []string) string {
	message = ansiPattern.ReplaceAllString(message, "")
	// Replace known authentication values before truncation or regex matching.
	for _, secret := range secrets {
		if secret != "" {
			message = strings.ReplaceAll(message, secret, "[已隐藏]")
		}
	}
	message = urlPattern.ReplaceAllString(message, "[链接已隐藏]")
	message = authPattern.ReplaceAllString(message, "[认证已隐藏]")
	message = secretPattern.ReplaceAllString(message, "[认证已隐藏]")
	message = uuidPattern.ReplaceAllString(message, "[UUID 已隐藏]")
	message = strings.Map(func(r rune) rune {
		if unicode.IsControl(r) {
			return ' '
		}
		return r
	}, message)
	runes := []rune(strings.TrimSpace(message))
	if len(runes) > maxLogRunes {
		return string(runes[:maxLogRunes]) + "…"
	}
	return string(runes)
}

// coreLogWriter bounds partial lines, consumes all output and never blocks on UI.
type coreLogWriter struct {
	mu       sync.Mutex
	buffer   []byte
	overflow bool
	logs     *logBuffer
	secrets  []string
}

func (w *coreLogWriter) Write(data []byte) (int, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	for _, value := range data {
		if value == '\n' {
			w.flush()
		} else if !w.overflow {
			if len(w.buffer) < maxLogLineBytes {
				w.buffer = append(w.buffer, value)
			} else {
				w.overflow = true
				w.buffer = nil
			}
		}
	}
	return len(data), nil
}

func (w *coreLogWriter) flush() {
	if w.overflow {
		w.logs.append("warning", "core", "核心日志行超出长度限制，内容已隐藏")
	} else if len(bytes.TrimSpace(w.buffer)) > 0 {
		line := ansiPattern.ReplaceAllString(string(w.buffer), "")
		level := "info"
		if match := levelPattern.FindStringSubmatch(line); len(match) > 0 {
			switch match[1] {
			case "WARN":
				level = "warning"
			case "ERROR", "FATAL", "PANIC":
				level = "error"
			case "TRACE", "DEBUG":
				level = "debug"
			}
			line = strings.TrimPrefix(line, match[0])
		}
		if message := safeLogText(line, w.secrets); message != "" {
			w.logs.append(level, "core", message)
		}
	}
	w.buffer, w.overflow = nil, false
}

func (w *coreLogWriter) finish() {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.flush()
}
