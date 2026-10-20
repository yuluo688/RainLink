package session

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"
)

const maximumTrafficCounter int64 = 9007199254740991
const maximumTrafficRows = 2049

// TrafficTarget is a frozen public identity, independent of the current selection.
type TrafficTarget struct {
	ID   string `json:"id"`
	Kind string `json:"kind"`
	Name string `json:"name"`
}

// TrafficCounter is cumulative within one core epoch. Each dimension partitions
// the same total; target and application counters must never be added together.
type TrafficCounter struct {
	TrafficTarget
	Upload   int64 `json:"upload"`
	Download int64 `json:"download"`
}

// TrafficSnapshot includes completed flows without retaining their destinations.
type TrafficSnapshot struct {
	Version       int              `json:"version"`
	SessionID     string           `json:"sessionId"`
	Epoch         string           `json:"epoch"`
	SampledAt     int64            `json:"sampledAt"`
	UploadTotal   int64            `json:"uploadTotal"`
	DownloadTotal int64            `json:"downloadTotal"`
	Limited       bool             `json:"limited"`
	Targets       []TrafficCounter `json:"targets"`
	Applications  []TrafficCounter `json:"applications"`
}

type coreTrafficRow struct {
	Outbound string `json:"outbound"`
	Process  string `json:"process"`
	Upload   int64  `json:"upload"`
	Download int64  `json:"download"`
}

type coreTrafficSnapshot struct {
	Version       int              `json:"version"`
	Epoch         string           `json:"epoch"`
	UploadTotal   int64            `json:"uploadTotal"`
	DownloadTotal int64            `json:"downloadTotal"`
	Limited       bool             `json:"limited"`
	Rows          []coreTrafficRow `json:"rows"`
}

var unknownTrafficTarget = TrafficTarget{ID: "unassigned", Kind: "unknown", Name: "未归属流量"}
var unknownTrafficApplication = TrafficTarget{ID: "unassigned", Kind: "application", Name: "未识别应用"}

func trafficTarget(outbound RoutingOutbound) TrafficTarget {
	if outbound.Chain != nil {
		return TrafficTarget{ID: outbound.Chain.ID, Kind: "chain", Name: outbound.Chain.Name}
	}
	return TrafficTarget{ID: outbound.Node.ID, Kind: "node", Name: outbound.Node.Name}
}

func trafficTargets(primary RoutingOutbound, plan *RoutingPlan) map[string]TrafficTarget {
	result := map[string]TrafficTarget{
		"proxy": trafficTarget(primary), "direct": {ID: "direct", Kind: "direct", Name: "直连"},
	}
	if plan != nil {
		for index, outbound := range plan.Outbounds {
			result["route-"+strconv.Itoa(index)] = trafficTarget(outbound)
		}
	}
	return result
}

func validTrafficLabel(label string) bool {
	return label != "" && strings.TrimSpace(label) != "" && utf8.ValidString(label) &&
		utf8.RuneCountInString(label) <= 128 && strings.IndexFunc(label, unicode.IsControl) < 0
}

func validTrafficCounter(value int64) bool { return value >= 0 && value <= maximumTrafficCounter }

func trafficPartition(rows map[string]TrafficCounter) []TrafficCounter {
	result := make([]TrafficCounter, 0, len(rows))
	for _, row := range rows {
		result = append(result, row)
	}
	sort.Slice(result, func(i, j int) bool {
		if result[i].Kind != result[j].Kind {
			return result[i].Kind < result[j].Kind
		}
		return result[i].ID < result[j].ID
	})
	return result
}

func addTraffic(rows map[string]TrafficCounter, identity TrafficTarget, row coreTrafficRow) {
	key := identity.Kind + ":" + identity.ID
	value := rows[key]
	value.TrafficTarget = identity
	value.Upload += row.Upload
	value.Download += row.Download
	rows[key] = value
}

// Traffic reads authenticated accounting owned by the supplied active session.
// Failure never falls back to attributing aggregate totals to today's selection.
func (m *Manager) Traffic(ctx context.Context, sessionID string) (TrafficSnapshot, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	core := m.active
	if !routeIDPattern.MatchString(sessionID) || core == nil || core.snapshot.SessionID != sessionID {
		return TrafficSnapshot{}, fail("session_changed", "连接会话已改变，请刷新")
	}
	var source coreTrafficSnapshot
	if err := core.apiJSON(ctx, http.MethodGet, "/rainlink/traffic", nil, &source); err != nil {
		return TrafficSnapshot{}, fail("traffic_unavailable", "无法读取核心流量统计，请检查核心版本并重试")
	}
	invalid := func() (TrafficSnapshot, error) {
		return TrafficSnapshot{}, fail("traffic_invalid", "核心流量计数无效，本次统计未保存")
	}
	if source.Version != 1 || !routeIDPattern.MatchString(source.Epoch) || len(source.Rows) > maximumTrafficRows ||
		!validTrafficCounter(source.UploadTotal) || !validTrafficCounter(source.DownloadTotal) {
		return invalid()
	}
	targets, applications := map[string]TrafficCounter{}, map[string]TrafficCounter{}
	seen := map[[2]string]bool{}
	var upload, download int64
	for _, row := range source.Rows {
		key := [2]string{row.Outbound, row.Process}
		if seen[key] || len(row.Outbound) > 128 || !validTrafficCounter(row.Upload) || !validTrafficCounter(row.Download) ||
			row.Process != "" && (!validTrafficLabel(row.Process) || utf8.RuneCountInString(row.Process) > 64 || strings.ContainsAny(row.Process, `/\`)) {
			return invalid()
		}
		seen[key] = true
		upload += row.Upload
		download += row.Download
		if upload > source.UploadTotal || download > source.DownloadTotal {
			return invalid()
		}
		target, exists := core.trafficTargets[row.Outbound]
		if !exists || !routeIDPattern.MatchString(target.ID) || !validTrafficLabel(target.Name) {
			target = unknownTrafficTarget
		}
		application := unknownTrafficApplication
		if row.Process != "" {
			digest := sha256.Sum256([]byte(row.Process))
			application = TrafficTarget{ID: "app-" + hex.EncodeToString(digest[:]), Kind: "application", Name: row.Process}
		}
		addTraffic(targets, target, row)
		addTraffic(applications, application, row)
	}
	if upload != source.UploadTotal || download != source.DownloadTotal || len(targets) > maxRouteTargets+3 || len(applications) > 128 {
		return invalid()
	}
	return TrafficSnapshot{Version: 1, SessionID: sessionID, Epoch: source.Epoch, SampledAt: time.Now().UnixMilli(),
		UploadTotal: upload, DownloadTotal: download, Limited: source.Limited,
		Targets: trafficPartition(targets), Applications: trafficPartition(applications)}, nil
}
