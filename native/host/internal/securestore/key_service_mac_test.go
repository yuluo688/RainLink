package securestore

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// A real child process exercises private pipes, bounded output and cancellation
// on every development OS; it does not access any OS keychain.
func TestMain(m *testing.M) {
	if action := os.Getenv("RAINLINK_MAC_KEY_FIXTURE"); action != "" {
		if len(os.Args) != 1 {
			os.Exit(10)
		}
		switch action {
		case "pipe":
			input, err := io.ReadAll(io.LimitReader(os.Stdin, 257))
			if err != nil || string(input) != `{"version":1,"createIfMissing":false}` {
				os.Exit(11)
			}
			fmt.Fprint(os.Stdout, `{"version":1,"status":"missing"}`)
		case "oversize":
			fmt.Fprint(os.Stdout, strings.Repeat("x", 513))
		case "stderr":
			fmt.Fprint(os.Stderr, "fixture-sensitive-diagnostic")
			os.Exit(12)
		case "hang":
			time.Sleep(time.Minute)
		default:
			os.Exit(13)
		}
		os.Exit(0)
	}
	os.Exit(m.Run())
}

func macFixtureResponse(key []byte) []byte {
	return fmt.Appendf(nil, `{"version":1,"status":"ok","key":"%s"}`, base64.StdEncoding.EncodeToString(key))
}

func TestMacKeyEnvelopeAndPrivateProtocol(t *testing.T) {
	key := bytes.Repeat([]byte{0x79}, keyBytes)
	var outputs [][]byte
	var calls []bool
	helper := filepath.Join(t.TempDir(), "rainlink-keychain")
	store := Store{Keys: &macKeyService{helper: helper, run: func(ctx context.Context, executable string, input []byte) ([]byte, error) {
		if executable != helper {
			t.Fatal("key helper was resolved through PATH")
		}
		deadline, exists := ctx.Deadline()
		if !exists || time.Until(deadline) > macKeyTimeout {
			t.Fatal("key access has no internal timeout")
		}
		var request struct {
			Version int  `json:"version"`
			Create  bool `json:"createIfMissing"`
		}
		if err := json.Unmarshal(input, &request); err != nil || request.Version != 1 || bytes.Contains(input, []byte("fixture-password")) {
			t.Fatal("key service received credentials or an invalid protocol")
		}
		calls = append(calls, request.Create)
		output := macFixtureResponse(key)
		outputs = append(outputs, output)
		return output, nil
	}}}
	sealed, err := store.Seal(t.Context(), []byte("fixture-password"), "fixture-id")
	if err != nil {
		t.Fatal(err)
	}
	plain, err := store.Unseal(t.Context(), sealed, "fixture-id")
	if err != nil || string(plain) != "fixture-password" {
		t.Fatalf("credential round trip failed: %v", err)
	}
	if len(calls) != 2 || !calls[0] || calls[1] {
		t.Fatalf("reading an encrypted record may not create a key: %v", calls)
	}
	for _, output := range outputs {
		if !bytes.Equal(output, make([]byte, len(output))) {
			t.Fatal("private helper response was not cleared")
		}
	}
}

func TestMacKeyRejectsMalformedOrUnavailableResponses(t *testing.T) {
	for _, fixture := range []struct {
		name   string
		output string
		create bool
		want   error
	}{
		{"missing", `{"version":1,"status":"missing"}`, false, ErrMissingKey},
		{"missing-after-create", `{"version":1,"status":"missing"}`, true, ErrUnavailable},
		{"denied", `{"version":1,"status":"unavailable"}`, true, ErrUnavailable},
		{"cancelled", `{"version":1,"status":"cancelled"}`, true, context.Canceled},
		{"future", `{"version":2,"status":"missing"}`, false, ErrUnavailable},
		{"unknown-field", `{"version":1,"status":"missing","extra":true}`, false, ErrUnavailable},
		{"multiple-values", `{"version":1,"status":"missing"}{}`, false, ErrUnavailable},
		{"empty-key", `{"version":1,"status":"ok","key":""}`, true, ErrUnavailable},
		{"bad-key", `{"version":1,"status":"ok","key":"!"}`, true, ErrUnavailable},
		{"short-key", `{"version":1,"status":"ok","key":"eQ=="}`, true, ErrUnavailable},
		{"unexpected-key", `{"version":1,"status":"missing","key":"eQ=="}`, false, ErrUnavailable},
		{"oversize", strings.Repeat(" ", 513), true, ErrUnavailable},
	} {
		t.Run(fixture.name, func(t *testing.T) {
			output := []byte(fixture.output)
			calls := 0
			service := macKeyService{helper: filepath.Join(t.TempDir(), "helper"), run: func(context.Context, string, []byte) ([]byte, error) {
				calls++
				return output, nil
			}}
			key, err := service.Key(t.Context(), fixture.create)
			if !errors.Is(err, fixture.want) || len(key) != 0 || calls != 1 {
				t.Fatalf("invalid result or key recreation: error=%v calls=%d", err, calls)
			}
			if !bytes.Equal(output, make([]byte, len(output))) {
				t.Fatal("failure retained a private response")
			}
		})
	}
}

func TestMacKeyCancellationAndMissingHelper(t *testing.T) {
	helper := filepath.Join(t.TempDir(), "helper")
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	service := macKeyService{helper: helper, run: func(context.Context, string, []byte) ([]byte, error) {
		t.Fatal("cancelled request started a helper")
		return nil, nil
	}}
	if _, err := service.Key(ctx, true); !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
	service.helper = "rainlink-keychain"
	if _, err := service.Key(t.Context(), true); !errors.Is(err, ErrUnavailable) {
		t.Fatal("relative helper location was accepted")
	}
	service.helper = helper
	service.run = func(context.Context, string, []byte) ([]byte, error) {
		return nil, errors.New("fixture-sensitive-diagnostic")
	}
	if _, err := service.Key(t.Context(), true); !errors.Is(err, ErrUnavailable) || strings.Contains(err.Error(), "fixture-sensitive") {
		t.Fatal("unsafe command error was exposed")
	}
	ctx, cancel = context.WithTimeout(t.Context(), 20*time.Millisecond)
	defer cancel()
	service.run = func(ctx context.Context, _ string, _ []byte) ([]byte, error) {
		<-ctx.Done()
		return nil, ctx.Err()
	}
	if _, err := service.Key(ctx, true); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal("key service lost the caller's timeout")
	}
}

func TestMacKeyRealCommandPipesAndCancellation(t *testing.T) {
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	for _, action := range []string{"pipe", "oversize", "stderr", "hang"} {
		t.Run(action, func(t *testing.T) {
			t.Setenv("RAINLINK_MAC_KEY_FIXTURE", action)
			timeout := 3 * time.Second
			if action == "hang" {
				timeout = 100 * time.Millisecond
			}
			ctx, cancel := context.WithTimeout(t.Context(), timeout)
			defer cancel()
			output, err := runMacKeyCommand(ctx, executable, []byte(`{"version":1,"createIfMissing":false}`))
			defer clear(output)
			if action == "pipe" {
				if err != nil || string(output) != `{"version":1,"status":"missing"}` {
					t.Fatalf("private pipe failed: %v", err)
				}
			} else {
				want := ErrUnavailable
				if action == "hang" {
					want = context.DeadlineExceeded
				}
				if !errors.Is(err, want) || len(output) != 0 || strings.Contains(err.Error(), "fixture-sensitive") {
					t.Fatalf("unbounded or unsafe command result: %v", err)
				}
			}
		})
	}
}
