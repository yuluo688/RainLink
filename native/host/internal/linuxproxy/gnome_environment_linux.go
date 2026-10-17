//go:build linux && !android

package linuxproxy

import (
	"bytes"
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"golang.org/x/sys/unix"
)

const gdbusPath = "/usr/bin/gdbus"

// dconf reads local files but sends writes to an activated session service. If
// their configuration directories differ, readback and rollback would inspect
// the wrong database. Verify the service before touching any proxy settings.
func verifyDconf(ctx context.Context) error {
	if !hasDconfEnvironment() {
		return ErrUnavailable
	}
	args := []string{"call", "--session", "--dest", "org.freedesktop.DBus", "--object-path", "/org/freedesktop/DBus", "--method"}
	if _, err := run(ctx, gdbusPath, append(args, "org.freedesktop.DBus.StartServiceByName", "ca.desrt.dconf", "0"), nil, 128); err != nil {
		return err
	}
	output, err := run(ctx, gdbusPath, append(args, "org.freedesktop.DBus.GetConnectionUnixProcessID", "ca.desrt.dconf"), nil, 128)
	if err != nil {
		return err
	}
	result := strings.TrimSpace(string(output))
	if !strings.HasPrefix(result, "(uint32 ") || !strings.HasSuffix(result, ",)") {
		return errors.New("invalid dconf service identity")
	}
	pid, err := strconv.Atoi(strings.TrimSuffix(strings.TrimPrefix(result, "(uint32 "), ",)"))
	if err != nil || pid < 2 {
		return errors.New("invalid dconf service PID")
	}
	path := "/proc/" + strconv.Itoa(pid)
	var stat unix.Stat_t
	if err = unix.Stat(path, &stat); err != nil || stat.Uid != uint32(os.Geteuid()) {
		return errors.New("dconf service user cannot be verified")
	}
	file, err := os.Open(path + "/environ")
	if err != nil {
		return errors.New("dconf service environment cannot be verified")
	}
	const limit = 512 << 10
	data, readErr := io.ReadAll(io.LimitReader(file, limit+1))
	err = errors.Join(readErr, file.Close())
	defer clear(data)
	if err != nil || len(data) > limit {
		return errors.New("dconf service environment exceeds limit or cannot be read")
	}
	var serviceHome, serviceConfig string
	for _, entry := range bytes.Split(data, []byte{0}) {
		if value, ok := bytes.CutPrefix(entry, []byte("HOME=")); ok && serviceHome == "" {
			serviceHome = string(value)
		}
		if value, ok := bytes.CutPrefix(entry, []byte("XDG_CONFIG_HOME=")); ok && serviceConfig == "" {
			serviceConfig = string(value)
		}
	}
	if serviceConfig == "" && serviceHome != "" {
		serviceConfig = filepath.Join(serviceHome, ".config")
	}
	config := os.Getenv("XDG_CONFIG_HOME")
	if config == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return err
		}
		config = filepath.Join(home, ".config")
	}
	if !filepath.IsAbs(config) || !filepath.IsAbs(serviceConfig) || filepath.Clean(config) != filepath.Clean(serviceConfig) {
		return errors.New("dconf service uses a different configuration directory")
	}
	return nil
}
