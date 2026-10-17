//go:build linux && !android

package linuxipc

import (
	"encoding/json"
	"errors"
)

// ProtocolVersion is independent of the ordinary host's Flutter protocol.
const ProtocolVersion = 1

// Command is the small permission-service contract. A start payload contains
// domain data for the controlled compiler, never a core path or raw core JSON.
type Command struct {
	Version int             `json:"version"`
	ID      int             `json:"id"`
	Method  string          `json:"method"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

// ErrCommand contains no input text and must not be supplemented with raw JSON.
var ErrCommand = errors.New("invalid permission service command")

// ParseCommand accepts exact envelope field names and a fixed method list.
// Callers must additionally enforce increasing IDs and session state.
func ParseCommand(raw []byte) (Command, error) {
	var command Command
	if ValidateJSON(raw) != nil {
		return command, ErrCommand
	}
	var fields map[string]json.RawMessage
	if json.Unmarshal(raw, &fields) != nil || fields == nil {
		return command, ErrCommand
	}
	for name := range fields {
		switch name {
		case "version", "id", "method", "payload":
		default:
			return command, ErrCommand
		}
	}
	if json.Unmarshal(raw, &command) != nil || command.Version != ProtocolVersion || command.ID < 1 || command.ID > 0x7fffffff {
		return Command{}, ErrCommand
	}
	switch command.Method {
	case "start":
		var payload map[string]json.RawMessage
		if json.Unmarshal(command.Payload, &payload) != nil || len(payload) == 0 {
			return Command{}, ErrCommand
		}
	case "stop", "idle", "hello", "hello-logs":
		if len(command.Payload) != 0 {
			return Command{}, ErrCommand
		}
	default:
		return Command{}, ErrCommand
	}
	return command, nil
}

// Reply carries either a private native result or a fixed, public error code.
// API credentials in a successful start result must never reach the UI or logs.
type Reply struct {
	Version int    `json:"version"`
	ID      int    `json:"id"`
	Result  any    `json:"result,omitempty"`
	Error   string `json:"error,omitempty"`
}
