//go:build linux && !android

package session

import (
	"context"

	"rainlink.local/host/internal/linuxnet"
)

func defaultUpstreamInterface(ctx context.Context, ipv6 bool) (string, error) {
	return linuxnet.Upstream(ctx, ipv6)
}
