//go:build linux && !android

package host

import (
	"context"
	"time"

	"rainlink.local/host/internal/coreprocess"
	"rainlink.local/host/internal/linuxinstall"
)

const tunInspectionTimeout = 10 * time.Second

func tunAvailable(parent context.Context, core string) bool {
	if !coreprocess.Trusted(core) {
		return false
	}
	ctx, cancel := context.WithTimeout(parent, tunInspectionTimeout)
	defer cancel()
	// Inspection never starts a capture or requests authorization. The ordinary
	// host can advertise TUN only for its own fully installed, active service.
	status := linuxinstall.InspectService(ctx)
	return ctx.Err() == nil && status.State == "current" && status.Enabled && status.Active
}
