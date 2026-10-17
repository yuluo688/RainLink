package session

import (
	"context"
	"net"
	"net/http"
	"path"
	"regexp"
	"sort"
	"strings"
	"time"
)

const connectionPageSize = 32

var connectionIDPattern = regexp.MustCompile(`^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$`)

// Connection is the public, bounded view of an observed core connection.
type Connection struct {
	ID          string `json:"id"`
	Destination string `json:"destination"`
	Network     string `json:"network"`
	Process     string `json:"process"`
	Rule        string `json:"rule"`
	Outbound    string `json:"outbound"`
	Direct      bool   `json:"direct"`
	Upload      int64  `json:"upload"`
	Download    int64  `json:"download"`
	StartedAt   int64  `json:"startedAt"`
}

// ConnectionPage is stable across pages even while the underlying network moves.
type ConnectionPage struct {
	SessionID     string       `json:"sessionId"`
	SnapshotID    string       `json:"snapshotId"`
	SampledAt     int64        `json:"sampledAt"`
	UploadTotal   int64        `json:"uploadTotal"`
	DownloadTotal int64        `json:"downloadTotal"`
	Total         int          `json:"total"`
	Next          int          `json:"next"`
	Entries       []Connection `json:"entries"`
}

type connectionBatch struct {
	ConnectionPage
	all []Connection
}

type coreConnections struct {
	UploadTotal   int64 `json:"uploadTotal"`
	DownloadTotal int64 `json:"downloadTotal"`
	Connections   []struct {
		ID       string `json:"id"`
		Metadata struct {
			Host            string `json:"host"`
			DestinationIP   string `json:"destinationIP"`
			DestinationPort string `json:"destinationPort"`
			ProcessPath     string `json:"processPath"`
			Network         string `json:"network"`
		} `json:"metadata"`
		Upload   int64     `json:"upload"`
		Download int64     `json:"download"`
		Start    time.Time `json:"start"`
		Chains   []string  `json:"chains"`
		Rule     string    `json:"rule"`
	} `json:"connections"`
}

func limitedText(value string, length int) string {
	runes := []rune(safeLogText(value, nil))
	if len(runes) > length {
		return string(runes[:length]) + "…"
	}
	return string(runes)
}

func (core *runningCore) readConnections(ctx context.Context) (coreConnections, error) {
	var data coreConnections
	if err := core.apiJSON(ctx, http.MethodGet, "/connections", nil, &data); err != nil {
		return data, fail("connections_unavailable", "无法读取核心连接，请重试")
	}
	return data, nil
}

