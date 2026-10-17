package session

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"rainlink.local/host/internal/securestore"
)

func TestCredentialFailuresAreActionableAndRedacted(t *testing.T) {
	for _, test := range []struct {
		cause error
		code  string
	}{
		{securestore.ErrUnavailable, "credential_service_unavailable"},
		{securestore.ErrMissingKey, "credential_key_missing"},
		{context.Canceled, "cancelled"},
		{context.DeadlineExceeded, "credential_service_timeout"},
		{securestore.ErrInvalidRecord, "fallback"},
		{errors.New("private-keyring-output"), "fallback"},
	} {
		failure := credentialFailure(errors.Join(test.cause, errors.New("private-keyring-output")), "fallback", "无法读取凭据")
		var public *Failure
		if !errors.As(failure, &public) || public.Code != test.code || strings.Contains(public.Message, "private-keyring-output") {
			t.Fatalf("unsafe credential response: %v", failure)
		}
	}
}

func TestCancelledCredentialCommandsAndTarget(t *testing.T) {
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	manager := New("", t.TempDir())
	for _, method := range []string{"protect", "reveal"} {
		payload := `{"id":"fixture","username":"fixture","password":"fixture"}`
		if method == "reveal" {
			payload = `{"id":"fixture","cipher":"fixture"}`
		}
		result, err := manager.execute(ctx, request{ID: 1, Method: method, Payload: json.RawMessage(payload)})
		var failure *Failure
		if result != nil || !errors.As(err, &failure) || failure.Code != "cancelled" {
			t.Fatalf("cancelled %s returned %v: %v", method, result, err)
		}
	}
	if _, err := readNodeCredentials(ctx, Node{ID: "fixture"}); err == nil {
		t.Fatal("cancelled target accepted")
	}
}
