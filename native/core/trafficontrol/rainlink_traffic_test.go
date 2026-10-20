package trafficontrol

import (
	"encoding/json"
	"fmt"
	"math"
	"strings"
	"sync"
	"testing"

	"github.com/sagernet/sing-box/common/process"
)

func trafficSnapshot(t *testing.T, manager *Manager) RainLinkTrafficSnapshot {
	t.Helper()
	result, err := manager.RainLinkTrafficSnapshot()
	if err != nil {
		t.Fatal(err)
	}
	up, down := int64(0), int64(0)
	seen := make(map[rainlinkTrafficKey]bool)
	for _, row := range result.Rows {
		key := rainlinkTrafficKey{row.Outbound, row.Process}
		if seen[key] {
			t.Fatal("duplicate aggregate identity")
		}
		seen[key] = true
		up, down = up+row.Upload, down+row.Download
	}
	if result.Version != 1 || result.Epoch == "" || up != result.UploadTotal || down != result.DownloadTotal {
		t.Fatal("aggregate bytes do not conserve the same snapshot")
	}
	return result
}

func TestRainLinkTrafficPrivacyAndUnknownIdentity(t *testing.T) {
	manager := NewManager()
	for index, fixture := range []struct {
		info *process.Info
		want string
	}{
		{nil, ""},
		{&process.Info{User: "private-user", UserId: 1000}, ""},
		{&process.Info{ProcessPath: "/home/private-user/bin/curl"}, "curl"},
		{&process.Info{ProcessPath: `C:\Users\private-user\Browser\browser.exe`}, "browser.exe"},
		{&process.Info{PackageName: "dev.example.reader", ProcessPath: "/private/path"}, "dev.example.reader"},
		{&process.Info{ProcessPath: "../"}, ""},
		{&process.Info{ProcessPath: "bad\nprocess"}, ""},
		{&process.Info{PackageName: strings.Repeat("界", 65)}, ""},
	} {
		counter := manager.rainlinkMeter(fmt.Sprintf("route-%d", index), fixture.info)
		if counter.key.process != fixture.want {
			t.Errorf("process fixture %d returned %q", index, counter.key.process)
		}
		counter.upload.Add(3)
	}
	for _, tag := range []string{"user@secret", "with space", "with\nnewline", strings.Repeat("x", 129)} {
		manager.rainlinkMeter(tag, nil).download.Add(1)
	}
	result := trafficSnapshot(t, manager)
	raw, err := json.Marshal(result)
	if err != nil || strings.Contains(string(raw), "private-user") || strings.Contains(string(raw), "user@secret") {
		t.Fatal("aggregate response contains a path, user or untrusted tag")
	}
	if result.UploadTotal != 24 || result.DownloadTotal != 4 {
		t.Fatal("unknown process or outbound lost bytes")
	}
}

func TestRainLinkTrafficConcurrentReadAndStableLifetime(t *testing.T) {
	manager := NewManager()
	initial := trafficSnapshot(t, manager)
	const workers, iterations = 16, 8000
	var group sync.WaitGroup
	for worker := range workers {
		group.Go(func() {
			counter := manager.rainlinkMeter(fmt.Sprintf("route-%d", worker%3), &process.Info{ProcessPath: "/private/app"})
			for range iterations {
				counter.upload.Add(7)
				counter.download.Add(11)
			}
		})
	}
	for range 30 {
		trafficSnapshot(t, manager)
	}
	group.Wait()
	result := trafficSnapshot(t, manager)
	if result.Epoch != initial.Epoch || result.UploadTotal != workers*iterations*7 || result.DownloadTotal != workers*iterations*11 {
		t.Fatal("concurrent streams lost bytes or changed epoch")
	}
	manager.ResetStatistic()
	afterReset := trafficSnapshot(t, manager)
	if afterReset.Epoch != result.Epoch || afterReset.UploadTotal != result.UploadTotal {
		t.Fatal("Clash reset changed the persistent accounting checkpoint")
	}
	if trafficSnapshot(t, NewManager()).Epoch == result.Epoch {
		t.Fatal("a new core reused the previous accounting epoch")
	}
}

func TestRainLinkTrafficBoundsPreserveAllBytes(t *testing.T) {
	manager := NewManager()
	for index := range rainlinkTrafficMaxProcesses + 20 {
		manager.rainlinkMeter("proxy", &process.Info{PackageName: fmt.Sprintf("package-%d", index)}).upload.Add(1)
	}
	processLimited := trafficSnapshot(t, manager)
	if !processLimited.Limited || processLimited.UploadTotal != rainlinkTrafficMaxProcesses+20 || len(processLimited.Rows) != rainlinkTrafficMaxProcesses+1 {
		t.Fatal("process limit lost bytes or exceeded the bound")
	}
	for _, row := range processLimited.Rows {
		if row.Outbound != "proxy" {
			t.Fatal("process limit discarded a known outbound")
		}
	}
	manager = NewManager()
	manager.rainlinkMeter("", nil).download.Add(9)
	for index := range rainlinkTrafficMaxCells + 30 {
		manager.rainlinkMeter(fmt.Sprintf("route-%d", index), nil).download.Add(1)
	}
	limited := trafficSnapshot(t, manager)
	if !limited.Limited || len(limited.Rows) > rainlinkTrafficMaxCells+1 || limited.DownloadTotal != rainlinkTrafficMaxCells+39 {
		t.Fatal("cell limit lost bytes or exceeded the bound")
	}
	// Existing meters stay usable after the limit; they are never evicted.
	manager.rainlinkMeter("route-0", nil).download.Add(5)
	if trafficSnapshot(t, manager).DownloadTotal != limited.DownloadTotal+5 {
		t.Fatal("an existing bucket was lost at the limit")
	}
}

func TestRainLinkTrafficOverflowFailsInsteadOfWrapping(t *testing.T) {
	manager := NewManager()
	manager.rainlinkMeter("proxy", nil).upload.Add(math.MaxInt64)
	manager.rainlinkMeter("direct", nil).upload.Add(1)
	if _, err := manager.RainLinkTrafficSnapshot(); err == nil {
		t.Fatal("aggregate overflow produced a valid response")
	}
}

func BenchmarkRainLinkTrafficCounterHotPath(b *testing.B) {
	counter := NewManager().rainlinkMeter("proxy", nil)
	b.ResetTimer()
	for b.Loop() {
		counter.upload.Add(1024)
	}
}
