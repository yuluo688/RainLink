package session

import (
	"context"
	"fmt"
	"net/http"
)

// MobileConnections exposes only the portable telemetry operations of Manager.
// It never starts a subprocess, changes capture, or calls desktop lifecycle APIs.
// The caller owns the supplied client and cancels its context on service stop.
type MobileConnections struct{ manager *Manager }

// NewMobileConnections reuses the same snapshot paging, ID validation, outbound
// attribution and confirmed stream termination as the desktop implementation.
func NewMobileConnections(prepared MobileConfiguration, client *http.Client, logs *MobileLogs) *MobileConnections {
	return &MobileConnections{manager: &Manager{
		active: &runningCore{api: fmt.Sprintf("http://127.0.0.1:%d", prepared.APIPort),
			secret: prepared.APISecret, client: client, snapshot: prepared.Snapshot, outboundNames: prepared.OutboundNames, trafficTargets: prepared.TrafficTargets},
		logs: logs.writer.logs,
	}}
}

// Page reads a stable bounded page scoped to the caller's active session.
func (c *MobileConnections) Page(ctx context.Context, sessionID, snapshotID string, cursor int) (ConnectionPage, error) {
	if sessionID == "" {
		return ConnectionPage{}, fail("invalid_request", "连接会话标识无效")
	}
	return c.manager.Connections(ctx, sessionID, snapshotID, cursor)
}

// Close confirms disappearance of the requested stream IDs before succeeding.
func (c *MobileConnections) Close(ctx context.Context, sessionID, connectionID string, all bool) error {
	return c.manager.CloseConnections(ctx, sessionID, connectionID, all)
}

// Traffic reads cumulative accounting including flows which have already closed.
func (c *MobileConnections) Traffic(ctx context.Context, sessionID string) (TrafficSnapshot, error) {
	return c.manager.Traffic(ctx, sessionID)
}
