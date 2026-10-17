package session

import (
	"context"
	"errors"
	"fmt"
	"runtime"
	"unsafe"

	"golang.org/x/sys/windows"
)

const (
	interfaceTypeVirtual = 53 // IF_TYPE_PROP_VIRTUAL (TUN implementations).
	initialAdapterBytes  = 15 << 10
	maximumAdapterBytes  = 1 << 20
)

type upstreamAdapter struct {
	name       string
	kind       uint32
	up         bool
	ipv4Metric uint32
	ipv6Metric uint32
}

func upstreamAdapters() (map[uint32]upstreamAdapter, error) {
	size := uint32(initialAdapterBytes)
	for attempt := 0; attempt < 3; attempt++ {
		if size > maximumAdapterBytes {
			return nil, errors.New("adapter table exceeds limit")
		}
		buffer := make([]byte, size)
		first := (*windows.IpAdapterAddresses)(unsafe.Pointer(&buffer[0]))
		err := windows.GetAdaptersAddresses(windows.AF_UNSPEC, windows.GAA_FLAG_SKIP_ANYCAST|windows.GAA_FLAG_SKIP_MULTICAST, 0, first, &size)
		if errors.Is(err, windows.ERROR_BUFFER_OVERFLOW) {
			continue
		}
		if err != nil {
			return nil, fmt.Errorf("read upstream adapters: %w", err)
		}
		adapters := make(map[uint32]upstreamAdapter)
		for adapter := first; adapter != nil; adapter = adapter.Next {
			entry := upstreamAdapter{name: windows.UTF16PtrToString(adapter.FriendlyName), kind: adapter.IfType,
				up: adapter.OperStatus == windows.IfOperStatusUp, ipv4Metric: adapter.Ipv4Metric, ipv6Metric: adapter.Ipv6Metric}
			adapters[adapter.IfIndex] = entry
			if adapter.Ipv6IfIndex != 0 {
				adapters[adapter.Ipv6IfIndex] = entry
			}
		}
		runtime.KeepAlive(buffer)
		return adapters, nil
	}
	return nil, errors.New("adapter table changed repeatedly")
}

func selectUpstreamInterface(routes []windows.MibIpForwardRow2, adapters map[uint32]upstreamAdapter, ipv6 bool) (string, error) {
	family := uint16(windows.AF_INET)
	if ipv6 {
		family = windows.AF_INET6
	}
	var selected string
	var selectedIndex uint32
	lowestMetric := ^uint64(0)
	for _, route := range routes {
		if route.DestinationPrefix.PrefixLength != 0 || route.DestinationPrefix.Prefix.Family != family || route.Loopback != 0 || route.ValidLifetime == 0 {
			continue
		}
		adapter, found := adapters[route.InterfaceIndex]
		if !found || !adapter.up || adapter.name == "" || adapter.kind == interfaceTypeVirtual || adapter.kind == windows.IF_TYPE_TUNNEL || adapter.kind == windows.IF_TYPE_SOFTWARE_LOOPBACK {
			continue
		}
		metric := adapter.ipv4Metric
		if ipv6 {
			metric = adapter.ipv6Metric
		}
		// Use uint64: two valid Windows metrics can overflow a uint32 sum.
		total := uint64(route.Metric) + uint64(metric)
		if total < lowestMetric || total == lowestMetric && route.InterfaceIndex < selectedIndex {
			lowestMetric, selected, selectedIndex = total, adapter.name, route.InterfaceIndex
		}
	}
	if selected == "" {
		return "", errors.New("no active non-tunnel default route")
	}
	return selected, nil
}

func defaultUpstreamInterface(ctx context.Context, ipv6 bool) (string, error) {
	if err := ctx.Err(); err != nil {
		return "", err
	}
	adapters, err := upstreamAdapters()
	if err != nil {
		return "", err
	}
	var table *windows.MibIpForwardTable2
	if err = windows.GetIpForwardTable2(windows.AF_UNSPEC, &table); err != nil {
		return "", fmt.Errorf("read upstream routes: %w", err)
	}
	defer windows.FreeMibTable(unsafe.Pointer(table))
	if err = ctx.Err(); err != nil {
		return "", err
	}
	return selectUpstreamInterface(table.Rows(), adapters, ipv6)
}
