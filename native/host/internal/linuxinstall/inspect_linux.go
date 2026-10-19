//go:build linux && !android

package linuxinstall

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"os"
	"path/filepath"

	"rainlink.local/host/internal/linuxipc"
	"rainlink.local/host/internal/rootfs"
	assets "rainlink.local/host/packaging/linux"
)

// ServiceStatus describes observable files and socket activation, not permission
// to connect or proof that a private installation transaction has completed.
type ServiceStatus struct {
	ProtocolVersion int    `json:"protocolVersion"`
	State           string `json:"state"`
	CanManage       bool   `json:"canManage"`
	Enabled         bool   `json:"enabled"`
	Active          bool   `json:"active"`
	Message         string `json:"message"`
}

// InspectService is read-only: no authorization, recovery, activation or writes.
func InspectService(ctx context.Context) ServiceStatus {
	status := ServiceStatus{ProtocolVersion: 1, State: "unavailable", Message: "需要 Linux 6.5 及以上、systemd 和 polkit"}
	service := systemServices{}
	if service.preflight(ctx, true) != nil {
		return status
	}
	pkexec, err := linuxipc.OpenRootExecutable("/usr/bin/pkexec")
	if err != nil {
		status.Message = "未找到可用的系统授权工具 pkexec"
		return status
	}
	if err = pkexec.Close(); err != nil {
		status.Message = "无法检查系统授权工具"
		return status
	}
	status.CanManage = true
	state, err := service.state(ctx)
	if err != nil {
		status.State, status.Message = "incomplete", "服务配置不完整或被管理员修改，请检查系统配置"
		return status
	}
	status.Enabled, status.Active = state.Enabled, state.Active
	executable, err := os.Executable()
	if err != nil {
		status.State, status.Message = "incomplete", "无法确认当前应用的服务文件"
		return status
	}
	current, installed, err := inspectServiceFiles(ctx, "", "/proc/self/exe", filepath.Join(filepath.Dir(executable), "sing-box"))
	if err != nil || installed != 0 && installed != len(targets) || state.Present != (installed == len(targets)) {
		status.State, status.Message = "incomplete", "服务文件不完整或无法验证，可尝试恢复安装"
		return status
	}
	switch {
	case installed == 0:
		status.State, status.Message = "missing", "尚未安装 TUN 权限服务"
	case current:
		status.State, status.Message = "current", "服务文件与当前应用一致"
	default:
		status.State, status.Message = "different", "已安装服务与当前应用不同，可更新服务"
	}
	return status
}

// The test root is never supplied by IPC. Every installed file is read through
// root-controlled descriptors; hashes cover the bundled host and embedded policy.
func inspectServiceFiles(ctx context.Context, root, executable, core string) (current bool, installed int, result error) {
	current = true
	for index, target := range targets {
		directory, err := rootfs.Open(root+filepath.Dir(target.path), false, 0755)
		if errors.Is(err, os.ErrNotExist) {
			current = false
			continue
		}
		if err != nil {
			return false, installed, err
		}
		file, openErr := directory.OpenFile(filepath.Base(target.path))
		closeErr := directory.Close()
		if errors.Is(openErr, os.ErrNotExist) && closeErr == nil {
			current = false
			continue
		}
		if err = errors.Join(openErr, closeErr); err != nil {
			return false, installed, err
		}
		digest, readErr := rootfs.Inspect(ctx, file, target.limit)
		if err = errors.Join(readErr, file.Close()); err != nil {
			return false, installed, err
		}
		installed++
		var expected rootfs.Digest
		if index < 2 {
			path := executable
			if index == 1 {
				path = core
			}
			source, err := os.Open(path)
			if err != nil {
				return false, installed, err
			}
			expected, readErr = rootfs.Inspect(ctx, source, target.limit)
			if err = errors.Join(readErr, source.Close()); err != nil {
				return false, installed, err
			}
		} else {
			data, err := assets.Files.ReadFile(filepath.Base(target.path))
			if err != nil {
				return false, installed, err
			}
			hash := sha256.Sum256(data)
			expected = rootfs.Digest{SHA256: hex.EncodeToString(hash[:]), Size: int64(len(data)), Mode: target.mode}
		}
		current = current && digest.SHA256 == expected.SHA256 && digest.Size == expected.Size && digest.Mode == target.mode
	}
	return current, installed, nil
}
