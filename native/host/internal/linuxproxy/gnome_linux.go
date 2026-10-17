//go:build linux && !android

package linuxproxy

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

const (
	gsettingsPath   = "/usr/bin/gsettings"
	dconfPath       = "/usr/bin/dconf"
	schemaPrefix    = "org.gnome.system.proxy"
	maxSettingBytes = 2048
)

type setting struct {
	section, key string
	routing      bool
}

var settings = []setting{
	{"", "mode", true}, {"", "autoconfig-url", true}, {"", "use-same-proxy", true}, {"", "ignore-hosts", false},
	{"http", "host", true}, {"http", "port", true}, {"http", "use-authentication", true},
	{"http", "authentication-user", true}, {"http", "authentication-password", true},
	{"https", "host", true}, {"https", "port", true},
	{"socks", "host", true}, {"socks", "port", true},
	{"ftp", "host", true}, {"ftp", "port", true},
}

func (s setting) id() string { return s.section + "/" + s.key }
func (s setting) schema() string {
	if s.section == "" {
		return schemaPrefix
	}
	return schemaPrefix + "." + s.section
}

type values map[string]string

type backend interface {
	ID() string
	Settings() []setting
	Owned(int) values
	Binding() (string, error)
	Available(context.Context) bool
	Snapshot(context.Context) (values, error)
	Write(context.Context, values) error
}

type gsettingsBackend struct{}

func (gsettingsBackend) ID() string            { return "gnome" }
func (gsettingsBackend) Settings() []setting   { return settings }
func (gsettingsBackend) Owned(port int) values { return ownedValues(port) }
func (gsettingsBackend) Binding() (string, error) {
	return configurationBinding(false)
}

// IsGNOME rejects unverified desktops and process-local GSettings backends.
func IsGNOME() bool {
	if !hasDconfEnvironment() {
		return false
	}
	for _, desktop := range strings.Split(os.Getenv("XDG_CURRENT_DESKTOP"), ":") {
		if strings.EqualFold(strings.TrimSpace(desktop), "GNOME") {
			return true
		}
	}
	return false
}

// Recovery may run after a desktop change, but must still read and write the
// same persistent backend. A memory backend must never retire a dconf journal.
func hasDconfEnvironment() bool {
	value := os.Getenv("GSETTINGS_BACKEND")
	return os.Getenv("DBUS_SESSION_BUS_ADDRESS") != "" && (value == "" || value == "dconf")
}

func (gsettingsBackend) Available(ctx context.Context) bool {
	if !IsGNOME() {
		return false
	}
	for _, path := range []string{gsettingsPath, dconfPath, gdbusPath} {
		info, err := os.Stat(path)
		if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0111 == 0 {
			return false
		}
	}
	if verifyDconf(ctx) != nil {
		return false
	}
	for _, item := range settings {
		output, err := run(ctx, gsettingsPath, []string{"writable", item.schema(), item.key}, nil, maxSettingBytes)
		if err != nil || strings.TrimSpace(string(output)) != "true" {
			return false
		}
	}
	return true
}

func (gsettingsBackend) Snapshot(ctx context.Context) (values, error) {
	if err := verifyDconf(ctx); err != nil {
		return nil, err
	}
	result := make(values, len(settings))
	for _, item := range settings {
		// Preserve unset keys instead of installing new persistent schema defaults.
		output, err := run(ctx, dconfPath, []string{"read", "/system/proxy/" + strings.TrimPrefix(item.id(), "/")}, nil, maxSettingBytes)
		if err != nil {
			return nil, fmt.Errorf("read GNOME proxy setting: %w", err)
		}
		value := strings.TrimSpace(string(output))
		clear(output)
		if strings.ContainsAny(value, "\r\n\x00") {
			return nil, errors.New("invalid GNOME proxy setting")
		}
		result[item.id()] = value
	}
	return result, nil
}

func (gsettingsBackend) Write(ctx context.Context, data values) error {
	if err := verifyDconf(ctx); err != nil {
		return err
	}
	if len(data) != len(settings) {
		return errors.New("incomplete GNOME proxy settings")
	}
	var buffer bytes.Buffer
	var resets []string
	setCount := 0
	for _, section := range []string{"", "http", "https", "socks", "ftp"} {
		header := section
		if header == "" {
			header = "/"
		}
		buffer.WriteString("[" + header + "]\n")
		for _, item := range settings {
			if item.section != section {
				continue
			}
			value, ok := data[item.id()]
			if !ok || len(value) > maxSettingBytes || strings.ContainsAny(value, "\r\n\x00") {
				return errors.New("invalid GNOME proxy value")
			}
			if value == "" {
				resets = append(resets, "/system/proxy/"+strings.TrimPrefix(item.id(), "/"))
				continue
			}
			buffer.WriteString(item.key + "=" + value + "\n")
			setCount++
		}
		buffer.WriteByte('\n')
	}
	// One dconf changeset keeps mode and endpoints in the same backend commit.
	defer clear(buffer.Bytes())
	if setCount > 0 {
		if _, err := run(ctx, dconfPath, []string{"load", "/system/proxy/"}, buffer.Bytes(), 256); err != nil {
			return err
		}
	}
	// dconf load cannot represent resets. Recovery persists the destination
	// before this sequence so an interrupted reset can be retried safely.
	for _, path := range resets {
		if _, err := run(ctx, dconfPath, []string{"reset", path}, nil, 256); err != nil {
			return err
		}
	}
	return nil
}

func ownedValues(port int) values {
	result := values{
		"/mode": "'manual'", "/autoconfig-url": "''", "/use-same-proxy": "false",
		"/ignore-hosts":           "['localhost', '127.0.0.0/8', '::1']",
		"http/use-authentication": "false", "http/authentication-user": "''", "http/authentication-password": "''",
	}
	for _, section := range []string{"http", "https", "socks"} {
		result[section+"/host"] = "'127.0.0.1'"
		result[section+"/port"] = strconv.Itoa(port)
	}
	// Do not leave an unrelated FTP route active in manual mode.
	result["ftp/host"], result["ftp/port"] = "''", "0"
	return result
}

type limitedOutput struct {
	buffer   bytes.Buffer
	limit    int
	overflow bool
}

func (b *limitedOutput) Write(data []byte) (int, error) {
	if len(data) > b.limit-b.buffer.Len() {
		b.overflow = true
		return 0, errors.New("GNOME proxy output exceeds limit")
	}
	return b.buffer.Write(data)
}

func run(ctx context.Context, path string, args []string, input []byte, limit int) ([]byte, error) {
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, path, args...)
	command.Env = append(os.Environ(), "GSETTINGS_BACKEND=dconf")
	command.Stdin = bytes.NewReader(input)
	command.WaitDelay = time.Second
	output, diagnostics := &limitedOutput{limit: limit}, &limitedOutput{limit: 4096}
	command.Stdout, command.Stderr = output, diagnostics
	err := command.Run()
	defer clear(diagnostics.buffer.Bytes())
	if ctx.Err() != nil {
		clear(output.buffer.Bytes())
		return nil, ctx.Err()
	}
	if output.overflow || diagnostics.overflow {
		clear(output.buffer.Bytes())
		return nil, errors.New("GNOME proxy output exceeds limit")
	}
	// dconf may exit 0 after a failed commit. Any diagnostic means the operation
	// is uncertain; callers retain the recovery record and verify/rollback.
	if err != nil || diagnostics.buffer.Len() != 0 {
		clear(output.buffer.Bytes())
		return nil, errors.New("GNOME proxy command failed")
	}
	return output.buffer.Bytes(), nil
}
