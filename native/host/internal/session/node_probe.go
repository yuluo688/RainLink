package session

import (
	"context"
	"crypto/x509"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"time"
)

const nodeProbeTimeout = 8 * time.Second

// NodeProbeResult identifies the exact saved revision tested through an isolated core.
type NodeProbeResult struct {
	NodeID      string `json:"nodeId"`
	Revision    int    `json:"revision"`
	CheckedAt   int64  `json:"checkedAt"`
	Passed      bool   `json:"passed"`
	Latency     int64  `json:"latency"`
	Error       string `json:"error"`
	FailureCode string `json:"failureCode,omitempty"`
	HTTPStatus  int    `json:"httpStatus,omitempty"`
}

// TestNode never uses a live manager or changes system capture settings.
func (m *Manager) TestNode(ctx context.Context, node Node) (NodeProbeResult, error) {
	if !m.isolated {
		return NodeProbeResult{}, fail("isolated_probe", "请使用独立测试宿主")
	}
	return m.testNode(ctx, node, chainProbeEndpoint)
}

func (m *Manager) testNode(ctx context.Context, node Node, endpoint string) (NodeProbeResult, error) {
	result := NodeProbeResult{NodeID: node.ID, Revision: node.Revision}
	if !routeIDPattern.MatchString(node.ID) {
		return result, fail("invalid_node", "节点标识无效")
	}
	if err := node.validate(); err != nil {
		return result, err
	}
	measurement, err := m.probePath(ctx, node, nil, endpoint)
	if err != nil {
		return result, err
	}
	result.CheckedAt = time.Now().UnixMilli()
	result.Latency = measurement.latency
	result.Passed = measurement.passed
	if !measurement.passed {
		result.FailureCode = measurement.failure
		result.HTTPStatus = measurement.status
		switch measurement.failure {
		case "timeout":
			result.Error = "测试站连接超时，请检查节点和网络"
		case "tls_failed":
			result.Error = "测试站的 TLS 证书验证失败"
		case "http_status":
			result.Error = fmt.Sprintf("测试站返回 HTTP %d，未通过延迟测试", measurement.status)
		case "core_start_failed":
			result.Error = "临时核心启动失败，请检查节点配置"
		default:
			result.Error = "测速未通过，请检查节点认证、网络和测试目标可达性"
		}
	}
	return result, nil
}

// probePath shares bounded HTTP probing and cleanup between nodes and chain prefixes.
type probeMeasurement struct {
	latency int64
	passed  bool
	failure string
	status  int
}

func probeFailure(err error) string {
	var timeout net.Error
	if errors.As(err, &timeout) && timeout.Timeout() {
		return "timeout"
	}
	var authority x509.UnknownAuthorityError
	var certificate x509.CertificateInvalidError
	if errors.As(err, &authority) || errors.As(err, &certificate) {
		return "tls_failed"
	}
	return "request_failed"
}

func (m *Manager) probePath(ctx context.Context, node Node, chain *ChainSnapshot, endpoint string) (probeMeasurement, error) {
	measurement := probeMeasurement{failure: "core_start_failed"}
	if ctx.Err() != nil {
		return measurement, fail("cancelled", "测试已取消")
	}
	probeCtx, cancel := context.WithTimeout(ctx, nodeProbeTimeout)
	defer cancel()
	manager := New(m.corePath, m.stateDir)
	manager.isolated = true
	snapshot, err := manager.connectTarget(probeCtx, node, chain, "global", false, nil, false)
	if err == nil {
		measurement.failure = "request_failed"
		proxy, parseErr := url.Parse("http://127.0.0.1:" + strconv.Itoa(snapshot.ProxyPort))
		if parseErr != nil {
			err = parseErr
		} else {
			transport := &http.Transport{Proxy: http.ProxyURL(proxy), DisableKeepAlives: true}
			client := &http.Client{Transport: transport, Timeout: 5 * time.Second,
				CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
			started := time.Now()
			request, requestErr := http.NewRequestWithContext(probeCtx, http.MethodGet, endpoint, nil)
			if requestErr == nil {
				response, responseErr := client.Do(request)
				if responseErr != nil {
					measurement.failure = probeFailure(responseErr)
				}
				if response != nil {
					length, readErr := io.Copy(io.Discard, io.LimitReader(response.Body, 4097))
					closeErr := response.Body.Close()
					measurement.passed = responseErr == nil && readErr == nil && closeErr == nil &&
						length <= 4096 && response.StatusCode == http.StatusNoContent
					if !measurement.passed && responseErr == nil {
						measurement.failure = "invalid_response"
						if response.StatusCode != http.StatusNoContent {
							measurement.failure = "http_status"
							measurement.status = response.StatusCode
						}
					}
				}
			}
			measurement.latency = time.Since(started).Milliseconds()
			client.CloseIdleConnections()
		}
	}
	if cleanupErr := manager.Disconnect(); cleanupErr != nil {
		return measurement, fail("probe_cleanup_failed", "临时测试核心未能退出，请重试取消")
	}
	if ctx.Err() != nil {
		return measurement, fail("cancelled", "测试已取消")
	}
	return measurement, nil
}
