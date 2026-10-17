//go:build linux && !android

package linuxprocess

import (
	"errors"
	"io"
	"os"
	"strconv"
	"strings"
)

// ErrCredentialsChanged rejects a process that changed UID after creating IPC.
var ErrCredentialsChanged = errors.New("process credentials changed")

// VerifyUID requires all four UID slots to match the kernel socket creator.
// RainLink uses ordinary user/root services, so setuid or partially dropped
// credentials are deliberately not accepted at its permission boundary.
func VerifyUID(identity Identity, uid uint32) error {
	if err := requireAlive(identity); err != nil {
		return err
	}
	status, err := os.Open("/proc/" + strconv.Itoa(identity.PID) + "/status")
	if err != nil {
		return err
	}
	data, readErr := io.ReadAll(io.LimitReader(status, 64<<10))
	if err = errors.Join(readErr, status.Close()); err != nil {
		return err
	}
	if !matchingUID(data, uid) {
		return ErrCredentialsChanged
	}
	return requireAlive(identity)
}

func requireAlive(identity Identity) error {
	alive, err := Alive(identity)
	if err != nil {
		return err
	}
	if !alive {
		return ErrNotAlive
	}
	return nil
}

func matchingUID(data []byte, uid uint32) bool {
	expected := strconv.FormatUint(uint64(uid), 10)
	for _, line := range strings.Split(string(data), "\n") {
		if !strings.HasPrefix(line, "Uid:") {
			continue
		}
		fields := strings.Fields(line)
		return len(fields) == 5 && fields[1] == expected && fields[2] == expected && fields[3] == expected && fields[4] == expected
	}
	return false
}
