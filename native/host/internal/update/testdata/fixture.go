//go:build ignore

// A disposable process used by updater integration tests. It never opens the
// real RainLink database, listens on network ports, or changes system settings.
package main

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

func main() {
	support := os.Getenv("RAINLINK_UPDATE_FIXTURE_SUPPORT")
	if support == "" {
		os.Exit(20)
	}
	health, token := "", ""
	for _, argument := range os.Args[1:] {
		if strings.HasPrefix(argument, "--rainlink-update-health=") {
			health = strings.TrimPrefix(argument, "--rainlink-update-health=")
		}
		if strings.HasPrefix(argument, "--rainlink-update-token=") {
			token = strings.TrimPrefix(argument, "--rainlink-update-token=")
		}
	}
	if health == "" {
		if len(os.Args) > 1 && os.Args[1] == "--wait" {
			os.WriteFile(filepath.Join(support, "parent-ready"), []byte("ready"), 0600)
			bufio.NewReader(os.Stdin).ReadString('\n')
			return
		}
		os.WriteFile(filepath.Join(support, "previous-restarted"), []byte("ready"), 0600)
		return
	}
	// Emulate a migration that must be rolled back on startup failure.
	os.WriteFile(filepath.Join(support, "rainlink.sqlite"), []byte("candidate-database"), 0600)
	os.WriteFile(filepath.Join(support, "rainlink.sqlite-wal"), []byte("candidate-wal"), 0600)
	os.WriteFile(filepath.Join(support, "candidate-pid"), []byte(strconv.Itoa(os.Getpid())), 0600)
	if _, err := os.Stat(filepath.Join(support, "hold-before-ready")); err == nil {
		for attempt := 0; attempt < 600; attempt++ {
			if _, err := os.Stat(filepath.Join(support, "continue-ready")); err == nil {
				break
			}
			time.Sleep(50 * time.Millisecond)
		}
	}
	if _, err := os.Stat(filepath.Join(support, "fail-start")); err == nil {
		os.Exit(21)
	}
	data, err := os.ReadFile(filepath.Join(health, "request.json"))
	if err != nil {
		os.Exit(22)
	}
	var request struct {
		Version string `json:"version"`
	}
	if json.Unmarshal(data, &request) != nil {
		os.Exit(23)
	}
	data, _ = json.Marshal(map[string]any{"token": token, "version": request.Version, "pid": os.Getpid()})
	temporary := filepath.Join(health, "ready.partial")
	if os.WriteFile(temporary, data, 0600) != nil || os.Rename(temporary, filepath.Join(health, "ready.json")) != nil {
		os.Exit(24)
	}
	for attempt := 0; attempt < 600; attempt++ {
		if _, err := os.Stat(filepath.Join(health, "accepted.json")); err == nil {
			os.WriteFile(filepath.Join(support, "candidate-accepted"), []byte("ready"), 0600)
			if _, err := os.Stat(filepath.Join(support, "hold-before-consumed")); err == nil {
				for attempt := 0; attempt < 600; attempt++ {
					if _, err := os.Stat(filepath.Join(support, "continue-consumed")); err == nil {
						break
					}
					time.Sleep(50 * time.Millisecond)
				}
			}
			if os.WriteFile(filepath.Join(health, "consumed"), []byte(token), 0600) != nil {
				os.Exit(25)
			}
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	os.Exit(26)
}
