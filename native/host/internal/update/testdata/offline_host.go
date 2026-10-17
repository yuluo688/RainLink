//go:build ignore

// A network-free host fixture for the real Flutter updater candidate. It only
// reports an idle session; connection and credential commands are rejected.
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
)

func run() error {
	output := json.NewEncoder(os.Stdout)
	if len(os.Args) != 2 {
		return fmt.Errorf("expected status or serve command")
	}
	if os.Args[1] == "status" {
		return output.Encode(map[string]any{
			"protocolVersion": 1,
			"host":            map[string]any{"version": "qa-offline", "platform": "windows", "arch": "amd64"},
			"core":            map[string]any{"state": "not_configured", "version": nil},
			"capabilities":    map[string]bool{"connect": false, "systemProxy": false, "tun": false},
		})
	}
	if os.Args[1] != "serve" {
		return fmt.Errorf("unsupported fixture command")
	}
	input := bufio.NewScanner(os.Stdin)
	input.Buffer(make([]byte, 4096), 128*1024)
	for input.Scan() {
		var request struct {
			ID     int    `json:"id"`
			Method string `json:"method"`
		}
		if err := json.Unmarshal(input.Bytes(), &request); err != nil {
			return fmt.Errorf("read fixture request: %w", err)
		}
		response := map[string]any{"id": request.ID}
		switch request.Method {
		case "hello":
			response["result"] = map[string]any{"protocolVersion": 2, "coreVersion": "qa-offline"}
		case "snapshot", "disconnect", "cancel":
			response["result"] = map[string]any{"phase": "idle", "error": ""}
		case "logs", "clearLogs":
			response["result"] = map[string]any{
				"stream": "qa-offline", "cursor": 0, "more": false, "dropped": false, "entries": []any{},
			}
		default:
			response["error"] = map[string]string{"code": "unsupported", "message": "Isolated offline fixture"}
		}
		if err := output.Encode(response); err != nil {
			return fmt.Errorf("write fixture response: %w", err)
		}
	}
	return input.Err()
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "offline fixture failed")
		os.Exit(1)
	}
}
