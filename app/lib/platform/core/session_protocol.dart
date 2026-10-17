import '../../domain/connection/connection_models.dart';
import '../../domain/core/core_gateway.dart';
import '../../domain/core/session_gateway.dart';

abstract final class SessionProtocol {
  static SessionObservation decode(Map<String, Object?> data) {
    if (data case {'phase': 'idle', 'error': String error}) {
      return SessionObservation(
          phase: error.isEmpty ? ConnectionPhase.idle : ConnectionPhase.failed,
          error: error);
    }
    // Older node hosts return `node`; chain sessions return a public target
    // identity and hop bindings, without inventing a synthetic node.
    final identity = data['target'] ?? data['node'];
    final kind =
        identity is Map<String, Object?> ? identity['kind'] ?? 'node' : null;
    if (data
        case {
          'phase': String phase,
          'sessionId': String session,
          'mode': String mode,
          'configRevision': String config,
          'systemProxy': bool capture
        }
        when (phase == 'connected' || phase == 'failed') &&
            (kind == 'node' || kind == 'chain')) {
      if (identity is! Map<String, Object?> ||
          identity['id'] is! String ||
          identity['name'] is! String ||
          identity['revision'] is! int) {
        throw const CoreGatewayException('invalid_response', '连接目标无效');
      }
      final id = identity['id'] as String;
      final name = identity['name'] as String;
      final revision = identity['revision'] as int;
      final modes = ProxyMode.values.where((value) => value.name == mode);
      final port = data['proxyPort'] ?? 0;
      final ruleRevision = data['ruleRevision'] ?? 0;
      final tun = data['tun'] ?? false;
      if (tun is! bool) {
        throw const CoreGatewayException('invalid_response', 'TUN 状态无效');
      }
      if (tun &&
          (data['tunInterface'] is! String ||
              (data['tunInterface'] as String).isEmpty)) {
        throw const CoreGatewayException('invalid_response', 'TUN 网卡回执无效');
      }
      final bindings = data['routeBindings'];
      if (ruleRevision is! int ||
          ruleRevision < 0 ||
          bindings != null && bindings is! Map<String, Object?>) {
        throw const CoreGatewayException('invalid_response', '规则快照无效');
      }
      final routeBindings = <String, RouteBinding>{};
      if (bindings is Map<String, Object?>) {
        for (final entry in bindings.entries) {
          if (entry.value
              case {'id': String nodeId, 'revision': int nodeRevision}
              when nodeId.isNotEmpty && nodeRevision > 0) {
            routeBindings[entry.key] = RouteBinding(nodeId, nodeRevision);
          } else {
            throw const CoreGatewayException('invalid_response', '规则出站快照无效');
          }
        }
      }
      if (port is! int || port < 0 || port > 65535) {
        throw const CoreGatewayException('invalid_response', '本地代理端口无效');
      }
      if (session.isEmpty ||
          id.isEmpty ||
          revision < 1 ||
          config.isEmpty ||
          modes.isEmpty) {
        throw const CoreGatewayException('invalid_response', '连接状态无效');
      }
      return SessionObservation(
          phase: phase == 'connected'
              ? ConnectionPhase.connected
              : ConnectionPhase.failed,
          error: data['error'] as String? ?? '',
          active: ActiveConnectionSnapshot(
              sessionId: session,
              target: ProxyTarget(
                  id: id, name: name, revision: revision, kind: kind as String),
              mode: modes.first,
              configRevision: config,
              ruleRevision: ruleRevision,
              routeBindings: Map.unmodifiable(routeBindings),
              proxyPort: port),
          systemProxy: capture,
          tun: tun,
          telemetry: _telemetry(data['telemetry']));
    }
    throw const CoreGatewayException('invalid_response', '连接状态无效');
  }

  static SessionTelemetry? _telemetry(Object? value) {
    if (value == null) return null;
    if (value
        case {
          'upload': int upload,
          'download': int download,
          'uploadTotal': int upTotal,
          'downloadTotal': int downTotal,
          'ip': String ip,
          'country': String country,
          'countryCode': String code,
          'latency': final latency,
          'probeError': String error
        }
        when upload >= 0 &&
            download >= 0 &&
            upTotal >= 0 &&
            downTotal >= 0 &&
            (latency == null || latency is int && latency >= 0)) {
      return SessionTelemetry(
          upload: upload,
          download: download,
          uploadTotal: upTotal,
          downloadTotal: downTotal,
          ip: ip,
          country: country,
          countryCode: code,
          latency: latency as int?,
          latencyAt: (value as Map<String, Object?>)['latencyAt'] as int? ?? 0,
          probeError: error);
    }
    throw const CoreGatewayException('invalid_response', '流量数据无效');
  }
}
