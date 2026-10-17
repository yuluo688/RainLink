// Package mobile is the Android native binding for RainLink's shared compiler.
package mobile

import (
	"errors"

	"github.com/sagernet/sing-box/experimental/libbox"
	"rainlink.local/host/mobileconfig"
)

// Compile validates a domain request and asks the pinned core to check it.
// Its return value contains secrets and is reserved for the native service.
func Compile(request string, tunnel bool) (string, error) {
	return mobileconfig.Compile(request, tunnel)
}

// CheckConfig checks only compiler output, which the native layer never exposes
// as an arbitrary-config entry point to Flutter.
func CheckConfig(configuration string) error {
	if err := libbox.CheckConfig(configuration); err != nil {
		// Core errors can contain upstream credentials and user-provided URLs.
		return errors.New("核心未通过配置校验，请检查协议和网络设置")
	}
	return nil
}

// ValidateRules validates shared rule editing without opening any listeners.
func ValidateRules(request string) error {
	return mobileconfig.ValidateRules(request)
}
