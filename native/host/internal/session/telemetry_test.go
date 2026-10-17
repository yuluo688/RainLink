package session

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestCoreLogFramingRedactionAndBounds(t *testing.T) {
	logs := newLogBuffer()
	writer := &coreLogWriter{logs: logs, secrets: []string{"fixture-password", "fixture-user"}}
	writer.Write([]byte("\x1b[31mERROR[0001]\x1b[0m password=fixture-"))
	writer.Write([]byte("password https://fixture-user:fixture-password@example.test/api/private-token?token=secret\n"))
	writer.Write([]byte("INFO[0002] Authorization: Bearer raw-bearer-token\n"))
	writer.Write([]byte("WARN[0003] UUID=00000000-0000-0000-0000-000000000001\n"))
	writer.Write([]byte(strings.Repeat("a", maxLogLineBytes+200) + "fixture-password\n"))
	writer.Write([]byte("INFO[0004] final partial line"))
	writer.finish()
	batch := logs.read("", 0)
	if len(batch.Entries) != 5 || batch.Entries[0].Level != "error" || batch.Entries[2].Level != "warning" {
		t.Fatalf("incorrect framing or level: %+v", batch)
	}
	encoded, _ := json.Marshal(batch)
	for _, forbidden := range []string{"fixture-password", "fixture-user", "private-token", "raw-bearer-token", "00000000-0000", "\x1b"} {
		if strings.Contains(string(encoded), forbidden) {
			t.Fatalf("sensitive output crossed boundary: %q", forbidden)
		}
	}
	if !strings.Contains(batch.Entries[3].Message, "超出长度") {
		t.Fatal("oversized line was partially exposed")
	}
	for i := 0; i < maxBufferedLogs+10; i++ {
		logs.append("info", "core", "actual event")
	}
	if len(logs.entries) != maxBufferedLogs {
		t.Fatal("unbounded log memory")
	}
	batch = logs.read(logs.id, 1)
	if len(batch.Entries) != logBatchSize || !batch.More || !batch.Dropped {
		t.Fatal("missing overflow or continuation signal")
	}
	checkpoint := logs.clear()
	logs.append("info", "core", "after clear")
	batch = logs.read(checkpoint.Stream, checkpoint.Cursor)
	if len(batch.Entries) != 1 || batch.Entries[0].Message != "after clear" {
		t.Fatal("clear cursor discarded new events or replayed old events")
	}
}

func TestConnectionPaginationAndSessionScopedClosing(t *testing.T) {
	var mu sync.Mutex
	var entries []map[string]any
	for i := 0; i < 70; i++ {
		entries = append(entries, map[string]any{"id": fmt.Sprintf("00000000-0000-0000-0000-%012d", i),
			"metadata": map[string]any{"host": "example.test", "destinationPort": "443", "network": "tcp", "processPath": `C:\Users\private-user\browser.exe`},
			"upload":   100, "download": 200, "start": time.Now().UTC(), "chains": []string{"direct"}, "rule": "ip_is_private=true => direct"})
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		defer mu.Unlock()
		if r.Header.Get("Authorization") != "Bearer fixture-secret" {
			http.Error(w, "unauthorized", 401)
			return
		}
		if r.Method == http.MethodDelete {
			if r.URL.Path == "/connections" {
				entries = nil
			} else {
				id := strings.TrimPrefix(r.URL.Path, "/connections/")
				var remaining []map[string]any
				for _, entry := range entries {
					if entry["id"] != id {
						remaining = append(remaining, entry)
					}
				}
				entries = remaining
			}
			w.WriteHeader(204)
			return
		}
		json.NewEncoder(w).Encode(map[string]any{"connections": entries, "uploadTotal": 7000, "downloadTotal": 14000})
	}))
	defer server.Close()
	manager := New("", t.TempDir())
	manager.active = &runningCore{api: server.URL, secret: "fixture-secret", client: server.Client(), snapshot: Snapshot{SessionID: "session-A"}}
	ctx := context.Background()
	page, err := manager.Connections(ctx, "session-A", "", 0)
	if err != nil || len(page.Entries) != connectionPageSize || page.Total != 70 || page.Next != 32 {
		t.Fatalf("first page: %+v, %v", page, err)
	}
	if page.Entries[0].Process != "browser.exe" || !page.Entries[0].Direct {
		t.Fatal("attribution or direct routing incorrect")
	}
	for _, entry := range page.Entries {
		if entry.Upload != 100 || entry.Download != 200 {
			t.Fatal("counter lost")
		}
	}
	firstID := page.Entries[0].ID
	snapshotID := page.SnapshotID
	mu.Lock()
	entries = entries[:10]
	mu.Unlock()
	page, err = manager.Connections(ctx, "session-A", snapshotID, 32)
	if err != nil || page.Total != 70 || len(page.Entries) != 32 {
		t.Fatal("pagination was not a stable snapshot")
	}
	page, err = manager.Connections(ctx, "session-A", snapshotID, 64)
	if err != nil || len(page.Entries) != 6 || page.Next != -1 {
		t.Fatal("last page incorrect")
	}
	if _, err = manager.Connections(ctx, "session-B", "", 0); err == nil {
		t.Fatal("stale session accepted")
	}
	if err = manager.CloseConnections(ctx, "session-B", firstID, false); err == nil {
		t.Fatal("stale close accepted")
	}
	if err = manager.CloseConnections(ctx, "session-A", "../configs", false); err == nil {
		t.Fatal("path injection accepted")
	}
	if err = manager.CloseConnections(ctx, "session-A", firstID, false); err != nil {
		t.Fatal(err)
	}
	if err = manager.CloseConnections(ctx, "session-A", "", true); err != nil {
		t.Fatal(err)
	}
	page, err = manager.Connections(ctx, "session-A", "", 0)
	if err != nil || page.Total != 0 {
		t.Fatal("closed connections persisted")
	}
}

