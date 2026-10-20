package trafficontrol

import (
	"errors"
	"math"
	"path"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"unicode"
	"unicode/utf8"

	"github.com/gofrs/uuid/v5"
	"github.com/sagernet/sing-box/common/process"
)

const (
	rainlinkTrafficVersion      = 1
	rainlinkTrafficMaxCells     = 2048
	rainlinkTrafficMaxProcesses = 127
	rainlinkTrafficLabelRunes   = 64
	rainlinkTrafficTagBytes     = 128
)

type rainlinkTrafficKey struct{ outbound, process string }

type rainlinkTrafficCounter struct {
	key              rainlinkTrafficKey
	upload, download atomic.Int64
}

// Each stream keeps its original counter pointer, including after Close. The
// hot counting path only performs atomic additions, without a map lookup or
// global mutex. Manager lifetime, rather than active-connection retention,
// bounds the cumulative history.
type rainlinkTrafficState struct {
	mu        sync.Mutex
	epoch     string
	cells     map[rainlinkTrafficKey]*rainlinkTrafficCounter
	processes map[string]struct{}
	overflow  rainlinkTrafficCounter
	limited   bool
}

// RainLinkTrafficRow contains counters for one actual outbound and process
// basename/package. Empty identities mean unknown, never an inferred route.
type RainLinkTrafficRow struct {
	Outbound string `json:"outbound"`
	Process  string `json:"process"`
	Upload   int64  `json:"upload"`
	Download int64  `json:"download"`
}

// RainLinkTrafficSnapshot partitions the same read counters into exact totals.
// Its independent epoch/counters are not reset by Clash's reset-statistics API.
type RainLinkTrafficSnapshot struct {
	Version       int                  `json:"version"`
	Epoch         string               `json:"epoch"`
	UploadTotal   int64                `json:"uploadTotal"`
	DownloadTotal int64                `json:"downloadTotal"`
	Limited       bool                 `json:"limited"`
	Rows          []RainLinkTrafficRow `json:"rows"`
}

func rainlinkProcess(info *process.Info) string {
	if info == nil {
		return ""
	}
	label := info.PackageName
	if label == "" && info.ProcessPath != "" {
		label = path.Base(strings.ReplaceAll(info.ProcessPath, `\`, "/"))
	}
	if label == "." || label == "/" || label == ".." || !utf8.ValidString(label) ||
		utf8.RuneCountInString(label) > rainlinkTrafficLabelRunes || strings.IndexFunc(label, unicode.IsControl) >= 0 {
		return ""
	}
	return strings.Clone(label)
}

func rainlinkOutbound(tag string) string {
	if len(tag) > rainlinkTrafficTagBytes {
		return ""
	}
	for _, character := range tag {
		if !(character >= 'a' && character <= 'z' || character >= 'A' && character <= 'Z' ||
			character >= '0' && character <= '9' || strings.ContainsRune("._:-", character)) {
			return ""
		}
	}
	return strings.Clone(tag)
}

func (m *Manager) rainlinkMeter(outbound string, info *process.Info) *rainlinkTrafficCounter {
	state := &m.rainlinkTraffic
	key := rainlinkTrafficKey{outbound: rainlinkOutbound(outbound), process: rainlinkProcess(info)}
	state.mu.Lock()
	defer state.mu.Unlock()
	if state.cells == nil {
		state.cells = make(map[rainlinkTrafficKey]*rainlinkTrafficCounter)
		state.processes = make(map[string]struct{})
	}
	if key.process != "" {
		if _, exists := state.processes[key.process]; !exists {
			if len(state.processes) >= rainlinkTrafficMaxProcesses {
				state.limited = true
				key.process = ""
			} else {
				state.processes[key.process] = struct{}{}
			}
		}
	}
	if counter := state.cells[key]; counter != nil {
		return counter
	}
	if key == (rainlinkTrafficKey{}) {
		return &state.overflow
	}
	if len(state.cells) >= rainlinkTrafficMaxCells {
		state.limited = true
		return &state.overflow
	}
	counter := &rainlinkTrafficCounter{key: key}
	state.cells[key] = counter
	return counter
}

// RainLinkTrafficSnapshot reads a bounded counter table, retaining closed flows
// without retaining their destinations, credentials, PIDs or full process paths.
func (m *Manager) RainLinkTrafficSnapshot() (RainLinkTrafficSnapshot, error) {
	state := &m.rainlinkTraffic
	state.mu.Lock()
	if state.epoch == "" {
		id, err := uuid.NewV4()
		if err != nil {
			state.mu.Unlock()
			return RainLinkTrafficSnapshot{}, errors.New("create traffic epoch")
		}
		state.epoch = id.String()
	}
	result := RainLinkTrafficSnapshot{Version: rainlinkTrafficVersion, Epoch: state.epoch, Limited: state.limited,
		Rows: make([]RainLinkTrafficRow, 0, len(state.cells)+1)}
	counters := make([]*rainlinkTrafficCounter, 0, len(state.cells)+1)
	for _, counter := range state.cells {
		counters = append(counters, counter)
	}
	counters = append(counters, &state.overflow)
	state.mu.Unlock()
	for _, counter := range counters {
		up, down := counter.upload.Load(), counter.download.Load()
		if up == 0 && down == 0 {
			continue
		}
		if up < 0 || down < 0 || result.UploadTotal > math.MaxInt64-up || result.DownloadTotal > math.MaxInt64-down {
			return RainLinkTrafficSnapshot{}, errors.New("traffic counter overflow")
		}
		result.UploadTotal += up
		result.DownloadTotal += down
		result.Rows = append(result.Rows, RainLinkTrafficRow{Outbound: counter.key.outbound, Process: counter.key.process, Upload: up, Download: down})
	}
	sort.Slice(result.Rows, func(i, j int) bool {
		left, right := result.Rows[i], result.Rows[j]
		if left.Outbound == right.Outbound {
			return left.Process < right.Process
		}
		return left.Outbound < right.Outbound
	})
	return result, nil
}
