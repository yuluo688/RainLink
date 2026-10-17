//go:build linux && !android

// Package rootfs anchors installation operations to root-controlled directories.
package rootfs

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"golang.org/x/sys/unix"
)

// Directory owns a descriptor, never a mutable path used again for child I/O.
type Directory struct{ fd int }

// Open checks every ancestor without following links. Only missing components
// are created; existing administrator permissions are never changed.
func Open(path string, create bool, mode uint32) (_ *Directory, result error) {
	if !filepath.IsAbs(path) || filepath.Clean(path) != path || mode&0022 != 0 || mode&^0777 != 0 {
		return nil, errors.New("invalid root directory path or mode")
	}
	fd, err := unix.Open("/", unix.O_RDONLY|unix.O_DIRECTORY|unix.O_NOFOLLOW|unix.O_CLOEXEC, 0)
	if err != nil {
		return nil, err
	}
	defer func() {
		if fd >= 0 {
			result = errors.Join(result, unix.Close(fd))
		}
	}()
	parts := strings.Split(strings.TrimPrefix(path, "/"), "/")
	for index := -1; index < len(parts); index++ {
		if index >= 0 && parts[index] != "" {
			part := parts[index]
			next, openErr := unix.Openat(fd, part, unix.O_RDONLY|unix.O_DIRECTORY|unix.O_NOFOLLOW|unix.O_CLOEXEC, 0)
			if errors.Is(openErr, unix.ENOENT) && create {
				permission := uint32(0755)
				if index == len(parts)-1 {
					permission = mode
				}
				if err = unix.Mkdirat(fd, part, permission); err != nil && !errors.Is(err, unix.EEXIST) {
					return nil, err
				}
				if err = unix.Fsync(fd); err != nil {
					return nil, err
				}
				next, openErr = unix.Openat(fd, part, unix.O_RDONLY|unix.O_DIRECTORY|unix.O_NOFOLLOW|unix.O_CLOEXEC, 0)
			}
			if openErr != nil {
				return nil, openErr
			}
			closeErr := unix.Close(fd)
			fd = next
			if closeErr != nil {
				return nil, closeErr
			}
		}
		var stat unix.Stat_t
		if err = unix.Fstat(fd, &stat); err != nil {
			return nil, err
		}
		if stat.Uid != 0 || stat.Gid != 0 || stat.Mode&0022 != 0 {
			return nil, errors.New("installation ancestor is not root-controlled")
		}
	}
	resultDir := &Directory{fd: fd}
	fd = -1
	return resultDir, nil
}

// Close releases the descriptor after child operations finish.
func (d *Directory) Close() error { return unix.Close(d.fd) }

func validName(name string) bool {
	return name != "" && name != "." && name != ".." && len(name) <= 128 && !strings.ContainsAny(name, "/\x00")
}

// OpenFile accepts only a single-link, root-owned, non-writable regular inode.
func (d *Directory) OpenFile(name string) (*os.File, error) {
	if !validName(name) {
		return nil, errors.New("invalid installation filename")
	}
	fd, err := unix.Openat(d.fd, name, unix.O_RDONLY|unix.O_NOFOLLOW|unix.O_CLOEXEC|unix.O_NONBLOCK, 0)
	if err != nil {
		return nil, err
	}
	var stat unix.Stat_t
	if err = unix.Fstat(fd, &stat); err != nil || stat.Uid != 0 || stat.Gid != 0 || stat.Nlink != 1 || stat.Mode&unix.S_IFMT != unix.S_IFREG || stat.Mode&07022 != 0 {
		return nil, errors.Join(errors.New("installation file has unsafe ownership, type or mode"), err, unix.Close(fd))
	}
	return os.NewFile(uintptr(fd), name), nil
}

// Digest records the bytes and mode used for ownership and rollback checks.
type Digest struct {
	SHA256 string `json:"sha256"`
	Size   int64  `json:"size"`
	Mode   uint32 `json:"mode"`
}

