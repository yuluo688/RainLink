//go:build linux && !android

package session

import (
	"context"

	"rainlink.local/host/internal/securestore"
)

func seal(ctx context.Context, plain []byte, id string) (string, error) {
	return securestore.NewLinuxStore().Seal(ctx, plain, id)
}

func unseal(ctx context.Context, cipher, id string) ([]byte, error) {
	return securestore.NewLinuxStore().Unseal(ctx, cipher, id)
}
