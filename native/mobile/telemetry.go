package mobile

import (
	"encoding/json"
	"errors"

	"rainlink.local/host/mobileconfig"
)

// LogStore retains bounded sanitized events across sessions and activity restarts.
// Session credentials live only in each runtime's writer, never in this store.
type LogStore struct{ logs *mobileconfig.Logs }

// NewLogStore constructs a process-local public log buffer without credentials.
func NewLogStore() *LogStore { return &LogStore{logs: mobileconfig.NewLogs(nil)} }

// Read provides the same cursor protocol while connected and disconnected.
func (s *LogStore) Read(stream string, after int64) (string, error) {
	if len(stream) > 128 || after < 0 || after > 9007199254740991 {
		return "", errors.New("日志游标无效")
	}
	encoded, err := json.Marshal(s.logs.Read(stream, after))
	return string(encoded), err
}

// Clear returns the checkpoint used to keep concurrent new events after clearing.
func (s *LogStore) Clear() (string, error) {
	encoded, err := json.Marshal(s.logs.Clear())
	return string(encoded), err
}

// ReadConnections returns stable pages from the authenticated local core API.
func (r *Runtime) ReadConnections(sessionID, snapshotID string, cursor int32) (string, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if !r.started || r.closed {
		return "", errors.New("当前没有活动连接")
	}
	if len(sessionID) > 128 || len(snapshotID) > 128 {
		return "", errors.New("连接分页参数无效")
	}
	page, err := r.connections.Page(r.ctx, sessionID, snapshotID, int(cursor))
	if err != nil {
		return "", err
	}
	encoded, err := json.Marshal(page)
	return string(encoded), err
}

// CloseConnections checks session ownership and confirms actual stream closure.
func (r *Runtime) CloseConnections(sessionID, connectionID string, all bool) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if !r.started || r.closed {
		return errors.New("当前没有活动连接")
	}
	return r.connections.Close(r.ctx, sessionID, connectionID, all)
}

// ReadTraffic returns public cumulative accounting, never a native configuration.
func (r *Runtime) ReadTraffic(sessionID string) (string, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if !r.started || r.closed {
		return "", errors.New("当前没有活动连接")
	}
	snapshot, err := r.connections.Traffic(r.ctx, sessionID)
	if err != nil {
		return "", err
	}
	encoded, err := json.Marshal(snapshot)
	return string(encoded), err
}
