//go:build linux && !android

package linuxinstall

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
	"syscall"
	"time"

	"golang.org/x/sys/unix"
	"rainlink.local/host/internal/linuxipc"
	"rainlink.local/host/internal/session"
)

const socketUnit = "rainlink-tun.socket"
const templateUnit = "rainlink-tun@.service"

// systemd cannot show a template itself; load an inactive, bounded instance to
// inspect its actual fragment and inherited drop-ins without starting it.
const templateProbeUnit = "rainlink-tun@install-check.service"

type systemServices struct{}

type boundedOutput struct{ bytes.Buffer }

func (b *boundedOutput) Write(data []byte) (int, error) {
	if b.Len()+len(data) > 64<<10 {
		return 0, errors.New("systemctl output exceeded bounds")
	}
	return b.Buffer.Write(data)
}

// Only constant program/arguments and validated RainLink instance names reach
// this runner. The executable inode is pinned; no inherited environment or
// configurable command path can affect this root process.
func systemctl(ctx context.Context, args ...string) (output []byte, result error) {
	ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	file, err := linuxipc.OpenRootExecutable("/usr/bin/systemctl")
	if err != nil {
		return nil, err
	}
	defer func() { result = errors.Join(result, file.Close()) }()
	command := exec.CommandContext(ctx, "/proc/self/fd/3", args...)
	command.ExtraFiles = []*os.File{file}
	command.Env = []string{"PATH=/usr/sbin:/usr/bin:/sbin:/bin", "LANG=C", "LC_ALL=C", "SYSTEMD_COLORS=0", "SYSTEMD_PAGER="}
	command.Dir = "/"
	command.WaitDelay = time.Second
	command.SysProcAttr = &syscall.SysProcAttr{Pdeathsig: syscall.SIGKILL}
	var stdout, stderr boundedOutput
	command.Stdout, command.Stderr = &stdout, &stderr
	runtime.LockOSThread()
	err = command.Run()
	runtime.UnlockOSThread()
	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	if err != nil {
		return stdout.Bytes(), fmt.Errorf("systemctl %s failed: %w", args[0], err)
	}
	return stdout.Bytes(), nil
}

func (systemServices) preflight(ctx context.Context, install bool) error {
	if install {
		var version unix.Utsname
		if err := unix.Uname(&version); err != nil {
			return err
		}
		parts := strings.Split(unix.ByteSliceToString(version.Release[:]), ".")
		if len(parts) < 2 {
			return errors.New("unable to determine Linux version")
		}
		major, majorErr := strconv.Atoi(parts[0])
		minor, minorErr := strconv.Atoi(parts[1])
		if majorErr != nil || minorErr != nil || major < 6 || (major == 6 && minor < 5) {
			return errors.New("Linux TUN service requires Linux 6.5 or newer")
		}
		pkcheck, err := linuxipc.OpenRootExecutable("/usr/bin/pkcheck")
		if err != nil {
			return fmt.Errorf("polkit authorization tool unavailable: %w", err)
		}
		if err = pkcheck.Close(); err != nil {
			return err
		}
	}
	if _, err := systemctl(ctx, "show", "--property=Version", "--no-pager"); err != nil {
		return errors.New("a running systemd system manager is required")
	}
	return nil
}

type unitState struct{ loaded, active, enabled bool }

func parseUnit(data []byte, unit string) (unitState, error) {
	return parseUnitForStop(data, unit, false)
}

func parseUnitForStop(data []byte, unit string, forStop bool) (unitState, error) {
	fields := make(map[string]string)
	for _, line := range strings.Split(strings.TrimSpace(string(data)), "\n") {
		key, value, ok := strings.Cut(line, "=")
		if _, duplicate := fields[key]; !ok || duplicate {
			return unitState{}, errors.New("invalid systemd unit state")
		}
		fields[key] = value
	}
	for _, key := range []string{"LoadState", "ActiveState", "UnitFileState", "FragmentPath", "DropInPaths"} {
		if _, ok := fields[key]; !ok {
			return unitState{}, errors.New("incomplete systemd unit state")
		}
	}
	if fields["DropInPaths"] != "" {
		return unitState{}, errors.New("administrator systemd overrides must be resolved before installation")
	}
	if fields["LoadState"] == "not-found" && fields["FragmentPath"] == "" && fields["UnitFileState"] == "" && fields["ActiveState"] == "inactive" {
		return unitState{}, nil
	}
	// A killed uninstall may have removed a fragment while systemd still owns
	// an active socket. Only the stop path accepts this transient state.
	if forStop && fields["LoadState"] == "not-found" && fields["FragmentPath"] == "" && fields["UnitFileState"] == "" {
		switch fields["ActiveState"] {
		case "active", "activating", "deactivating":
			return unitState{active: true}, nil
		case "failed":
			return unitState{}, nil
		}
	}
	fragmentUnit := unit
	if validInstance(unit) {
		fragmentUnit = templateUnit
	}
	if fields["LoadState"] != "loaded" || fields["FragmentPath"] != "/usr/lib/systemd/system/"+fragmentUnit {
		return unitState{}, errors.New("systemd unit is masked, redirected, or unmanaged")
	}
	state := unitState{loaded: true}
	switch fields["ActiveState"] {
	case "active":
		state.active = true
	case "inactive", "failed":
	case "activating", "deactivating":
		if !forStop {
			return unitState{}, errors.New("systemd unit is transitioning")
		}
		state.active = true
	default:
		return unitState{}, errors.New("systemd unit is transitioning")
	}
	switch fields["UnitFileState"] {
	case "enabled":
		state.enabled = true
	case "disabled":
	case "static":
		if fragmentUnit != templateUnit {
			return unitState{}, errors.New("socket unit has no persistent installation state")
		}
	default:
		return unitState{}, errors.New("unsupported systemd unit enablement state")
	}
	return state, nil
}

