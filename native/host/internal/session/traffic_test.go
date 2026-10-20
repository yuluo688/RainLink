package session

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func trafficFixture(t *testing.T, snapshot coreTrafficSnapshot) (*Manager, *coreTrafficSnapshot) {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Path != "/rainlink/traffic" || request.Header.Get("Authorization") != "Bearer fixture-secret" {
			http.Error(writer, "private-response", http.StatusUnauthorized)
			return
		}
		if err := json.NewEncoder(writer).Encode(snapshot); err != nil {
			t.Error(err)
		}
	}))
	t.Cleanup(server.Close)
	manager := New("", t.TempDir())
	manager.active = &runningCore{api: server.URL, secret: "fixture-secret", client: server.Client(),
		snapshot: Snapshot{SessionID: "session-a", Mode: "rule"},
		trafficTargets: map[string]TrafficTarget{
			"proxy":   {ID: "node-a", Kind: "node", Name: "主节点"},
			"route-0": {ID: "chain-a", Kind: "chain", Name: "工作链"},
			"route-1": {ID: "node-a", Kind: "node", Name: "主节点"},
			"direct":  {ID: "direct", Kind: "direct", Name: "直连"},
		}}
	return manager, &snapshot
}

func validTrafficFixture() coreTrafficSnapshot {
	return coreTrafficSnapshot{Version: 1, Epoch: "epoch-a", UploadTotal: 10, DownloadTotal: 100,
		Rows: []coreTrafficRow{{Outbound: "proxy", Process: "browser.exe", Upload: 10, Download: 100}}}
}

func TestTrafficPartitionsActualTargetsApplicationsAndUnknown(t *testing.T) {
	source := coreTrafficSnapshot{Version: 1, Epoch: "epoch-a", UploadTotal: 50, DownloadTotal: 500, Limited: true,
		Rows: []coreTrafficRow{
			{Outbound: "proxy", Process: "browser.exe", Upload: 10, Download: 100},
			{Outbound: "route-0", Process: "dev.editor", Upload: 10, Download: 100},
			{Outbound: "route-1", Process: "browser.exe", Upload: 10, Download: 100},
			{Outbound: "direct", Upload: 10, Download: 100},
			{Upload: 10, Download: 100},
		}}
	manager, _ := trafficFixture(t, source)
	snapshot, err := manager.Traffic(t.Context(), "session-a")
	if err != nil {
		t.Fatal(err)
	}
	if snapshot.Epoch != source.Epoch || !snapshot.Limited || len(snapshot.Targets) != 4 || len(snapshot.Applications) != 3 {
		t.Fatalf("partition lost identities: %+v", snapshot)
	}
	for _, dimension := range [][]TrafficCounter{snapshot.Targets, snapshot.Applications} {
		var upload, download int64
		for _, row := range dimension {
			upload += row.Upload
			download += row.Download
		}
		if upload != 50 || download != 500 {
			t.Fatal("dimension is not a partition of totals")
		}
	}
	for _, row := range snapshot.Targets {
		if row.ID == "node-a" && (row.Upload != 20 || row.Download != 200) {
			t.Fatal("one actual node was counted as multiple logical groups")
		}
	}
	if _, err := manager.Traffic(t.Context(), "session-b"); err == nil {
		t.Fatal("accepted stale session")
	}
	manager.isolated = true
	if _, err := manager.execute(t.Context(), request{Method: "traffic", Payload: json.RawMessage(`{"sessionId":"session-a"}`)}); err == nil {
		t.Fatal("isolated probe gained interactive traffic access")
	}
}

func TestTrafficRejectsInvalidSnapshotsWithoutLeakingCoreBody(t *testing.T) {
	for name, mutate := range map[string]func(*coreTrafficSnapshot){
		"version":        func(s *coreTrafficSnapshot) { s.Version = 2 },
		"epoch":          func(s *coreTrafficSnapshot) { s.Epoch = "" },
		"negative":       func(s *coreTrafficSnapshot) { s.Rows[0].Upload = -1 },
		"overflow":       func(s *coreTrafficSnapshot) { s.UploadTotal = maximumTrafficCounter + 1 },
		"missing bytes":  func(s *coreTrafficSnapshot) { s.UploadTotal++ },
		"invented bytes": func(s *coreTrafficSnapshot) { s.Rows[0].Download++ },
		"duplicate":      func(s *coreTrafficSnapshot) { s.Rows = append(s.Rows, s.Rows[0]) },
		"private path":   func(s *coreTrafficSnapshot) { s.Rows[0].Process = `C:\Users\private-user\browser.exe` },
		"control":        func(s *coreTrafficSnapshot) { s.Rows[0].Process = "browser\x00.exe" },
		"rows":           func(s *coreTrafficSnapshot) { s.Rows = make([]coreTrafficRow, maximumTrafficRows+1) },
	} {
		t.Run(name, func(t *testing.T) {
			source := validTrafficFixture()
			mutate(&source)
			manager, _ := trafficFixture(t, source)
			_, err := manager.Traffic(t.Context(), "session-a")
			if err == nil || strings.Contains(err.Error(), "private-user") {
				t.Fatal("invalid traffic was accepted or exposed")
			}
		})
	}
	manager, _ := trafficFixture(t, validTrafficFixture())
	manager.active.secret = "wrong-token"
	_, err := manager.Traffic(context.Background(), "session-a")
	if err == nil || strings.Contains(err.Error(), "private-response") {
		t.Fatal("upstream error body crossed public boundary")
	}
}

func TestTrafficMaximumPublicSnapshotFitsPrivateIPC(t *testing.T) {
	source := coreTrafficSnapshot{Version: 1, Epoch: "epoch-a"}
	for i := 0; i < 127; i++ {
		source.Rows = append(source.Rows, coreTrafficRow{Outbound: fmt.Sprintf("route-%d", i%32),
			Process: strings.Repeat("<", 60) + fmt.Sprintf("%04d", i), Upload: 1, Download: 1})
	}
	source.Rows = append(source.Rows, coreTrafficRow{Upload: 1, Download: 1})
	source.UploadTotal, source.DownloadTotal = 128, 128
	manager, _ := trafficFixture(t, source)
	for i := 0; i < 32; i++ {
		manager.active.trafficTargets[fmt.Sprintf("route-%d", i)] = TrafficTarget{
			ID: fmt.Sprintf("%0128d", i), Kind: "node", Name: strings.Repeat("<", 128)}
	}
	snapshot, err := manager.Traffic(t.Context(), "session-a")
	if err != nil {
		t.Fatal(err)
	}
	encoded, err := json.Marshal(response{ID: 1, Result: snapshot})
	if err != nil || len(encoded)+1 >= 128<<10 {
		t.Fatalf("public traffic exceeded IPC limit: %d, %v", len(encoded), err)
	}
	t.Logf("maximum escaped public frame: %d bytes", len(encoded)+1)
}

func TestTrafficTargetsUseFrozenNodeAndChainIdentities(t *testing.T) {
	primary := RoutingOutbound{Chain: &ChainSnapshot{ID: "chain", Name: "链"}}
	plan := &RoutingPlan{Outbounds: []RoutingOutbound{{Key: "group:group", Name: "订阅组", Node: Node{ID: "actual-node", Name: "实际节点"}}}}
	identities := trafficTargets(primary, plan)
	if identities["proxy"].Kind != "chain" || identities["route-0"].ID != "actual-node" || identities["route-0"].Name != "实际节点" || len(identities) != 3 {
		t.Fatal("logical selection was substituted for actual identity")
	}
}
