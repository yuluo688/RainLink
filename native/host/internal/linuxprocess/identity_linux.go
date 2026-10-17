//go:build linux && !android

// Package linuxprocess binds Linux recovery records to actual process lifetimes.
package linuxprocess

import (
	"errors"
	"os"
	"strconv"
	"strings"

	"golang.org/x/sys/unix"
)

// Identity distinguishes PID reuse and reboots. Start is measured in clock ticks.
type Identity struct {
	PID   int    `json:"pid"`
	Start uint64 `json:"start"`
	Boot  string `json:"boot"`
}

// Valid checks the persisted, non-secret process identity format.
func (identity Identity) Valid() bool {
	if identity.PID < 1 || identity.Start == 0 || len(identity.Boot) != 36 {
		return false
	}
	for index, value := range identity.Boot {
		if index == 8 || index == 13 || index == 18 || index == 23 {
			if value != '-' {
				return false
			}
		} else if !(value >= '0' && value <= '9' || value >= 'a' && value <= 'f') {
			return false
		}
	}
	return true
}

func parseStart(data []byte) (uint64, bool, error) {
	// comm may contain spaces and closing parentheses. The final ") " is
	// the boundary before stat's fixed fields, including starttime (field 22).
	index := strings.LastIndex(string(data), ") ")
	if index < 0 {
		return 0, false, errors.New("invalid process identity")
	}
	parts := strings.Fields(string(data[index+2:]))
	if len(parts) < 20 {
		return 0, false, errors.New("invalid process identity")
	}
	if parts[0] == "Z" || parts[0] == "X" {
		return 0, false, nil
	}
	start, err := strconv.ParseUint(parts[19], 10, 64)
	if err != nil || start == 0 {
		return 0, false, errors.New("invalid process start time")
	}
	return start, true, nil
}

// ReadIdentity returns false for missing, zombie or dead processes. Permission
// and parsing failures remain errors; they must never authorize recovery.
func ReadIdentity(pid int) (Identity, bool, error) {
	return readIdentity(pid, os.ReadFile)
}

func readIdentity(pid int, readFile func(string) ([]byte, error)) (Identity, bool, error) {
	if pid < 1 {
		return Identity{}, false, errors.New("invalid process PID")
	}
	data, err := readFile("/proc/" + strconv.Itoa(pid) + "/stat")
	// procfs can return ESRCH from an already-open stat file while the kernel
	// reaps its task. Both results prove this PID has disappeared; other read
	// failures must still retain recovery state.
	if errors.Is(err, os.ErrNotExist) || errors.Is(err, unix.ESRCH) {
		return Identity{}, false, nil
	}
	if err != nil {
		return Identity{}, false, err
	}
	start, alive, err := parseStart(data)
	if err != nil || !alive {
		return Identity{}, false, err
	}
	boot, err := readFile("/proc/sys/kernel/random/boot_id")
	if err != nil {
		return Identity{}, false, err
	}
	identity := Identity{pid, start, strings.TrimSpace(string(boot))}
	if !identity.Valid() {
		return Identity{}, false, errors.New("invalid process boot identity")
	}
	return identity, true, nil
}

// Alive checks the entire identity rather than a signal-zero PID probe.
func Alive(identity Identity) (bool, error) {
	if !identity.Valid() {
		return false, errors.New("invalid recorded process identity")
	}
	current, alive, err := ReadIdentity(identity.PID)
	return alive && current == identity, err
}

// NetworkNamespace reads the kernel's namespace identity, without switching it.
func NetworkNamespace(pid int) (string, error) {
	if pid < 1 {
		return "", errors.New("invalid namespace owner PID")
	}
	value, err := os.Readlink("/proc/" + strconv.Itoa(pid) + "/ns/net")
	if err != nil {
		return "", err
	}
	if !ValidNamespace(value) {
		return "", errors.New("invalid network namespace identity")
	}
	return value, nil
}

// ValidNamespace checks the kernel link format stored in recovery records.
func ValidNamespace(value string) bool {
	if !strings.HasPrefix(value, "net:[") || !strings.HasSuffix(value, "]") || len(value) > 32 {
		return false
	}
	number, err := strconv.ParseUint(value[5:len(value)-1], 10, 64)
	return err == nil && number != 0
}
