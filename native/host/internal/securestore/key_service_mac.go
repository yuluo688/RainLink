package securestore

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os/exec"
	"path/filepath"
	"time"
)

const (
	macKeyTimeout         = 12 * time.Second
	macKeyResponseLimit   = 512
	macKeyDiagnosticLimit = 4096
)

type macKeyCommand func(context.Context, string, []byte) ([]byte, error)

type macKeyService struct {
	helper string
	run    macKeyCommand
}

// NewMacStore uses the bundled Security.framework helper through private pipes.
// Only encryption may create a key. The helper never receives a node password,
// and its key output must never be copied into public logs or command arguments.
func NewMacStore(helper string) Store {
	return Store{Keys: &macKeyService{helper: helper, run: runMacKeyCommand}}
}

func (s *macKeyService) Key(ctx context.Context, create bool) ([]byte, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if !filepath.IsAbs(s.helper) || s.run == nil {
		return nil, fmt.Errorf("locate macOS key service: %w", ErrUnavailable)
	}
	ctx, cancel := context.WithTimeout(ctx, macKeyTimeout)
	defer cancel()
	input := []byte(`{"version":1,"createIfMissing":false}`)
	if create {
		input = []byte(`{"version":1,"createIfMissing":true}`)
	}
	output, err := s.run(ctx, s.helper, input)
	defer clear(output)
	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	if err != nil {
		return nil, fmt.Errorf("read macOS credential key: %w", ErrUnavailable)
	}
	if len(output) > macKeyResponseLimit {
		return nil, fmt.Errorf("oversized macOS key service response: %w", ErrUnavailable)
	}
	var reply struct {
		Version int    `json:"version"`
		Status  string `json:"status"`
		Key     []byte `json:"key,omitempty"`
	}
	decoder := json.NewDecoder(bytes.NewReader(output))
	decoder.DisallowUnknownFields()
	decodeErr := decoder.Decode(&reply)
	if decodeErr != nil || reply.Version != 1 || decoder.Decode(new(any)) != io.EOF {
		clear(reply.Key)
		return nil, fmt.Errorf("invalid macOS key service response: %w", ErrUnavailable)
	}
	if reply.Status == "ok" && len(reply.Key) == keyBytes {
		return reply.Key, nil
	}
	clear(reply.Key)
	if reply.Status == "missing" && !create && len(reply.Key) == 0 {
		return nil, ErrMissingKey
	}
	if reply.Status == "cancelled" && len(reply.Key) == 0 {
		return nil, context.Canceled
	}
	return nil, fmt.Errorf("macOS key service denied access: %w", ErrUnavailable)
}

func runMacKeyCommand(ctx context.Context, helper string, input []byte) ([]byte, error) {
	command := exec.CommandContext(ctx, helper)
	command.Stdin = bytes.NewReader(input)
	command.WaitDelay = time.Second
	output := &boundedOutput{limit: macKeyResponseLimit}
	stderr := &boundedOutput{limit: macKeyDiagnosticLimit}
	command.Stdout, command.Stderr = output, stderr
	err := command.Run()
	defer clear(stderr.buffer.Bytes())
	if ctx.Err() != nil {
		clear(output.buffer.Bytes())
		return nil, ctx.Err()
	}
	if err != nil || output.overflow || stderr.overflow {
		clear(output.buffer.Bytes())
		return nil, ErrUnavailable
	}
	return output.buffer.Bytes(), nil
}
