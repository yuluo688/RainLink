// Package host defines the versioned desktop host status contract.
package host

import (
	"context"
	"runtime"

	"rainlink.local/host/internal/coreprocess"
	"rainlink.local/host/internal/session"
)

const (
	// Version is the host implementation version, independent of the network core.
	Version = "0.1.0"
	// ProtocolVersion changes when the Dart/Go status contract is incompatible.
	ProtocolVersion = 1
)

// Status describes observed capabilities. An unconfigured core has none.
type Status struct {
	ProtocolVersion int          `json:"protocolVersion"`
	Host            Information  `json:"host"`
	Core            Core         `json:"core"`
	Capabilities    Capabilities `json:"capabilities"`
}

// Information identifies the host binary that answered the request.
type Information struct {
	Version  string `json:"version"`
	Platform string `json:"platform"`
	Arch     string `json:"arch"`
}

// Core reports the configured network engine, if one exists.
type Core struct {
	State   string  `json:"state"`
	Version *string `json:"version"`
}

// Capabilities gate client operations; platform names alone do not enable them.
type Capabilities struct {
	Connect     bool `json:"connect"`
	SystemProxy bool `json:"systemProxy"`
	TUN         bool `json:"tun"`
}

// Inspect returns actual bundled core availability without starting a session.
func Inspect() Status {
	status := Status{
		ProtocolVersion: ProtocolVersion,
		Host: Information{
			Version: Version, Platform: runtime.GOOS, Arch: runtime.GOARCH,
		},
		Core: Core{State: "not_configured"},
	}
	if runtime.GOOS == "windows" || runtime.GOOS == "linux" {
		if version, err := session.Version(session.CorePath()); err == nil {
			status.Core = Core{State: "ready", Version: &version}
			status.Capabilities.Connect = true
			status.Capabilities.SystemProxy = session.SystemProxyAvailable(context.Background())
			if runtime.GOOS == "windows" {
				status.Capabilities.TUN = coreprocess.Trusted(session.CorePath())
			}
		}
	}
	return status
}
