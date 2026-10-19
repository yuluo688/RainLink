//go:build linux && !android

package linuxmanage

import (
	"context"
	"encoding/json"
	"io"
	"strings"
	"testing"
	"time"

	"rainlink.local/host/internal/linuxinstall"
)

func TestManagementBoundaryRejectsParametersAndAmbiguity(t *testing.T) {
	for _, method := range []string{"status", "install", "uninstall", "recover", "cancel"} {
		value, err := parseRequest([]byte(`{"id":1,"method":"` + method + `","payload":{}}`))
		if err != nil || value.ID != 1 || value.Method != method {
			t.Fatal(value, err)
		}
	}
	for _, invalid := range []string{
		`{"id":1,"method":"install","payload":{"path":"/tmp/other"}}`,
		`{"id":1,"id":2,"method":"install"}`,
		`{"ID":1,"method":"install"}`,
		`{"id":1,"method":"install","Payload":{}}`,
		`{"id":1,"method":"start"}`,
		`{"id":0,"method":"install"}`,
		`{"id":1,"method":"install","payload":null}`,
		`{"id":1,"method":"install"} {}`,
	} {
		if _, err := parseRequest([]byte(invalid)); err == nil {
			t.Fatal("invalid request accepted", invalid)
		}
	}
}

type pendingBackend struct {
	started, cancelled, release chan struct{}
	operationErr                error
}

func (b *pendingBackend) inspect(context.Context) linuxinstall.ServiceStatus {
	return linuxinstall.ServiceStatus{ProtocolVersion: 1, State: "missing", CanManage: true, Message: "fixture"}
}

func (b *pendingBackend) change(ctx context.Context, _ string) error {
	close(b.started)
	<-ctx.Done()
	close(b.cancelled)
	<-b.release
	return b.operationErr
}

func newPending() *pendingBackend {
	return &pendingBackend{started: make(chan struct{}), cancelled: make(chan struct{}), release: make(chan struct{}),
		operationErr: &failure{"cancelled", "cancelled after rollback"}}
}

func waitFor(t *testing.T, event <-chan struct{}) {
	t.Helper()
	select {
	case <-event:
	case <-time.After(time.Second):
		t.Fatal("event did not arrive")
	}
}

func TestManagementCancellationWaitsForActualOperationExit(t *testing.T) {
	service := newPending()
	input, commands := io.Pipe()
	output, responses := io.Pipe()
	t.Cleanup(func() { commands.Close(); input.Close(); responses.Close(); output.Close() })
	done := make(chan error, 1)
	go func() { done <- serve(t.Context(), input, responses, service) }()
	send := json.NewEncoder(commands)
	if err := send.Encode(map[string]any{"id": 1, "method": "install"}); err != nil {
		t.Fatal(err)
	}
	waitFor(t, service.started)
	if err := send.Encode(map[string]any{"id": 2, "method": "cancel"}); err != nil {
		t.Fatal(err)
	}
	decoder := json.NewDecoder(output)
	var response struct {
		ID     int
		Result map[string]bool
		Error  *failure
	}
	if err := decoder.Decode(&response); err != nil || response.ID != 2 || !response.Result["requested"] {
		t.Fatal("cancel request not acknowledged", response, err)
	}
	waitFor(t, service.cancelled)
	if err := send.Encode(map[string]any{"id": 3, "method": "recover"}); err != nil {
		t.Fatal(err)
	}
	if err := decoder.Decode(&response); err != nil || response.ID != 3 || response.Error == nil || response.Error.Code != "service_busy" {
		t.Fatal("new operation overlapped rollback", response, err)
	}
	close(service.release)
	if err := decoder.Decode(&response); err != nil || response.ID != 1 || response.Error == nil || response.Error.Code != "cancelled" {
		t.Fatal("original operation did not retain cancellation", response, err)
	}
	commands.Close()
	if err := <-done; err != nil {
		t.Fatal(err)
	}
}

func TestManagementEOFWaitsForRollbackAndDoesNotHideFailures(t *testing.T) {
	service := newPending()
	input, commands := io.Pipe()
	done := make(chan error, 1)
	go func() { done <- serve(t.Context(), input, io.Discard, service) }()
	if _, err := io.WriteString(commands, "{\"id\":1,\"method\":\"uninstall\"}\n"); err != nil {
		t.Fatal(err)
	}
	waitFor(t, service.started)
	commands.Close()
	waitFor(t, service.cancelled)
	select {
	case err := <-done:
		t.Fatal("server exited before elevated worker", err)
	default:
	}
	close(service.release)
	if err := <-done; err == nil {
		t.Fatal("EOF swallowed the cancelled operation")
	}
}

func TestManagementRejectsRepeatedIdentifiers(t *testing.T) {
	service := newPending()
	if err := serve(t.Context(), strings.NewReader("{\"id\":1,\"method\":\"cancel\"}\n{\"id\":1,\"method\":\"cancel\"}\n"), io.Discard, service); err == nil {
		t.Fatal("repeated ID was accepted")
	}
}

func TestOnlyFixedInstallationVerbsAreSelected(t *testing.T) {
	for method, want := range map[string]string{"install": "install-tun", "uninstall": "uninstall-tun", "recover": "recover-tun-install"} {
		got, err := installationAction(method)
		if err != nil || got != want {
			t.Fatal(got, err)
		}
	}
	if _, err := installationAction("/tmp/command"); err == nil {
		t.Fatal("arbitrary command accepted")
	}
	var output boundedOutput
	if _, err := output.Write(make([]byte, 4097)); err == nil {
		t.Fatal("unbounded output accepted")
	}
}
