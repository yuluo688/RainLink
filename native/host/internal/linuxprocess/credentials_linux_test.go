//go:build linux && !android

package linuxprocess

import (
	"errors"
	"os"
	"testing"
)

func TestProcessCredentialsRequireMatchingUIDSlotsAndLifetime(t *testing.T) {
	identity, alive, err := ReadIdentity(os.Getpid())
	if err != nil || !alive {
		t.Fatal(err)
	}
	if err = VerifyUID(identity, uint32(os.Geteuid())); err != nil {
		t.Fatal("current ordinary process was rejected", err)
	}
	if err = VerifyUID(identity, uint32(os.Geteuid())+1); !errors.Is(err, ErrCredentialsChanged) {
		t.Fatal("different UID was accepted", err)
	}
	identity.Start++
	if err = VerifyUID(identity, uint32(os.Geteuid())); !errors.Is(err, ErrNotAlive) {
		t.Fatal("credential read accepted a different process lifetime", err)
	}
	for _, text := range []string{"", "Uid:\t1000 1000 1000", "Uid: 1000 0 1000 1000", "Uid: 1000 1000 0 1000", "Uid: 1000 1000 1000 0", "Uid: x x x x"} {
		if matchingUID([]byte(text), 1000) {
			t.Fatal("partial or malformed credentials were accepted")
		}
	}
	if !matchingUID([]byte("Name: fixture\nUid:\t1000\t1000\t1000\t1000\nGid: 0 0 0 0\n"), 1000) {
		t.Fatal("valid credentials were rejected")
	}
}
