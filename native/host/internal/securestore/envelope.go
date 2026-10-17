// Package securestore keeps encrypted records separate from OS key storage.
package securestore

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"
)

// MaxPlaintextBytes bounds one encrypted record, including recovery metadata.
const MaxPlaintextBytes = 16 << 10

const (
	keyBytes       = 32
	maxPlaintext   = MaxPlaintextBytes
	maxCiphertext  = 32 << 10
	envelopePrefix = "rls1."
)

var (
	// ErrUnavailable means the OS key service could not be reached or unlocked.
	ErrUnavailable = errors.New("system key service unavailable")
	// ErrMissingKey never causes an existing ciphertext to create a replacement key.
	ErrMissingKey = errors.New("credential encryption key is missing")
	// ErrInvalidRecord includes invalid versions, input limits and failed authentication.
	ErrInvalidRecord = errors.New("invalid encrypted credential record")
)

// KeyService returns an owned copy of the per-user installation key. The caller
// clears it after use. Only encryption may create it.
type KeyService interface {
	Key(ctx context.Context, create bool) ([]byte, error)
}

// Store authenticates each record with its node or subscription identity.
type Store struct {
	Keys KeyService
}

func (s Store) aead(ctx context.Context, create bool) (cipher.AEAD, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if s.Keys == nil {
		return nil, ErrUnavailable
	}
	key, err := s.Keys.Key(ctx, create)
	defer clear(key)
	if err != nil {
		return nil, err
	}
	if len(key) != keyBytes {
		return nil, fmt.Errorf("invalid system key length: %w", ErrUnavailable)
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("initialize credential cipher: %w", err)
	}
	return cipher.NewGCM(block)
}

// Seal produces a versioned AES-256-GCM record; the key stays in the OS service.
func (s Store) Seal(ctx context.Context, plain []byte, id string) (string, error) {
	if err := ctx.Err(); err != nil {
		return "", err
	}
	if len(id) == 0 || len(id) > 128 || len(plain) == 0 || len(plain) > maxPlaintext {
		return "", ErrInvalidRecord
	}
	aead, err := s.aead(ctx, true)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, aead.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return "", fmt.Errorf("generate credential nonce: %w", err)
	}
	if err := ctx.Err(); err != nil {
		return "", err
	}
	sealed := aead.Seal(nonce, nonce, plain, []byte("RainLink/credentials/v1/"+id))
	return envelopePrefix + base64.RawStdEncoding.EncodeToString(sealed), nil
}

// Unseal rejects malformed or foreign records before requesting an OS key.
func (s Store) Unseal(ctx context.Context, record, id string) ([]byte, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if len(id) == 0 || len(id) > 128 || len(record) > maxCiphertext || !strings.HasPrefix(record, envelopePrefix) {
		return nil, ErrInvalidRecord
	}
	raw, err := base64.RawStdEncoding.Strict().DecodeString(strings.TrimPrefix(record, envelopePrefix))
	if err != nil || len(raw) < 12+16+1 || len(raw) > maxPlaintext+12+16 {
		return nil, ErrInvalidRecord
	}
	aead, err := s.aead(ctx, false)
	if err != nil {
		return nil, err
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	plain, err := aead.Open(nil, raw[:aead.NonceSize()], raw[aead.NonceSize():], []byte("RainLink/credentials/v1/"+id))
	if err != nil {
		return nil, ErrInvalidRecord
	}
	return plain, nil
}
