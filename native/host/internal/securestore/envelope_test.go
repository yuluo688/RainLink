package securestore

import (
	"bytes"
	"context"
	"encoding/base64"
	"errors"
	"strings"
	"testing"
)

type keyFunc func(context.Context, bool) ([]byte, error)

func (f keyFunc) Key(ctx context.Context, create bool) ([]byte, error) { return f(ctx, create) }

func fixtureStore(t *testing.T, calls *[]bool) Store {
	t.Helper()
	return Store{Keys: keyFunc(func(_ context.Context, create bool) ([]byte, error) {
		*calls = append(*calls, create)
		return bytes.Repeat([]byte{0x79}, keyBytes), nil
	})}
}

func TestEnvelopeRoundTripAndBinding(t *testing.T) {
	var calls []bool
	store := fixtureStore(t, &calls)
	plain := []byte(`{"password":"test-only-secret","username":"测试"}`)
	first, err := store.Seal(t.Context(), plain, "node-a")
	if err != nil {
		t.Fatal(err)
	}
	second, err := store.Seal(t.Context(), plain, "node-a")
	if err != nil || first == second || strings.Contains(first, "test-only-secret") {
		t.Fatalf("non-random or failed seal: %v", err)
	}
	got, err := store.Unseal(t.Context(), first, "node-a")
	if err != nil || !bytes.Equal(got, plain) {
		t.Fatalf("round trip failed: %v", err)
	}
	if _, err = store.Unseal(t.Context(), first, "node-b"); !errors.Is(err, ErrInvalidRecord) {
		t.Fatalf("identity binding lost: %v", err)
	}
	raw, err := base64.RawStdEncoding.DecodeString(strings.TrimPrefix(first, envelopePrefix))
	if err != nil {
		t.Fatal(err)
	}
	for _, index := range []int{0, 12, len(raw) - 1} {
		changed := bytes.Clone(raw)
		changed[index] ^= 1
		if _, err = store.Unseal(t.Context(), envelopePrefix+base64.RawStdEncoding.EncodeToString(changed), "node-a"); !errors.Is(err, ErrInvalidRecord) {
			t.Fatalf("tampering byte %d accepted: %v", index, err)
		}
	}
	for i, create := range calls {
		if create != (i < 2) {
			t.Fatalf("decryption may not create keys; calls=%v", calls)
		}
	}
}

func TestEnvelopeValidationBeforeKeyAccess(t *testing.T) {
	var calls []bool
	store := fixtureStore(t, &calls)
	for _, test := range []struct {
		name string
		id   string
		data []byte
	}{
		{"empty-id", "", []byte{1}},
		{"long-id", strings.Repeat("x", 129), []byte{1}},
		{"empty-plain", "id", nil},
		{"large-plain", "id", make([]byte, maxPlaintext+1)},
	} {
		t.Run(test.name, func(t *testing.T) {
			if _, err := store.Seal(t.Context(), test.data, test.id); !errors.Is(err, ErrInvalidRecord) {
				t.Fatalf("input accepted: %v", err)
			}
		})
	}
	for _, record := range []string{"", "rls2.data", envelopePrefix + "!", envelopePrefix + "AA", envelopePrefix + strings.Repeat("A", maxCiphertext)} {
		if _, err := store.Unseal(t.Context(), record, "id"); !errors.Is(err, ErrInvalidRecord) {
			t.Fatalf("invalid record accepted: %v", err)
		}
	}
	if len(calls) != 0 {
		t.Fatal("invalid input reached the OS key service")
	}
	plain := bytes.Repeat([]byte{0x41}, maxPlaintext)
	record, err := store.Seal(t.Context(), plain, strings.Repeat("i", 128))
	if err != nil {
		t.Fatal(err)
	}
	got, err := store.Unseal(t.Context(), record, strings.Repeat("i", 128))
	if err != nil || !bytes.Equal(got, plain) {
		t.Fatalf("valid maximum rejected: %v", err)
	}
}

func TestEnvelopeKeyFailuresAndCancellation(t *testing.T) {
	var calls []bool
	record, err := fixtureStore(t, &calls).Seal(t.Context(), []byte("credential"), "id")
	if err != nil {
		t.Fatal(err)
	}
	for _, failure := range []error{ErrUnavailable, ErrMissingKey, context.Canceled, context.DeadlineExceeded} {
		store := Store{Keys: keyFunc(func(_ context.Context, create bool) ([]byte, error) {
			if create {
				t.Fatal("decryption attempted to recreate a lost key")
			}
			return nil, failure
		})}
		if _, err = store.Unseal(t.Context(), record, "id"); !errors.Is(err, failure) {
			t.Fatalf("failure was lost: %v", err)
		}
	}
	for _, length := range []int{0, 16, 31, 33} {
		key := make([]byte, length)
		store := Store{Keys: keyFunc(func(context.Context, bool) ([]byte, error) { return key, nil })}
		if _, err := store.Seal(t.Context(), []byte("credential"), "id"); !errors.Is(err, ErrUnavailable) {
			t.Fatalf("key length %d accepted: %v", length, err)
		}
	}
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	store := Store{Keys: keyFunc(func(context.Context, bool) ([]byte, error) {
		t.Fatal("cancelled operation reached OS service")
		return nil, nil
	})}
	if _, err = store.Seal(ctx, []byte("credential"), "id"); !errors.Is(err, context.Canceled) {
		t.Fatalf("cancel not preserved: %v", err)
	}
	if _, err = store.Unseal(ctx, record, "id"); !errors.Is(err, context.Canceled) {
		t.Fatalf("cancel not preserved: %v", err)
	}
	if _, err = (Store{}).Seal(t.Context(), []byte("credential"), "id"); !errors.Is(err, ErrUnavailable) {
		t.Fatalf("nil service: %v", err)
	}
}
