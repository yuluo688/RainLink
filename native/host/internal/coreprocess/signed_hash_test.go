package coreprocess

import (
	"runtime"
	"strings"
	"testing"
)

func TestMacSignedCorePinIsBuildTimeAndPlatformSpecific(t *testing.T) {
	previous := signedDarwinCoreSHA256
	t.Cleanup(func() { signedDarwinCoreSHA256 = previous })
	signedDarwinCoreSHA256 = strings.Repeat("ab", 32)
	if coreHash("darwin") != signedDarwinCoreSHA256 {
		t.Fatal("signed macOS bytes were not pinned")
	}
	for _, platform := range []string{"windows", "linux"} {
		if coreHash(platform) != expectedCoreSHA256[platform+"-"+runtime.GOARCH] {
			t.Fatal("macOS signing changed another platform's pinned binary")
		}
	}
	for _, invalid := range []string{"local-manifest.json", strings.Repeat("a", 63), strings.Repeat("z", 64)} {
		signedDarwinCoreSHA256 = invalid
		if coreHash("darwin") != "" {
			t.Fatal("invalid macOS build pin fell back to unsigned bytes")
		}
	}
	signedDarwinCoreSHA256 = ""
	if coreHash("darwin") != expectedCoreSHA256["darwin-"+runtime.GOARCH] {
		t.Fatal("cross-compiled development host lost its source lock")
	}
}
