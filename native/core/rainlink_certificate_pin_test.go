package tls

import (
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/hex"
	"testing"
)

func TestRainLinkCertificatePin(t *testing.T) {
	certificate := &x509.Certificate{Raw: []byte("fixture-certificate")}
	hash := sha256.Sum256(certificate.Raw)
	for _, insecure := range []bool{false, true} {
		config := &tls.Config{InsecureSkipVerify: insecure}
		if err := applyRainLinkCertificatePin(config, hex.EncodeToString(hash[:])); err != nil {
			t.Fatal(err)
		}
		if err := config.VerifyConnection(tls.ConnectionState{PeerCertificates: []*x509.Certificate{certificate}}); err != nil {
			t.Fatal("matching leaf certificate rejected")
		}
		if err := config.VerifyConnection(tls.ConnectionState{PeerCertificates: []*x509.Certificate{{Raw: []byte("different")}}}); err == nil {
			t.Fatal("incorrect certificate accepted")
		}
		if err := config.VerifyConnection(tls.ConnectionState{}); err == nil {
			t.Fatal("missing certificate accepted")
		}
	}
	if err := applyRainLinkCertificatePin(&tls.Config{}, "invalid"); err == nil {
		t.Fatal("invalid fingerprint accepted")
	}
	config := &tls.Config{}
	if err := applyRainLinkCertificatePin(config, ""); err != nil || config.InsecureSkipVerify || config.VerifyConnection != nil {
		t.Fatal("empty fingerprint changed normal certificate verification")
	}
}
