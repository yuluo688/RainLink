// Package coreprocess owns a core and, for Windows TUN, its elevated guardian.
package coreprocess

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"os"
	"os/exec"
	"runtime"
)

// ErrPermissionDenied distinguishes a declined UAC prompt from core failure.
var ErrPermissionDenied = errors.New("TUN authorization was declined")

// Process includes the exit guard; callers must Wait before Close.
type Process interface {
	Kill() error
	Wait() error
	Close()
}

type localProcess struct {
	command *exec.Cmd
	cleanup func()
}

func (p *localProcess) Kill() error { return p.command.Process.Kill() }
func (p *localProcess) Wait() error { return p.command.Wait() }
func (p *localProcess) Close()      { p.cleanup() }

// Start never puts configuration or secrets in argv or temporary files.
func Start(ctx context.Context, path string, config []byte, stdout, stderr io.Writer, tun bool) (Process, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if tun {
		return startElevated(ctx, path, config, stdout, stderr)
	}
	command := exec.Command(path, "run", "-c", "stdin")
	hideWindow(command)
	command.Stdin = bytes.NewReader(config)
	command.Stdout, command.Stderr = stdout, stderr
	cleanup, err := startOwned(command)
	if err != nil {
		return nil, err
	}
	return &localProcess{command: command, cleanup: cleanup}, nil
}

// Trusted reports whether the core matches this host's locked release. TUN
// never elevates an arbitrary executable or a user-replaced core.
func Trusted(path string) bool {
	file, err := os.Open(path)
	if err != nil {
		return false
	}
	defer file.Close()
	return TrustedFile(file)
}

// TrustedFile verifies a pinned executable inode before an elevated helper
// passes that same file through ExtraFiles. It never reopens a mutable path.
func TrustedFile(file *os.File) bool {
	expected := lockedCoreHash()
	if expected == "" || file == nil {
		return false
	}
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return false
	}
	digest := sha256.New()
	_, err := io.Copy(digest, file)
	_, seekErr := file.Seek(0, io.SeekStart)
	return err == nil && seekErr == nil && hex.EncodeToString(digest.Sum(nil)) == expected
}

// Code signing changes Mach-O bytes. The macOS builder verifies the unsigned
// core against the source lock, signs that copy, then pins its exact digest into
// the host at link time. No runtime path, environment or manifest can override it.
var signedDarwinCoreSHA256 string

func coreHash(platform string) string {
	if platform == "darwin" && signedDarwinCoreSHA256 != "" {
		raw, err := hex.DecodeString(signedDarwinCoreSHA256)
		if err != nil || len(raw) != sha256.Size {
			return ""
		}
		return hex.EncodeToString(raw)
	}
	return expectedCoreSHA256[platform+"-"+runtime.GOARCH]
}

func lockedCoreHash() string { return coreHash(runtime.GOOS) }
