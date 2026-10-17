//go:build linux && !android

package linuxipc

import (
	"errors"
	"os"
	"path/filepath"
	"strings"

	"golang.org/x/sys/unix"
)

// OpenRootExecutable anchors every component to checked root-owned directory
// descriptors. The returned inode must be executed through an inherited FD;
// reopening its path would lose protection against replacement after hashing.
// Symlinks and writable ancestors are deliberately refused.
func OpenRootExecutable(path string) (_ *os.File, result error) {
	return openRootPath(path, false)
}

// openRootPath pins either an executable or the socket inode used by
// DialRootService. Even read-only clients must reject writable ancestors.
func openRootPath(path string, socket bool) (_ *os.File, result error) {
	if !filepath.IsAbs(path) || filepath.Clean(path) != path || path == "/" {
		return nil, errors.New("privileged endpoint requires a canonical absolute path")
	}
	directory, err := unix.Open("/", unix.O_RDONLY|unix.O_DIRECTORY|unix.O_CLOEXEC|unix.O_NOFOLLOW, 0)
	if err != nil {
		return nil, err
	}
	defer func() { result = errors.Join(result, unix.Close(directory)) }()
	parts := strings.Split(strings.TrimPrefix(path, "/"), "/")
	for index, part := range parts {
		var parent unix.Stat_t
		if err = unix.Fstat(directory, &parent); err != nil {
			return nil, err
		}
		if parent.Uid != 0 || parent.Mode&0022 != 0 {
			return nil, errors.New("privileged endpoint ancestor is not root-controlled")
		}
		flags := unix.O_RDONLY | unix.O_NOFOLLOW | unix.O_CLOEXEC | unix.O_NONBLOCK
		if index != len(parts)-1 {
			flags |= unix.O_DIRECTORY
		} else if socket {
			flags = unix.O_PATH | unix.O_NOFOLLOW | unix.O_CLOEXEC
		}
		fd, err := unix.Openat(directory, part, flags, 0)
		if err != nil {
			return nil, err
		}
		if index != len(parts)-1 {
			if err = unix.Close(directory); err != nil {
				_ = unix.Close(fd)
				return nil, err
			}
			directory = fd
			continue
		}
		var stat unix.Stat_t
		if err = unix.Fstat(fd, &stat); err != nil {
			return nil, errors.Join(err, unix.Close(fd))
		}
		valid := stat.Uid == 0 && stat.Mode&unix.S_IFMT == unix.S_IFREG && stat.Mode&0022 == 0 && stat.Mode&0111 != 0
		if socket {
			// Ordinary callers need write permission to connect. Only the socket
			// inode may be writable; every containing directory stays trusted.
			valid = stat.Uid == 0 && stat.Mode&unix.S_IFMT == unix.S_IFSOCK
		}
		if !valid {
			return nil, errors.Join(errors.New("privileged endpoint has an invalid owner, type or mode"), unix.Close(fd))
		}
		return os.NewFile(uintptr(fd), path), nil
	}
	return nil, errors.New("privileged endpoint is missing")
}