// Connections reads one core snapshot and pages it within the bounded IPC frame.
func (m *Manager) Connections(ctx context.Context, sessionID, snapshotID string, cursor int) (ConnectionPage, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if cursor < 0 || cursor > 100000 {
		return ConnectionPage{}, fail("invalid_request", "连接分页参数无效")
	}
	if m.active == nil {
		if sessionID != "" {
			return ConnectionPage{}, fail("session_changed", "连接会话已结束，请刷新列表")
		}
		return ConnectionPage{Next: -1, Entries: []Connection{}}, nil
	}
	core := m.active
	if sessionID != "" && sessionID != core.snapshot.SessionID {
		return ConnectionPage{}, fail("session_changed", "连接会话已改变，请刷新列表")
	}
	if snapshotID == "" {
		if cursor != 0 {
			return ConnectionPage{}, fail("invalid_request", "连接分页参数无效")
		}
		data, err := core.readConnections(ctx)
		if err != nil {
			return ConnectionPage{}, err
		}
		batch := &connectionBatch{ConnectionPage: ConnectionPage{SessionID: core.snapshot.SessionID,
			SnapshotID: randomID(), SampledAt: time.Now().UnixMilli(), UploadTotal: max(0, data.UploadTotal), DownloadTotal: max(0, data.DownloadTotal)}}
		for _, item := range data.Connections {
			if !connectionIDPattern.MatchString(item.ID) {
				return ConnectionPage{}, fail("invalid_core_response", "核心返回的连接标识无效")
			}
			destination := item.Metadata.Host
			if destination == "" {
				destination = item.Metadata.DestinationIP
			}
			if item.Metadata.DestinationPort != "" {
				destination = net.JoinHostPort(destination, item.Metadata.DestinationPort)
			}
			outbound := ""
			if len(item.Chains) > 0 {
				outbound = item.Chains[0]
			}
			direct := outbound == "direct"
			if name := core.outboundNames[outbound]; name != "" {
				outbound = name
			}
			// A basename is sufficient for attribution; don't expose the user's home path.
			process := path.Base(strings.ReplaceAll(item.Metadata.ProcessPath, `\`, "/"))
			if process == "." {
				process = ""
			}
			batch.all = append(batch.all, Connection{ID: item.ID, Destination: limitedText(destination, 280),
				Network: limitedText(item.Metadata.Network, 8), Process: limitedText(process, 64),
				Rule: limitedText(item.Rule, 128), Outbound: limitedText(outbound, 64), Direct: direct,
				Upload: max(0, item.Upload), Download: max(0, item.Download), StartedAt: item.Start.UnixMilli()})
		}
		sort.Slice(batch.all, func(i, j int) bool {
			if batch.all[i].StartedAt == batch.all[j].StartedAt {
				return batch.all[i].ID < batch.all[j].ID
			}
			return batch.all[i].StartedAt > batch.all[j].StartedAt
		})
		batch.Total = len(batch.all)
		m.connectionsCache = batch
	}
	batch := m.connectionsCache
	if batch == nil || snapshotID != "" && batch.SnapshotID != snapshotID || batch.SessionID != core.snapshot.SessionID || time.Since(time.UnixMilli(batch.SampledAt)) > 30*time.Second || cursor > len(batch.all) {
		return ConnectionPage{}, fail("snapshot_expired", "连接快照已过期，请刷新列表")
	}
	result := batch.ConnectionPage
	end := min(cursor+connectionPageSize, len(batch.all))
	result.Entries = append([]Connection{}, batch.all[cursor:end]...)
	result.Next = -1
	if end < len(batch.all) {
		result.Next = end
	}
	return result, nil
}

// CloseConnections uses a session-scoped ID so stale rows cannot affect a new core.
func (m *Manager) CloseConnections(ctx context.Context, sessionID, connectionID string, all bool) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if sessionID == "" || m.active == nil || m.active.snapshot.SessionID != sessionID {
		return fail("session_changed", "连接会话已改变，请刷新列表")
	}
	if all && connectionID != "" || !all && !connectionIDPattern.MatchString(connectionID) {
		return fail("invalid_request", "连接标识无效")
	}
	endpoint := "/connections"
	if !all {
		endpoint += "/" + connectionID
	}
	core := m.active
	previousIDs := map[string]bool{}
	if all {
		before, err := core.readConnections(ctx)
		if err != nil {
			return err
		}
		for _, item := range before.Connections {
			previousIDs[item.ID] = true
		}
	}
	if err := core.apiJSON(ctx, http.MethodDelete, endpoint, nil, nil); err != nil {
		return fail("close_connection_failed", "核心未确认关闭连接，请重试")
	}
	// DELETE is idempotent; confirm the requested ID has actually disappeared.
	data, err := core.readConnections(ctx)
	if err != nil {
		return fail("close_connection_unconfirmed", "已请求关闭，但无法确认结果，请刷新列表")
	}
	for _, item := range data.Connections {
		if !all && item.ID == connectionID || all && previousIDs[item.ID] {
			return fail("close_connection_unconfirmed", "连接仍在关闭中，请刷新后重试")
		}
	}
	m.logs.append("info", "host", "已关闭连接")
	return nil
}
