package session

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestMobileConnectionsReuseStablePagingAttributionAndConfirmedClosing(t *testing.T) {
	var mu sync.Mutex
	var entries []map[string]any
	for i := 0; i < 35; i++ {
		entries = append(entries, map[string]any{"id": fmt.Sprintf("00000000-0000-0000-0000-%012d", i),
			"metadata": map[string]any{"host": "example.test", "destinationPort": "443", "network": "tcp"},
			"upload":   20, "download": 40, "start": time.Unix(int64(i+1), 0).UTC(), "chains": []string{"route-0"}})
	}
	ignoreDelete := true
	deletes := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		defer mu.Unlock()
		if r.Header.Get("Authorization") != "Bearer fixture-secret" {
			http.Error(w, "unauthorized", 401)
			return
		}
		if r.Method == http.MethodDelete {
			deletes++
			if !ignoreDelete {
				if r.URL.Path == "/connections" {
					entries = nil
				} else {
					id := strings.TrimPrefix(r.URL.Path, "/connections/")
					for i, entry := range entries {
						if entry["id"] == id {
							entries = append(entries[:i], entries[i+1:]...)
							break
						}
					}
				}
			}
			w.WriteHeader(204)
			return
		}
		json.NewEncoder(w).Encode(map[string]any{"connections": entries, "uploadTotal": 700, "downloadTotal": 1400})
	}))
	defer server.Close()
	address, _ := url.Parse(server.URL)
	port, _ := strconv.Atoi(address.Port())
	logs := NewMobileLogs(nil)
	monitor := NewMobileConnections(MobileConfiguration{APIPort: port, APISecret: "fixture-secret",
		Snapshot: Snapshot{SessionID: "mobile-A"}, OutboundNames: map[string]string{"route-0": "自定义出口"}}, server.Client(), logs)
	ctx := context.Background()
	first, err := monitor.Page(ctx, "mobile-A", "", 0)
	if err != nil || first.Total != 35 || len(first.Entries) != 32 || first.Next != 32 {
		t.Fatalf("unexpected page: %+v, %v", first, err)
	}
	if first.Entries[0].Process != "" || first.Entries[0].Outbound != "自定义出口" || first.Entries[0].Direct {
		t.Fatal("unknown process or actual outbound attribution was fabricated")
	}
	if _, err := monitor.Page(ctx, "", "", 0); err == nil {
		t.Fatal("missing session accepted")
	}
	if _, err := monitor.Page(ctx, "mobile-B", "", 0); err == nil {
		t.Fatal("stale session accepted")
	}
	if err := monitor.Close(ctx, "mobile-B", "", true); err == nil {
		t.Fatal("stale close accepted")
	}
	if err := monitor.Close(ctx, "mobile-A", "../configs", false); err == nil {
		t.Fatal("path injection accepted")
	}
	mu.Lock()
	invalidDeletes := deletes
	mu.Unlock()
	if invalidDeletes != 0 {
		t.Fatal("invalid requests reached the control endpoint")
	}
	id := first.Entries[0].ID
	if err := monitor.Close(ctx, "mobile-A", id, false); err == nil {
		t.Fatal("DELETE without actual disappearance reported success")
	}
	mu.Lock()
	ignoreDelete = false
	mu.Unlock()
	if err := monitor.Close(ctx, "mobile-A", id, false); err != nil {
		t.Fatal(err)
	}
	last, err := monitor.Page(ctx, "mobile-A", first.SnapshotID, 32)
	if err != nil || last.Total != 35 || len(last.Entries) != 3 || last.Next != -1 {
		t.Fatal("underlying mutation changed a stable page")
	}
	if err := monitor.Close(ctx, "mobile-A", "", true); err != nil {
		t.Fatal(err)
	}
	empty, err := monitor.Page(ctx, "mobile-A", "", 0)
	if err != nil || empty.Total != 0 || len(logs.Read("", 0).Entries) != 2 {
		t.Fatal("closure did not update actual connections and shared logs")
	}
	cancelled, cancel := context.WithCancel(ctx)
	cancel()
	if _, err := monitor.Page(cancelled, "mobile-A", "", 0); err == nil {
		t.Fatal("cancelled service request succeeded")
	}
}

func TestMobileLogStoreSharesOnlySanitizedEntriesAcrossSessions(t *testing.T) {
	store := NewMobileLogs(nil)
	first := store.ForSession([]string{"first-password"})
	second := store.ForSession([]string{"second-password"})
	first.WriteLine("INFO[001] first-password")
	second.WriteLine("WARN[002] second-password")
	batch := store.Read("", 0)
	if len(batch.Entries) != 2 || batch.Entries[0].Level != "info" || batch.Entries[1].Level != "warning" {
		t.Fatal("session writers did not share the service buffer")
	}
	encoded, err := json.Marshal(batch)
	if err != nil || strings.Contains(string(encoded), "-password") || len(store.writer.secrets) != 0 {
		t.Fatal("service-wide store retained a credential")
	}
	checkpoint := store.Clear()
	second.WriteLine("INFO[003] after clearing")
	batch = store.Read(checkpoint.Stream, checkpoint.Cursor)
	if len(batch.Entries) != 1 || batch.Entries[0].Message != "after clearing" {
		t.Fatal("clear replayed old events or discarded a newer event")
	}
}
