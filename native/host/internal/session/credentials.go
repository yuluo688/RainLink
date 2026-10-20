package session

import (
	"context"
	"errors"
	"runtime"

	"rainlink.local/host/internal/securestore"
)

// Only known errors are displayable. OS command diagnostics and keyring data
// must never become part of the public session response.
func credentialFailure(err error, code, message string) error {
	switch {
	case errors.Is(err, context.Canceled):
		return fail("cancelled", "凭据操作已取消")
	case errors.Is(err, context.DeadlineExceeded):
		return fail("credential_service_timeout", "等待系统密钥服务超时，请解锁密钥环后重试")
	case errors.Is(err, securestore.ErrUnavailable):
		if runtime.GOOS == "darwin" {
			return fail("credential_service_unavailable", "macOS 钥匙串不可用或已锁定，请解锁钥匙串后重试")
		}
		return fail("credential_service_unavailable", "系统密钥服务不可用或已锁定，请安装 libsecret 工具并解锁系统密钥环")
	case errors.Is(err, securestore.ErrMissingKey):
		return fail("credential_key_missing", "系统密钥环中找不到加密密钥，请恢复密钥环或重新导入节点")
	default:
		return fail(code, message)
	}
}
