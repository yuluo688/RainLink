//go:build !windows && (!linux || android)

package session

import (
	"context"
	"errors"
)

func defaultUpstreamInterface(context.Context, bool) (string, error) {
	return "", errors.New("upstream interface selection is unavailable on this platform")
}
