// Package mobileconfig exposes the shared validated compiler to mobile bindings.
// It deliberately exposes no desktop process or system-proxy management API.
package mobileconfig

import (
	"context"
	"encoding/json"
	"net"
	"net/http"
	"time"

	"rainlink.local/host/internal/session"
)

// Prepared and Telemetry are Go-only contracts used by the embedded runtime.
type Prepared = session.MobileConfiguration
type Telemetry = session.Telemetry
type Logs = session.MobileLogs
type Connections = session.MobileConnections

// NewLogs creates the same bounded credential-filtered log stream as desktop.
func NewLogs(secrets []string) *Logs {
	return session.NewMobileLogs(secrets)
}

// NewConnections shares the desktop telemetry contract without lifecycle APIs.
func NewConnections(prepared Prepared, client *http.Client, logs *Logs) *Connections {
	return session.NewMobileConnections(prepared, client, logs)
}

// Prepare keeps secrets in native memory without an intermediate JSON copy.
func Prepare(request string, tunnel bool) (Prepared, error) {
	return session.CompileMobile([]byte(request), tunnel)
}

// Probe observes the egress through the same selected local proxy as desktop.
func Probe(ctx context.Context, proxyPort int) Telemetry {
	return session.ProbeTelemetry(ctx, proxyPort, 20*time.Second)
}

// TestDNS shares the desktop validation, bootstrap handling and DNS decoder.
func TestDNS(ctx context.Context, request string, dialer *net.Dialer) (string, error) {
	var settings session.RuntimeSettings
	if len(request) > 65536 || json.Unmarshal([]byte(request), &settings) != nil {
		return "", &session.Failure{Code: "invalid_settings", Message: "DNS 配置格式无效"}
	}
	result, err := session.TestDNSWithDialer(ctx, settings, dialer)
	if err != nil {
		return "", err
	}
	encoded, err := json.Marshal(result)
	return string(encoded), err
}

// Compile returns a native-only envelope containing config and a public snapshot.
func Compile(request string, tunnel bool) (string, error) {
	prepared, err := session.CompileMobile([]byte(request), tunnel)
	if err != nil {
		return "", err
	}
	encoded, err := json.Marshal(prepared)
	if err != nil {
		return "", err
	}
	return string(encoded), nil
}

// ValidateRules validates rule editing without starting a core or a tunnel.
func ValidateRules(request string) error {
	return session.ValidateMobileRules([]byte(request))
}
