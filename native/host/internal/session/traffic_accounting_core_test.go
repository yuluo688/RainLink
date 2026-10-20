package session

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

type trafficAccountingCoreSnapshot struct {
	Version       int    `json:"version"`
	Epoch         string `json:"epoch"`
	UploadTotal   int64  `json:"uploadTotal"`
	DownloadTotal int64  `json:"downloadTotal"`
	Limited       bool   `json:"limited"`
	Rows          []struct {
		Outbound string `json:"outbound"`
		Process  string `json:"process"`
		Upload   int64  `json:"upload"`
		Download int64  `json:"download"`
	} `json:"rows"`
}

func (snapshot trafficAccountingCoreSnapshot) outbound(tag string) (int64, int64) {
	var up, down int64
	for _, row := range snapshot.Rows {
		if row.Outbound == tag {
			up, down = up+row.Upload, down+row.Download
		}
	}
	return up, down
}

func TestRealCoreTrafficAccountingAcrossModesAndClosedFlows(t *testing.T) {
	corePath := testCore(t)
	ctx, cancel := context.WithTimeout(t.Context(), 90*time.Second)
	defer cancel()
	calls := &chainRecorder{}
	primary := chainProxyFixture(t, "primary-traffic", calls, false)
	secondary := chainProxyFixture(t, "secondary-traffic", calls, false)
	resume := make(chan struct{})
	var resumeOnce sync.Once
	t.Cleanup(func() { resumeOnce.Do(func() { close(resume) }) })
	chunk := bytes.Repeat([]byte("t"), 4096)
	origin := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Path == "/held" {
			writer.Header().Set("Content-Length", strconv.Itoa(2*len(chunk)))
			writer.Write(chunk)
			writer.(http.Flusher).Flush()
			select {
			case <-resume:
				writer.Write(chunk)
			case <-request.Context().Done():
			}
			return
		}
		io.WriteString(writer, "traffic-accounting-fixture")
	}))
	t.Cleanup(origin.Close)
	plan := RoutingPlan{Revision: 9, Rules: []RouteRule{
		{ID: "local-secondary", Type: "IP-CIDR", Value: "127.0.0.0/8", Target: "node:" + secondary.ID, Enabled: true},
		fallbackRule("direct"),
	}, Outbounds: []RoutingOutbound{{Key: "node:" + secondary.ID, Name: secondary.Name, Node: secondary}}}
	manager := New(corePath, t.TempDir())
	t.Cleanup(func() {
		if err := manager.Disconnect(); err != nil {
			t.Error(err)
		}
	})
	snapshot, err := manager.connectTarget(ctx, primary, nil, "global", false, &plan, false)
	if err != nil {
		t.Fatal(err)
	}
	read := func() trafficAccountingCoreSnapshot {
		t.Helper()
		var result trafficAccountingCoreSnapshot
		if err := manager.active.apiJSON(ctx, http.MethodGet, "/rainlink/traffic", nil, &result); err != nil {
			t.Fatal("traffic accounting API unavailable", err)
		}
		var up, down int64
		for _, row := range result.Rows {
			if strings.ContainsAny(row.Process, `/\`) || row.Upload < 0 || row.Download < 0 {
				t.Fatal("aggregate exposed a path or invalid counter")
			}
			up, down = up+row.Upload, down+row.Download
		}
		if result.Version != 1 || !connectionIDPattern.MatchString(result.Epoch) || result.Rows == nil || up != result.UploadTotal || down != result.DownloadTotal || result.Limited {
			t.Fatal("aggregate snapshot lost bytes or identity")
		}
		return result
	}
	initial := read()
	if initial.UploadTotal != 0 || initial.DownloadTotal != 0 {
		t.Fatal("control requests were counted as proxy traffic")
	}
	unauthorized, err := manager.active.client.Get(manager.active.api + "/rainlink/traffic")
	if err != nil {
		t.Fatal(err)
	}
	unauthorized.Body.Close()
	if unauthorized.StatusCode != http.StatusUnauthorized {
		t.Fatal("real aggregate endpoint accepted unauthenticated access")
	}
	proxy, _ := url.Parse(fmt.Sprintf("http://127.0.0.1:%d", snapshot.ProxyPort))
	client := &http.Client{Timeout: 5 * time.Second, Transport: &http.Transport{Proxy: http.ProxyURL(proxy), DisableKeepAlives: true}}
	t.Cleanup(client.CloseIdleConnections)
	held, err := client.Get(origin.URL + "/held")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { held.Body.Close() })
	first := make([]byte, len(chunk))
	if _, err := io.ReadFull(held.Body, first); err != nil || !bytes.Equal(first, chunk) {
		t.Fatal("held global stream failed", err)
	}
	beforeMode := read()
	if err := manager.SetMode(ctx, "direct"); err != nil {
		t.Fatal(err)
	}
	get := func() {
		t.Helper()
		response, err := client.Get(origin.URL)
		if err != nil {
			t.Fatal(err)
		}
		data, readErr := io.ReadAll(response.Body)
		response.Body.Close()
		if readErr != nil || string(data) != "traffic-accounting-fixture" {
			t.Fatal("local origin transfer failed", readErr)
		}
	}
	get()
	resumeOnce.Do(func() { close(resume) })
	remaining, err := io.ReadAll(held.Body)
	held.Body.Close()
	if err != nil || !bytes.Equal(remaining, chunk) {
		t.Fatal("original global flow did not survive mode change", err)
	}
	afterMode := read()
	_, oldProxy := beforeMode.outbound("proxy")
	_, newProxy := afterMode.outbound("proxy")
	_, direct := afterMode.outbound("direct")
	if newProxy < oldProxy+int64(len(chunk)) || direct <= 0 {
		t.Fatal("mode change attributed an existing flow to the new route")
	}
	if err := manager.SetMode(ctx, "rule"); err != nil {
		t.Fatal(err)
	}
	// This exceeds upstream's 1,000-entry closed-flow retention. No polling is
	// performed between these short connections; accounting must retain all bytes.
	const closedFlows = 1050
	for range closedFlows {
		get()
	}
	afterShort := read()
	_, ruleDown := afterShort.outbound("route-0")
	if ruleDown < closedFlows*int64(len("traffic-accounting-fixture")) {
		t.Fatal("closed short connections lost their actual rule outbound")
	}
	if err := manager.SetMode(ctx, "direct"); err != nil {
		t.Fatal(err)
	}
	echo, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	echoDone := make(chan struct{})
	go func() {
		defer close(echoDone)
		buffer := make([]byte, 4096)
		for {
			count, address, err := echo.ReadFrom(buffer)
			if err != nil {
				return
			}
			if _, err = echo.WriteTo(buffer[:count], address); err != nil {
				return
			}
		}
	}()
	t.Cleanup(func() { echo.Close(); <-echoDone })
	socksUDPEcho(t, snapshot.ProxyPort, echo.LocalAddr().(*net.UDPAddr).Port)
	afterUDP := read()
	udpUp, udpDown := afterUDP.outbound("direct")
	beforeUDPUp, beforeUDPDown := afterShort.outbound("direct")
	if udpUp <= beforeUDPUp || udpDown <= beforeUDPDown {
		t.Fatal("real UDP payload was not counted in its actual direct outbound")
	}
	if err := manager.active.apiJSON(ctx, http.MethodDelete, "/connections", nil, nil); err != nil {
		t.Fatal(err)
	}
	var final trafficAccountingCoreSnapshot
	matched := false
	for deadline := time.Now().Add(3 * time.Second); time.Now().Before(deadline); {
		connections, err := manager.active.readConnections(ctx)
		if err != nil {
			t.Fatal(err)
		}
		final = read()
		if len(connections.Connections) == 0 && final.UploadTotal == connections.UploadTotal && final.DownloadTotal == connections.DownloadTotal {
			matched = true
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if !matched || final.Epoch != initial.Epoch || final.UploadTotal < afterUDP.UploadTotal || final.DownloadTotal < afterUDP.DownloadTotal {
		t.Fatal("closed-flow aggregates no longer match the real core totals")
	}
	public, err := manager.Traffic(ctx, snapshot.SessionID)
	if err != nil || public.UploadTotal != final.UploadTotal || public.DownloadTotal != final.DownloadTotal || public.Epoch != final.Epoch {
		t.Fatalf("public accounting lost real counters: %+v, %v", public, err)
	}
	var knownApplicationBytes int64
	for _, row := range public.Applications {
		if row.ID != unknownTrafficApplication.ID {
			knownApplicationBytes += row.Upload + row.Download
		}
	}
	if runtime.GOOS == "windows" && knownApplicationBytes == 0 {
		t.Fatal("Windows process lookup did not attribute the real test client")
	}
	t.Logf("public targets=%d applications=%d identifiedApplicationBytes=%d", len(public.Targets), len(public.Applications), knownApplicationBytes)
	if err := manager.Disconnect(); err != nil {
		t.Fatal(err)
	}
	if _, err := manager.connectTarget(ctx, primary, nil, "global", false, nil, false); err != nil {
		t.Fatal(err)
	}
	restarted := read()
	if restarted.Epoch == final.Epoch || restarted.UploadTotal != 0 || restarted.DownloadTotal != 0 {
		t.Fatal("new core reused an earlier epoch or byte checkpoint")
	}
	t.Logf("closedFlows=%d totals=%d/%d; global/direct/rule and live TCP+UDP verified", closedFlows, final.UploadTotal, final.DownloadTotal)
}
