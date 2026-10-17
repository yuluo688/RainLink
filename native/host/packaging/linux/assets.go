// Package linux packages the fixed privilege service inputs with the installer.
package linux

import "embed"

// Files is the single source for installed units and the authorization policy.
//
//go:embed rainlink-tun.socket rainlink-tun@.service org.rainlink.tun.policy
var Files embed.FS
