//go:build !windows && (!linux || android)

package session

import (
	"context"
	"errors"
)

func seal(ctx context.Context, plain []byte, id string) (string, error) {
	if err := ctx.Err(); err != nil {
		return "", err
	}
	return "", errors.New("secure storage is not implemented on this platform")
}

func unseal(ctx context.Context, cipher, id string) ([]byte, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	return nil, errors.New("secure storage is not implemented on this platform")
}
