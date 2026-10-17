package session

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"sync/atomic"
	"testing"
	"time"
)

func TestRealCoreNodeProbeIsolationAndFailures(t *testing.T) {
	core := testCore(t)
	calls := &chainRecorder{}
	node := chainProxyFixture(t, "node-probe", calls, false)
	rejected := chainProxyFixture(t, "node-reject", calls, true)
	var originCalls atomic.Int32
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		originCalls.Add(1)
		w.WriteHeader(http.StatusNoContent)
	}))
	defer origin.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	live := New(core, t.TempDir())
	active, err := live.connectTarget(ctx, node, nil, "global", false, nil, false)
	if err != nil {
		t.Fatal(err)
	}
	defer live.Disconnect()
	stateDir := t.TempDir()
	probe := New(core, stateDir)
	probe.isolated = true
	result, err := probe.testNode(ctx, node, origin.URL)
	if err != nil || !result.Passed || result.NodeID != node.ID || result.Revision != node.Revision || result.CheckedAt <= 0 {
		t.Fatal("actual node probe failed", result, err)
	}
	target, _ := url.Parse(origin.URL)
	if got := calls.take(); len(got) != 1 || got[0] != node.ID+">"+target.Host || originCalls.Load() != 1 {
		t.Fatal("probe did not traverse its selected upstream", got, originCalls.Load())
	}
	result, err = probe.testNode(ctx, rejected, origin.URL)
	if err != nil || result.Passed || result.Error == "" || originCalls.Load() != 1 {
		t.Fatal("authentication failure reported success or reached source", result, err, originCalls.Load())
	}
	current := live.Snapshot(ctx)
	if current.SessionID != active.SessionID || current.ProxyPort != active.ProxyPort {
		t.Fatal("probe replaced live session")
	}
	if entries, readErr := os.ReadDir(stateDir); readErr != nil || len(entries) != 0 {
		t.Fatal("probe retained runtime capture data", readErr)
	}
	if probe.active != nil {
		t.Fatal("probe leaked an active core")
	}
	payload, _ := json.Marshal(node)
	if _, err = live.execute(ctx, request{Method: "testNode", Payload: payload}); err == nil {
		t.Fatal("node testing allowed on a normal host")
	}
	for _, method := range []string{"capture", "connect", "protect", "reveal", "mode"} {
		if _, err = probe.execute(ctx, request{Method: method, Payload: json.RawMessage(`{}`)}); err == nil {
			t.Fatalf("isolated host allowed %s", method)
		}
	}
}

func TestRealCoreNodeProbeCancellationAndStatus(t *testing.T) {
	core := testCore(t)
	calls := &chainRecorder{}
	node := chainProxyFixture(t, "node-probe", calls, false)
	for _, status := range []int{http.StatusOK, http.StatusFound, http.StatusServiceUnavailable} {
		t.Run(http.StatusText(status), func(t *testing.T) {
			origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(status) }))
			defer origin.Close()
			probe := New(core, t.TempDir())
			probe.isolated = true
			result, err := probe.testNode(context.Background(), node, origin.URL)
			if err != nil || result.Passed || result.Error == "" {
				t.Fatal("non-204 probe accepted", result, err)
			}
		})
	}
	started, closed := make(chan struct{}), make(chan struct{})
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		close(started)
		<-r.Context().Done()
		close(closed)
	}))
	defer origin.Close()
	probe := New(core, t.TempDir())
	probe.isolated = true
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() { _, err := probe.testNode(ctx, node, origin.URL); done <- err }()
	select {
	case <-started:
	case err := <-done:
		t.Fatal("probe ended before reaching source", err)
	case <-time.After(5 * time.Second):
		t.Fatal("probe never reached source")
	}
	cancel()
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("cancelled probe succeeded")
		}
	case <-time.After(5 * time.Second):
		t.Fatal("cancel did not stop probe")
	}
	select {
	case <-closed:
	case <-time.After(5 * time.Second):
		t.Fatal("source connection survived cancellation")
	}
	if probe.active != nil {
		t.Fatal("cancel leaked probe core")
	}
}
