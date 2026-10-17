//go:build !linux || android

package session

import "context"

func (m *Manager) connectManagedTUNLocked(context.Context, Node, *ChainSnapshot, string, bool, *RoutingPlan, bool, RuntimeSettings) (Snapshot, error) {
	return Snapshot{}, fail("capture_unavailable", "当前平台没有可用的 TUN 权限服务")
}
