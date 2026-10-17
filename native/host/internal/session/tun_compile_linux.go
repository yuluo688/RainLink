//go:build linux && !android

package session

import (
	"context"
	"encoding/json"

	"rainlink.local/host/internal/linuxipc"
	"rainlink.local/host/internal/linuxtun"
)

// CompileLinuxTUN accepts the same validated node/chain/routing domain as the
// native mobile service, with in-memory credentials from an authorized caller.
// It never accepts a raw core configuration or starts a privileged process.
// Resources must come from the root helper's held lease, not from the caller.
func CompileLinuxTUN(ctx context.Context, raw []byte, resources linuxtun.Specification) (MobileConfiguration, error) {
	if ctx.Err() != nil {
		return MobileConfiguration{}, fail("cancelled", "连接已取消")
	}
	if linuxipc.ValidateJSON(raw) != nil {
		return MobileConfiguration{}, fail("invalid_request", "连接请求包含无效或重复字段，或超出大小限制")
	}
	// encoding/json otherwise accepts case-insensitive aliases of struct tags.
	// Keep the privileged envelope exact while ciphertext map keys retain case.
	var fields map[string]json.RawMessage
	if json.Unmarshal(raw, &fields) != nil || fields == nil {
		return MobileConfiguration{}, fail("invalid_request", "连接请求应为对象")
	}
	for name := range fields {
		switch name {
		case "node", "chain", "mode", "systemProxy", "tun", "routing", "runtimeSettings", "secrets":
		default:
			return MobileConfiguration{}, fail("invalid_request", "连接请求包含未知字段")
		}
	}
	if _, err := resources.ExpectedRules(); err != nil {
		return MobileConfiguration{}, fail("invalid_tun_resources", "TUN 资源租约无效")
	}
	compiled, err := compileNativeRequest(raw, true, func(config []byte) ([]byte, error) {
		plan, err := newTUNPlan(ctx)
		if err != nil {
			return nil, err
		}
		plan.Name = resources.Name
		config, err = configureTUN(config, plan)
		if err != nil {
			return nil, fail("invalid_config", "无法编译 TUN 网络配置")
		}
		var value map[string]any
		if json.Unmarshal(config, &value) != nil {
			return nil, fail("invalid_config", "无法读取已编译的 TUN 配置")
		}
		inbounds := value["inbounds"].([]any)
		inbound := inbounds[len(inbounds)-1].(map[string]any)
		inbound["rainlink_managed"] = true
		inbound["iproute2_table_index"] = resources.Table
		inbound["iproute2_rule_index"] = resources.Priority
		return json.Marshal(value)
	})
	if err != nil {
		return MobileConfiguration{}, err
	}
	if ctx.Err() != nil {
		return MobileConfiguration{}, fail("cancelled", "连接已取消")
	}
	if compiled.Snapshot.ProxyPort < 1024 || compiled.APIPort < 1024 {
		return MobileConfiguration{}, fail("invalid_settings", "权限服务的本地监听端口应大于或等于 1024")
	}
	compiled.Snapshot.Phase = "connecting"
	compiled.Snapshot.TUNInterface = resources.Name
	return compiled, nil
}