func inspectUnit(ctx context.Context, unit string) (unitState, error) {
	return inspectUnitForStop(ctx, unit, false)
}

func inspectUnitForStop(ctx context.Context, unit string, forStop bool) (unitState, error) {
	data, err := systemctl(ctx, "show", unit, "--all", "--no-pager", "--property=LoadState,ActiveState,UnitFileState,FragmentPath,DropInPaths")
	state, parseErr := parseUnitForStop(data, unit, forStop)
	// systemctl may return a nonzero status with a complete not-found result.
	if parseErr == nil && !state.loaded {
		return state, nil
	}
	return state, errors.Join(err, parseErr)
}

func (systemServices) state(ctx context.Context) (serviceState, error) {
	socket, err := inspectUnit(ctx, socketUnit)
	if err != nil {
		return serviceState{}, err
	}
	template, err := inspectUnit(ctx, templateProbeUnit)
	if err != nil {
		return serviceState{}, err
	}
	if socket.loaded != template.loaded {
		return serviceState{}, errors.New("partial systemd installation")
	}
	return serviceState{Present: socket.loaded, Enabled: socket.enabled, Active: socket.active}, nil
}

func validInstance(name string) bool {
	if len(name) > 256 || !strings.HasPrefix(name, "rainlink-tun@") || !strings.HasSuffix(name, ".service") || name == templateUnit {
		return false
	}
	for _, r := range name {
		if !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || strings.ContainsRune("@_.:-\\", r)) {
			return false
		}
	}
	return true
}

func instances(data []byte) ([]string, error) {
	var names []string
	for _, line := range strings.Split(strings.TrimSpace(string(data)), "\n") {
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}
		if !validInstance(fields[0]) {
			return nil, errors.New("unexpected systemd permission instance")
		}
		names = append(names, fields[0])
		if len(names) > 256 {
			return nil, errors.New("too many systemd permission instances")
		}
	}
	return names, nil
}

func (systemServices) quiesce(ctx context.Context) error {
	// Missing units are normal during interrupted replacement, redirects are not.
	if _, err := systemctl(ctx, "daemon-reload"); err != nil {
		return err
	}
	socket, err := inspectUnitForStop(ctx, socketUnit, true)
	if err != nil {
		return err
	}
	if socket.loaded || socket.active {
		if _, err = systemctl(ctx, "stop", socketUnit); err != nil {
			return err
		}
	}
	data, err := systemctl(ctx, "list-units", "--all", "--no-legend", "--plain", "--no-pager", "rainlink-tun@*.service")
	if err != nil {
		return err
	}
	names, err := instances(data)
	if err != nil {
		return err
	}
	for _, name := range names {
		instance, inspectErr := inspectUnitForStop(ctx, name, true)
		if inspectErr != nil {
			return inspectErr
		}
		if !instance.loaded && !instance.active {
			continue
		}
		if _, err = systemctl(ctx, "stop", name); err != nil {
			return err
		}
	}
	data, err = systemctl(ctx, "list-units", "--state=active,activating,deactivating", "--no-legend", "--plain", "--no-pager", "rainlink-tun@*.service")
	if err != nil {
		return err
	}
	names, err = instances(data)
	if err != nil {
		return err
	}
	if len(names) != 0 {
		return errors.New("permission sessions remain active")
	}
	return nil
}

func (systemServices) enable(ctx context.Context, enabled bool) error {
	socket, err := inspectUnit(ctx, socketUnit)
	if err != nil {
		return err
	}
	if !socket.loaded {
		if enabled {
			return errors.New("cannot enable missing permission socket")
		}
		return nil
	}
	verb := "disable"
	if enabled {
		verb = "enable"
	}
	_, err = systemctl(ctx, verb, socketUnit)
	return err
}

func (systemServices) reload(ctx context.Context) error {
	_, err := systemctl(ctx, "daemon-reload")
	return err
}
func (systemServices) start(ctx context.Context) error {
	_, err := systemctl(ctx, "start", socketUnit)
	return err
}
func (s systemServices) ready(ctx context.Context) error {
	state, err := s.state(ctx)
	if err != nil {
		return err
	}
	if !state.Present || !state.Active {
		return errors.New("permission socket did not become active")
	}
	return session.ConfirmLinuxTUNServiceIdle(ctx)
}