// Inspect bounds both the initial size and the bytes actually read.
func Inspect(ctx context.Context, file *os.File, limit int64) (Digest, error) {
	stat, err := file.Stat()
	if err != nil {
		return Digest{}, err
	}
	if !stat.Mode().IsRegular() || stat.Size() < 1 || stat.Size() > limit {
		return Digest{}, errors.New("installation file exceeds size bounds")
	}
	if _, err = file.Seek(0, io.SeekStart); err != nil {
		return Digest{}, err
	}
	hash := sha256.New()
	n, err := copyContext(ctx, hash, io.LimitReader(file, limit+1))
	if err != nil {
		return Digest{}, err
	}
	if n != stat.Size() || n > limit {
		return Digest{}, errors.New("installation file changed while reading")
	}
	if _, err = file.Seek(0, io.SeekStart); err != nil {
		return Digest{}, err
	}
	return Digest{SHA256: hex.EncodeToString(hash.Sum(nil)), Size: n, Mode: uint32(stat.Mode().Perm())}, nil
}

func copyContext(ctx context.Context, writer io.Writer, reader io.Reader) (int64, error) {
	buffer := make([]byte, 64*1024)
	var total int64
	for {
		if err := ctx.Err(); err != nil {
			return total, err
		}
		n, readErr := reader.Read(buffer)
		if n > 0 {
			written, writeErr := writer.Write(buffer[:n])
			total += int64(written)
			if writeErr != nil {
				return total, writeErr
			}
			if written != n {
				return total, io.ErrShortWrite
			}
		}
		if errors.Is(readErr, io.EOF) {
			return total, nil
		}
		if readErr != nil {
			return total, readErr
		}
	}
}

// Replace writes an inode, fsyncs it, then atomically renames and fsyncs the
// directory. It never truncates the old inode or follows a destination link.
func (d *Directory) Replace(ctx context.Context, name string, source io.Reader, limit int64, mode uint32) (result error) {
	if !validName(name) || mode&0022 != 0 || mode&^0777 != 0 || limit <= 0 {
		return errors.New("invalid installation write")
	}
	var suffix [12]byte
	if _, err := rand.Read(suffix[:]); err != nil {
		return err
	}
	temporary := ".rainlink-" + hex.EncodeToString(suffix[:]) + ".tmp"
	fd, err := unix.Openat(d.fd, temporary, unix.O_CREAT|unix.O_EXCL|unix.O_NOFOLLOW|unix.O_CLOEXEC|unix.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	file := os.NewFile(uintptr(fd), temporary)
	defer func() {
		if err := unix.Unlinkat(d.fd, temporary, 0); err != nil && !errors.Is(err, unix.ENOENT) {
			result = errors.Join(result, err)
		}
	}()
	n, copyErr := copyContext(ctx, file, io.LimitReader(source, limit+1))
	if copyErr == nil && (n < 1 || n > limit) {
		copyErr = errors.New("installation source exceeds size bounds")
	}
	err = errors.Join(copyErr, file.Chown(0, 0), file.Chmod(os.FileMode(mode)), file.Sync(), file.Close())
	if err != nil {
		return err
	}
	if err = ctx.Err(); err != nil {
		return err
	}
	old, err := d.OpenFile(name)
	if err == nil {
		err = old.Close()
	}
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if err = unix.Renameat(d.fd, temporary, d.fd, name); err != nil {
		return fmt.Errorf("replace installation file: %w", err)
	}
	return unix.Fsync(d.fd)
}

// Remove deletes one checked regular inode only. Missing files are idempotent.
func (d *Directory) Remove(name string) error {
	file, err := d.OpenFile(name)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if err = file.Close(); err != nil {
		return err
	}
	if err = unix.Unlinkat(d.fd, name, 0); err != nil {
		return err
	}
	return unix.Fsync(d.fd)
}
