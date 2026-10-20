package host

import (
	"context"

	"rainlink.local/host/internal/coreprocess"
)

func tunAvailable(_ context.Context, core string) bool {
	return coreprocess.Trusted(core)
}
