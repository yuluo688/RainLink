import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/chains/proxy_chain.dart';
import '../../domain/connection/connection_models.dart';
import '../../domain/core/core_gateway.dart';
import '../../domain/core/core_status.dart';
import '../../domain/core/core_telemetry.dart';
import '../../domain/core/core_traffic.dart';
import '../../domain/connection/traffic_accounting.dart';
import '../../domain/core/runtime_settings.dart';
import '../../domain/core/session_gateway.dart';
import '../../domain/nodes/node_probe.dart';
import '../../domain/nodes/proxy_node.dart';
import '../../domain/routing/route_rules.dart';
import 'session_protocol.dart';
import 'session_request_protocol.dart';
import 'core_telemetry_protocol.dart';
import 'core_traffic_protocol.dart';

/// Thin transport to the Android service. No native configuration or plaintext
/// connection credentials are returned to the Flutter presentation layer.
class AndroidCoreGateway
    implements
        SessionGateway,
        SessionRecoveryGateway,
        SecretStore,
        RouteRuleValidator,
        NodeTester,
        ChainTester,
        CoreTelemetryGateway,
        CoreTrafficGateway,
        RuntimeSettingsGateway {
  AndroidCoreGateway({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('rainlink/core');

  final MethodChannel _channel;
  bool _disposed = false;
  int _generation = 0;
  int _testGeneration = 0;
  int _testId = 0;
  int _tests = 0;
  int _dnsGeneration = 0;

  Future<Map<String, Object?>> _request(
    String method, [
    Map<String, Object?> arguments = const {},
    Duration timeout = const Duration(seconds: 15),
  ]) async {
    if (_disposed) {
      throw const CoreGatewayException('disposed', '核心接口已关闭');
    }
    try {
      final raw = await _channel
          .invokeMethod<String>(method, jsonEncode(arguments))
          .timeout(timeout);
      if (raw == null || raw.length > 8 * 1024 * 1024) {
        throw const FormatException();
      }
      final value = jsonDecode(raw);
      if (value is! Map<String, Object?>) throw const FormatException();
      return value;
    } on PlatformException catch (error) {
      throw CoreGatewayException(error.code, error.message ?? 'Android 网络操作失败');
    } on MissingPluginException {
      throw const CoreGatewayException('unavailable', '未找到 Android 网络服务');
    } on TimeoutException {
      throw const CoreGatewayException('timeout', 'Android 网络操作超时，请重试');
    } on FormatException {
      throw const CoreGatewayException('invalid_response', 'Android 网络响应无效');
    }
  }

  @override
  Stream<Exception> get failures => const Stream.empty();

  @override
  Future<CoreStatus> inspect() async {
    final status = await _request('status');
    if (status case {
      'coreVersion': String version,
      'requiresTun': true,
    } when version.isNotEmpty) {
      return CoreStatus(
        hostAvailable: true,
        hostVersion: 'android-1',
        coreVersion: version,
        message: 'Android 网络服务已就绪',
        capabilities: const CoreCapabilities(
          connect: true,
          tun: true,
          requiresTun: true,
        ),
      );
    }
    throw const CoreGatewayException('invalid_response', 'Android 核心能力响应无效');
  }

  @override
  Future<ConnectionsSnapshot> connections({required String sessionId}) =>
      CoreTelemetryProtocol.readConnections(
        sessionId: sessionId,
        loadPage: (arguments) => _request('connections', arguments),
      );

  @override
  Future<void> closeConnections({
    required String sessionId,
    String? connectionId,
  }) async {
    await _request('closeConnections', {
      'sessionId': sessionId,
      'connectionId': connectionId ?? '',
      'all': connectionId == null,
    });
  }

  @override
  Future<TrafficAccountingSnapshot> traffic({
    required String sessionId,
  }) async => CoreTrafficProtocol.parse(
    await _request('traffic', {'sessionId': sessionId}),
    sessionId: sessionId,
  );

  @override
  Future<CoreLogBatch> logs({String stream = '', int after = 0}) async =>
      CoreTelemetryProtocol.logs(
        await _request('logs', {'stream': stream, 'after': after}),
      );

  @override
  Future<CoreLogBatch> clearLogs() async =>
      CoreTelemetryProtocol.logs(await _request('clearLogs'));

  @override
  Future<ActiveConnectionSnapshot> connect(ConnectRequest request) async {
    if (!request.tun || request.systemProxy) {
      throw const CoreGatewayException(
        'invalid_capture',
        'Android 连接须启用系统隧道，不使用桌面系统代理',
      );
    }
    final generation = ++_generation;
    final node = request.node;
    final chain = request.chain;
    if (chain != null
        ? node != null ||
            request.target.kind != 'chain' ||
            chain.chain.id != request.target.id ||
            chain.chain.revision != request.target.revision
        : node == null ||
            request.target.kind != 'node' ||
            node.id != request.target.id ||
            node.revision != request.target.revision) {
      throw const CoreGatewayException('invalid_node', '请选择有效的连接目标');
    }
    Map<String, Object?> result;
    try {
      result = await _request('connect', {
        if (node != null) 'node': node.toHost(),
        if (chain != null) 'chain': chain.toHost(),
        'mode': request.mode.name,
        'systemProxy': false,
        'tun': true,
        'runtimeSettings': request.runtimeSettings.validated().toJson(),
        if (request.routing case final plan?) 'routing': plan.toHost(),
      }, const Duration(seconds: 90));
    } on CoreGatewayException catch (error) {
      if (error.code == 'timeout') await _request('cancel');
      rethrow;
    }
    if (generation != _generation) {
      throw const CoreGatewayException('cancelled', '连接已取消');
    }
    try {
      return _verifyReceipt(result, request).active!;
    } on Exception {
      await _request('disconnect');
      rethrow;
    }
  }

  SessionObservation _verifyReceipt(
    Map<String, Object?> result,
    ConnectRequest request,
  ) {
    final observation = SessionProtocol.decode(result);
    final active = observation.active;
    final rawSettings = result['runtimeSettings'];
    if (rawSettings is! Map<String, Object?>) {
      throw const CoreGatewayException('invalid_response', 'Android 网络设置回执无效');
    }
    final Map<String, Object?> settings;
    try {
      // The native core omits an empty advanced patch. Parse both wire forms
      // through the same validated model before comparing the applied snapshot.
      settings = CoreRuntimeSettings.fromJson(rawSettings).toJson();
    } on SettingsException {
      throw const CoreGatewayException('invalid_response', 'Android 网络设置回执无效');
    }
    final plan = request.routing;
    if (active == null ||
        !observation.tun ||
        observation.systemProxy ||
        active.target.id != request.target.id ||
        active.target.kind != request.target.kind ||
        active.target.revision != request.target.revision ||
        active.mode != request.mode ||
        !request.runtimeSettings.toJson().entries.every(
          (entry) => settings[entry.key] == entry.value,
        ) ||
        plan != null &&
            (active.ruleRevision != plan.ruleSet.revision ||
                !plan.matchesBindings(active.routeBindings))) {
      throw const CoreGatewayException(
        'invalid_response',
        'Android 实际连接与请求不一致',
      );
    }
    return observation;
  }

  @override
  Future<RecoveredSession> recoverSession() async {
    final result = await _request('restore');
    final observation = SessionProtocol.decode(result);
    if (observation.active == null) return RecoveredSession(observation, null);
    try {
      final request = SessionRequestProtocol.decode(result['request']);
      return RecoveredSession(_verifyReceipt(result, request), request);
    } on Exception {
      await disconnect();
      rethrow;
    }
  }

  @override
  Future<SessionObservation> observe() async =>
      SessionProtocol.decode(await _request('snapshot'));
  @override
  Future<void> disconnect() async {
    ++_generation;
    await _request('disconnect');
  }

  @override
  Future<void> cancel() async {
    ++_generation;
    await _request('cancel');
  }

  @override
  Future<void> setMode(ProxyMode mode) async {
    await _request('mode', {'mode': mode.name});
  }

  @override
  Future<void> setSystemProxy(bool enabled) async {
    throw const CoreGatewayException('unsupported', 'Android 通过系统隧道接管网络');
  }

  @override
  Future<void> probe() async {
    await _request('probe');
  }

  @override
  Future<String> protect(
    String nodeId,
    String username,
    String password, {
    String obfsPassword = '',
  }) async {
    final value = await _request('protect', {
      'id': nodeId,
      'username': username,
      'password': password,
      'obfsPassword': obfsPassword,
    });
    if (value case {'cipher': String cipher} when cipher.startsWith('rlk1.')) {
      return cipher;
    }
    throw const CoreGatewayException('invalid_response', '安全凭据保存响应无效');
  }

  @override
  Future<NodeCredentials> reveal(String id, String cipher) async {
    final value = await _request('reveal', {'id': id, 'cipher': cipher});
    if (value case {
      'username': String username,
      'password': String password,
      'obfsPassword': String obfs,
    }) {
      return NodeCredentials(
        username: username,
        password: password,
        obfsPassword: obfs,
      );
    }
    throw const CoreGatewayException('invalid_response', '安全凭据读取响应无效');
  }

  Map<String, Object?> _temporary({
    ProxyNode? node,
    ChainSnapshot? chain,
    CoreRuntimeSettings settings = const CoreRuntimeSettings(),
  }) => {
    if (node != null) 'node': node.toHost(),
    if (chain != null) 'chain': chain.toHost(),
    'mode': 'global',
    'tun': false,
    'systemProxy': false,
    'runtimeSettings': settings.validated().toJson(),
  };
  Future<int> _measure({ProxyNode? node, ChainSnapshot? chain}) async {
    final value = await _request('measure', {
      ..._temporary(node: node, chain: chain),
      'testId': 'probe-${++_testId}',
    }, const Duration(seconds: 25));
    if (value case {
      'latency': int latency,
    } when latency >= 0 && latency <= 60000) {
      return latency;
    }
    throw const NodeException('节点测速响应无效');
  }

  @override
  Future<NodeProbeResult> testNode(ProxyNode node) async {
    if (_tests >= nodeProbeConcurrency) throw const NodeException('测速并发已满');
    final generation = _testGeneration;
    _tests++;
    try {
      final latency = await _measure(node: node);
      if (generation != _testGeneration) {
        throw const CoreGatewayException('cancelled', '测试已取消');
      }
      return NodeProbeResult(
        nodeId: node.id,
        revision: node.revision,
        checkedAt: DateTime.now(),
        passed: true,
        latency: latency,
      );
    } on CoreGatewayException catch (error) {
      if (generation != _testGeneration || error.code == 'cancelled') rethrow;
      return NodeProbeResult(
        nodeId: node.id,
        revision: node.revision,
        checkedAt: DateTime.now(),
        passed: false,
        error: error.message,
      );
    } finally {
      _tests--;
    }
  }

  @override
  Future<void> cancelNodeTests() async {
    ++_testGeneration;
    await _request('cancelTests');
  }

  @override
  Future<void> validateChain(ChainSnapshot chain) async {
    chain.validate();
    await _request('validate', _temporary(chain: chain));
  }

  @override
  Future<ChainTestResult> testChain(ChainSnapshot chain) async {
    chain.validate();
    final generation = _testGeneration;
    final results = <ChainHopTest>[];
    for (var index = 0; index < chain.hops.length; index++) {
      if (generation != _testGeneration) throw const ChainException('链路测试已取消');
      try {
        final prefix = chain.hops.sublist(0, index + 1);
        final latency = await _measure(
          node: index == 0 ? prefix.first : null,
          chain:
              index == 0
                  ? null
                  : ChainSnapshot(
                    ProxyChain(
                      id: chain.chain.id,
                      name: chain.chain.name,
                      revision: chain.chain.revision,
                      hopIds: prefix.map((node) => node.id).toList(),
                    ),
                    prefix,
                  ),
        );
        if (generation != _testGeneration) {
          throw const ChainException('链路测试已取消');
        }
        results.add(
          ChainHopTest(hop: index + 1, latency: latency, passed: true),
        );
      } on CoreGatewayException catch (error) {
        if (generation != _testGeneration) {
          throw const ChainException('链路测试已取消');
        }
        results.add(
          ChainHopTest(
            hop: index + 1,
            latency: 0,
            passed: false,
            error: error.message,
          ),
        );
        break;
      }
    }
    return ChainTestResult(
      fingerprint: chain.fingerprint,
      checkedAt: DateTime.now(),
      passed:
          results.length == chain.hops.length &&
          results.every((hop) => hop.passed),
      hops: results,
    );
  }

  @override
  Future<void> cancelChainTest() => cancelNodeTests();
  @override
  Future<void> validateRules(RouteRuleSet rules) async {
    await _request('validateRules', rules.validated().toJson());
  }

  @override
  Future<void> validateRuntime(CoreRuntimeSettings settings) async {
    await _request(
      'validate',
      _temporary(
        settings: settings,
        node: const ProxyNode(
          id: 'settings-check',
          name: '配置校验',
          protocol: NodeProtocol.http,
          server: '127.0.0.1',
          port: 9,
        ),
      ),
    );
  }

  @override
  Future<void> cancelValidation() async {}
  @override
  Future<DnsTestResult> testDns(CoreRuntimeSettings settings) async {
    final generation = ++_dnsGeneration;
    final result = await _request('testDns', settings.validated().toJson());
    if (generation != _dnsGeneration) throw const SettingsException('解析测试已取消');
    return DnsTestResult.fromJson(result);
  }

  @override
  Future<void> cancelDnsTest() async {
    ++_dnsGeneration;
    await _request('cancelDns');
  }

  @override
  Future<void> close() async {
    if (_disposed) return;
    try {
      await cancelNodeTests();
    } finally {
      try {
        await cancelDnsTest();
      } finally {
        await disconnect();
      }
    }
  }

  @override
  void dispose() {
    // Destroying an Activity must not tear down its foreground network service.
    _disposed = true;
  }
}
