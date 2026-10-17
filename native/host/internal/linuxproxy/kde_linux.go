//go:build linux && !android

package linuxproxy

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"golang.org/x/sys/unix"
)

var kdeSettings = []setting{
	{"", "ProxyType", true}, {"", "httpProxy", true}, {"", "httpsProxy", true},
	{"", "ftpProxy", true}, {"", "socksProxy", true}, {"", "Proxy Config Script", true},
	{"", "NoProxyFor", false}, {"", "ReversedException", true},
}

type kdeBackend struct{}

func (kdeBackend) ID() string          { return "kde" }
func (kdeBackend) Settings() []setting { return kdeSettings }
func (kdeBackend) Binding() (string, error) {
	return configurationBinding(true)
}

// IsKDE selects Plasma's configuration independently of the Qt application UI.
func IsKDE() bool {
	if os.Getenv("DBUS_SESSION_BUS_ADDRESS") == "" {
		return false
	}
	for _, desktop := range strings.Split(os.Getenv("XDG_CURRENT_DESKTOP"), ":") {
		if strings.EqualFold(strings.TrimSpace(desktop), "KDE") {
			return true
		}
	}
	return false
}

func (kdeBackend) Owned(port int) values {
	endpoint := "v:http://127.0.0.1:" + strconv.Itoa(port)
	return values{
		"/ProxyType": "v:1", "/httpProxy": endpoint, "/httpsProxy": endpoint,
		"/ftpProxy": endpoint, "/socksProxy": "v:socks://127.0.0.1:" + strconv.Itoa(port),
		"/Proxy Config Script": "v:", "/ReversedException": "v:0", "/NoProxyFor": "v:localhost,127.0.0.0/8,::1",
	}
}

func (b kdeBackend) Available(ctx context.Context) bool {
	if !IsKDE() {
		return false
	}
	response, err := b.call(ctx, "snapshot", nil)
	return err == nil && response.Available
}

func (b kdeBackend) Snapshot(ctx context.Context) (values, error) {
	response, err := b.call(ctx, "snapshot", nil)
	return response.Values, err
}

func (b kdeBackend) Write(ctx context.Context, data values) error {
	if !validKDEValues(data) {
		return errors.New("invalid KDE proxy settings")
	}
	_, err := b.call(ctx, "write", data)
	return err
}

func validKDEValues(data values) bool {
	if !validValues(kdeSettings, data) {
		return false
	}
	for _, value := range data {
		// Empty means no local override; v: also preserves a present empty string.
		if value != "" && !strings.HasPrefix(value, "v:") {
			return false
		}
	}
	return true
}

type kdeResponse struct {
	Version   int    `json:"version"`
	Available bool   `json:"available"`
	Values    values `json:"values"`
}

func kdeHelperPath() (string, error) {
	executable, err := os.Executable()
	if err != nil {
		return "", err
	}
	path := filepath.Join(filepath.Dir(executable), "rainlink-kde-proxy")
	info, err := os.Lstat(path)
	if err != nil {
		return "", errors.New("KDE proxy helper unavailable")
	}
	var stat unix.Stat_t
	if !info.Mode().IsRegular() || info.Mode().Perm()&0111 == 0 || info.Mode().Perm()&0022 != 0 || unix.Lstat(path, &stat) != nil || stat.Uid != 0 && stat.Uid != uint32(os.Geteuid()) {
		return "", errors.New("KDE proxy helper is not a trusted executable")
	}
	return path, nil
}

func (kdeBackend) call(ctx context.Context, operation string, data values) (kdeResponse, error) {
	var response kdeResponse
	path, err := kdeHelperPath()
	if err != nil {
		return response, err
	}
	root, err := configRoot()
	if err != nil {
		return response, err
	}
	request, err := json.Marshal(struct {
		Version    int    `json:"version"`
		Operation  string `json:"operation"`
		ConfigRoot string `json:"configRoot"`
		Values     values `json:"values,omitempty"`
	}{1, operation, root, data})
	if err != nil {
		return response, err
	}
	defer clear(request)
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, path)
	// Qt/KConfig receive a predictable environment; debug/plugin hooks must not
	// print original proxy credentials. All values travel through private stdin.
	command.Env = []string{"PATH=/usr/bin:/bin", "LANG=C.UTF-8", "LC_ALL=C.UTF-8"}
	for _, key := range []string{"HOME", "XDG_CONFIG_HOME", "XDG_CONFIG_DIRS", "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS"} {
		if value, exists := os.LookupEnv(key); exists {
			command.Env = append(command.Env, key+"="+value)
		}
	}
	command.Stdin = bytes.NewReader(request)
	command.WaitDelay = time.Second
	output, diagnostics := &limitedOutput{limit: 32 << 10}, &limitedOutput{limit: 4096}
	command.Stdout, command.Stderr = output, diagnostics
	err = command.Run()
	defer clear(output.buffer.Bytes())
	defer clear(diagnostics.buffer.Bytes())
	if ctx.Err() != nil {
		return response, ctx.Err()
	}
	if err != nil || output.overflow || diagnostics.overflow || diagnostics.buffer.Len() != 0 {
		return response, errors.New("KDE proxy configuration command failed")
	}
	decoder := json.NewDecoder(&output.buffer)
	decoder.DisallowUnknownFields()
	if err = decoder.Decode(&response); err != nil || response.Version != 1 || !validKDEValues(response.Values) {
		return kdeResponse{}, errors.New("invalid KDE proxy configuration response")
	}
	var extra any
	if err = decoder.Decode(&extra); err != io.EOF {
		return kdeResponse{}, errors.New("trailing KDE proxy configuration response")
	}
	return response, nil
}
