package cli_test

import (
	"bytes"
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"rainlink.local/host/internal/cli"
	"rainlink.local/host/internal/host"
)

func TestStatusContractDoesNotClaimNetworkCapabilities(t *testing.T) {
	var stdout, stderr bytes.Buffer
	if code := cli.Run([]string{"status"}, &stdout, &stderr); code != 0 {
		t.Fatalf("status exited %d: %s", code, &stderr)
	}
	var status host.Status
	decoder := json.NewDecoder(&stdout)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&status); err != nil {
		t.Fatal(err)
	}
	if status.ProtocolVersion != 1 || status.Host.Version == "" || status.Host.Platform == "" {
		t.Fatalf("incomplete status: %+v", status)
	}
	if status.Core.State != "not_configured" || status.Core.Version != nil ||
		status.Capabilities != (host.Capabilities{}) {
		t.Fatalf("unconfigured host claimed network capabilities: %+v", status)
	}
	if stderr.Len() != 0 {
		t.Fatalf("unexpected diagnostics: %s", &stderr)
	}
}

func TestRejectsUnsupportedCommandsWithoutEchoingSecrets(t *testing.T) {
	for _, args := range [][]string{nil, {"connect"}, {"status", "password=secret"}, {"password=secret"}} {
		var stdout, stderr bytes.Buffer
		if code := cli.Run(args, &stdout, &stderr); code != 2 {
			t.Fatalf("expected usage error for %v, got %d", args, code)
		}
		if stdout.Len() != 0 || strings.Contains(stderr.String(), "secret") {
			t.Fatalf("invalid command emitted protocol data or secrets")
		}
	}
}

type brokenWriter struct{}

func (brokenWriter) Write([]byte) (int, error) { return 0, errors.New("closed pipe") }

func TestOutputFailureIsNotReportedAsSuccess(t *testing.T) {
	for _, command := range []string{"status", "--version"} {
		var stderr bytes.Buffer
		if code := cli.Run([]string{command}, brokenWriter{}, &stderr); code != 1 {
			t.Fatalf("expected output failure, got %d", code)
		}
	}
}