func TestRealCoreConnectionCloseAndLogCollection(t *testing.T) {
	corePath := testCore(t)
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
		io.WriteString(w, "stream started\n")
		w.(http.Flusher).Flush()
		<-r.Context().Done()
	}))
	defer origin.Close()
	manager := New(corePath, t.TempDir())
	defer func() {
		if err := manager.Disconnect(); err != nil {
			t.Error(err)
		}
	}()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	snapshot, err := manager.Connect(ctx, Node{ID: "telemetry-test", Name: "local direct fixture", Revision: 1,
		Protocol: "http", Server: "127.0.0.1", Port: 9}, "direct", false)
	if err != nil {
		t.Fatal(err)
	}
	manager.active.cancelProbe()
	proxy, _ := url.Parse(fmt.Sprintf("http://127.0.0.1:%d", snapshot.ProxyPort))
	client := &http.Client{Transport: &http.Transport{Proxy: http.ProxyURL(proxy), DisableKeepAlives: true}}
	defer client.CloseIdleConnections()
	response, err := client.Get(origin.URL)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	page, err := manager.Connections(ctx, snapshot.SessionID, "", 0)
	if err != nil {
		t.Fatal(err)
	}
	var id string
	for _, entry := range page.Entries {
		if strings.Contains(entry.Destination, strings.TrimPrefix(origin.URL, "http://")) {
			id = entry.ID
			if !entry.Direct {
				t.Fatal("direct connection classified as proxy")
			}
		}
	}
	if id == "" {
		t.Fatal("real held connection missing")
	}
	if err = manager.CloseConnections(ctx, snapshot.SessionID, id, false); err != nil {
		t.Fatal(err)
	}
	// Finishing this read proves that DELETE closed the actual TCP stream.
	readDone := make(chan struct{})
	go func() { io.Copy(io.Discard, response.Body); close(readDone) }()
	select {
	case <-readDone:
	case <-time.After(2 * time.Second):
		t.Fatal("close only changed UI; network stream survived")
	}
	for i := 0; i < 2; i++ {
		response, err := client.Get(origin.URL)
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
	}
	if err = manager.CloseConnections(ctx, snapshot.SessionID, "", true); err != nil {
		t.Fatal(err)
	}
	logs := manager.logs.read("", 0)
	if len(logs.Entries) == 0 {
		t.Fatal("real core output was not captured")
	}
	coreEvents := 0
	for _, entry := range logs.Entries {
		if entry.Source == "core" {
			coreEvents++
		}
	}
	if coreEvents == 0 {
		t.Fatal("only host summaries present; no real core logs")
	}
}
