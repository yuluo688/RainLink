//go:build (!linux && !windows) || android

package host

import "context"

func tunAvailable(context.Context, string) bool { return false }
