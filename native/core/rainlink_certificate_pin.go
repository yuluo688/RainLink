// RainLink extension to sing-box v1.12.25, distributed under GPL-3.0-or-later.
package tls

import (
	"crypto/sha256"
	"crypto/subtle"
	"crypto/tls"
	"crypto/x509"
	"encoding/hex"
	"errors"
	"strings"
)

// Match Clash's certificate fingerprint semantics, including intermediate pins.
// A pin replaces the normal trust decision; insecure never bypasses this check.
func applyRainLinkCertificatePin(config *tls.Config, fingerprint string) error {
	if fingerprint == "" {
		return nil
	}
	pin, err := hex.DecodeString(strings.ReplaceAll(strings.TrimSpace(fingerprint), ":", ""))
	if err != nil || len(pin) != sha256.Size {
		return errors.New("invalid RainLink certificate SHA-256 fingerprint")
	}
	config.InsecureSkipVerify = true
	config.VerifyConnection = func(state tls.ConnectionState) error {
		for i, certificate := range state.PeerCertificates {
			hash := sha256.Sum256(certificate.Raw)
			if subtle.ConstantTimeCompare(pin, hash[:]) != 1 {
				continue
			}
			if i == 0 {
				return nil
			}
			// An intermediate/root pin still requires a valid leaf chain and name.
			options := x509.VerifyOptions{Roots: x509.NewCertPool(), Intermediates: x509.NewCertPool(), DNSName: state.ServerName}
			options.Roots.AddCert(certificate)
			for _, intermediate := range state.PeerCertificates[1 : i+1] {
				options.Intermediates.AddCert(intermediate)
			}
			if config.Time != nil {
				options.CurrentTime = config.Time()
			}
			_, err := state.PeerCertificates[0].Verify(options)
			return err
		}
		return errors.New("RainLink certificate fingerprint mismatch")
	}
	return nil
}
