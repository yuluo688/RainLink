//go:build linux && !android

package securestore

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"rainlink.local/host/internal/privatefs"
)

const secretToolPath = "/usr/bin/secret-tool"

type secretCommand func(context.Context, string, []string, []byte) ([]byte, bool, error)

type linuxKeyService struct {
	run       secretCommand
	directory func() (string, error)
}

// NewLinuxStore uses libsecret's CLI and a private, key-free interprocess lock.
// A missing or locked Secret Service is an error; there is no plaintext fallback.
func NewLinuxStore() Store {
	return Store{Keys: &linuxKeyService{run: runSecretCommand, directory: keyLockDirectory}}
}

func keyLockDirectory() (string, error) {
	root, err := privatefs.UserStateRoot()
	if err != nil {
		return "", err
	}
	return filepath.Join(root, "RainLink", "keys"), nil
}

func acquireKeyLock(ctx context.Context, directory string) (func() error, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	dir, err := privatefs.Open(directory)
	if err != nil {
		return nil, err
	}
	release, err := dir.Lock(ctx, "credential-key.lock")
	if err != nil {
		return nil, errors.Join(err, dir.Close())
	}
	return func() error { return errors.Join(release(), dir.Close()) }, nil
}

func (s *linuxKeyService) Key(ctx context.Context, create bool) (key []byte, err error) {
	if err = ctx.Err(); err != nil {
		return nil, err
	}
	// The service owns its own bound as well as respecting the caller's cancel.
	ctx, cancel := context.WithTimeout(ctx, 12*time.Second)
	defer cancel()
	directory, err := s.directory()
	if err != nil {
		return nil, fmt.Errorf("locate key lock: %w", errors.Join(ErrUnavailable, err))
	}
	release, err := acquireKeyLock(ctx, directory)
	if err != nil {
		return nil, fmt.Errorf("acquire key lock: %w", errors.Join(ErrUnavailable, err))
	}
	defer func() {
		if unlockErr := release(); unlockErr != nil {
			clear(key)
			key = nil
			err = errors.Join(err, fmt.Errorf("release key lock: %w", unlockErr))
		}
	}()
	attributes := []string{"application", "dev.rainlink.RainLink", "purpose", "credential-master-v1"}
	lookup := func() ([]byte, bool, error) {
		output, missing, lookupErr := s.run(ctx, secretToolPath, append([]string{"lookup"}, attributes...), nil)
		defer clear(output)
		if lookupErr != nil {
			return nil, false, fmt.Errorf("read system credential key: %w", errors.Join(ErrUnavailable, lookupErr))
		}
		if missing {
			// libsecret lookup also returns an empty exit 1 when an existing item
			// is locked and its unlock prompt cannot run. Search without --unlock
			// confirms true absence before allowing a new key or reporting key loss.
			found, _, searchErr := s.run(ctx, secretToolPath, append([]string{"search", "--all"}, attributes...), nil)
			defer clear(found)
			if searchErr != nil || len(bytes.TrimSpace(found)) != 0 {
				return nil, false, fmt.Errorf("system credential key is not readable: %w", errors.Join(ErrUnavailable, searchErr))
			}
			return nil, true, nil
		}
		decoded, decodeErr := base64.StdEncoding.Strict().DecodeString(strings.TrimSpace(string(output)))
		if decodeErr != nil || len(decoded) != keyBytes {
			clear(decoded)
			return nil, false, fmt.Errorf("invalid system credential key: %w", ErrUnavailable)
		}
		return decoded, false, nil
	}
	key, missing, err := lookup()
	if err != nil || !missing {
		return key, err
	}
	if !create {
		return nil, ErrMissingKey
	}
	generated := make([]byte, keyBytes)
	defer clear(generated)
	if _, err = rand.Read(generated); err != nil {
		return nil, fmt.Errorf("generate system credential key: %w", err)
	}
	encoded := []byte(base64.StdEncoding.EncodeToString(generated))
	defer clear(encoded)
	output, missing, err := s.run(ctx, secretToolPath, append([]string{"store", "--label=RainLink credential key"}, attributes...), encoded)
	clear(output)
	if err != nil || missing {
		return nil, fmt.Errorf("save system credential key: %w", errors.Join(ErrUnavailable, err))
	}
	key, missing, err = lookup()
	if err != nil || missing || subtle.ConstantTimeCompare(key, generated) != 1 {
		clear(key)
		return nil, fmt.Errorf("system credential key readback failed: %w", errors.Join(ErrUnavailable, err))
	}
	return key, nil
}

func runSecretCommand(ctx context.Context, path string, args []string, input []byte) ([]byte, bool, error) {
	command := exec.CommandContext(ctx, path, args...)
	command.Stdin = bytes.NewReader(input)
	command.WaitDelay = time.Second
	limit := 256
	if len(args) > 0 && args[0] == "search" {
		limit = 4096
	}
	output, stderr := &boundedOutput{limit: limit}, &boundedOutput{limit: 4096}
	command.Stdout, command.Stderr = output, stderr
	err := command.Run()
	// Diagnostic output may include sensitive library details; do not return it.
	defer clear(stderr.buffer.Bytes())
	if ctx.Err() != nil {
		clear(output.buffer.Bytes())
		return nil, false, ctx.Err()
	}
	if output.overflow || stderr.overflow {
		clear(output.buffer.Bytes())
		return nil, false, errors.New("key service output exceeds limit")
	}
	var exit *exec.ExitError
	if len(args) > 0 && args[0] == "lookup" && errors.As(err, &exit) && exit.ExitCode() == 1 && output.buffer.Len() == 0 && stderr.buffer.Len() == 0 {
		return nil, true, nil
	}
	if err != nil {
		clear(output.buffer.Bytes())
		return nil, false, fmt.Errorf("secret service command failed: %w", err)
	}
	return output.buffer.Bytes(), false, nil
}
