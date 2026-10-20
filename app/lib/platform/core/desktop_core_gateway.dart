import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/connection/connection_models.dart';
import '../../domain/core/core_gateway.dart';
import '../../domain/core/core_status.dart';
import '../../domain/core/session_gateway.dart';
import '../../domain/core/core_telemetry.dart';
import '../../domain/core/core_traffic.dart';
import '../../domain/connection/traffic_accounting.dart';
import '../../domain/nodes/proxy_node.dart';
import '../../domain/routing/route_rules.dart';
import '../../domain/chains/proxy_chain.dart';
import '../../domain/nodes/node_probe.dart';
import '../../domain/core/runtime_settings.dart';
import 'desktop_settings_gateway.dart';
import 'desktop_probe_gateway.dart';
import 'host_command_runner.dart';
import 'host_session_client.dart';
import 'host_status_protocol.dart';
import 'session_protocol.dart';
import 'core_telemetry_protocol.dart';
import 'core_traffic_protocol.dart';

/// Diagnostics are one-shot; connection operations use one owned host session.
class DesktopCoreGateway
    implements
        CoreGateway,
        SessionGateway,
        SecretStore,
        CoreTelemetryGateway,
        CoreTrafficGateway,
        RouteRuleValidator,
        ChainTester,
        NodeTester,
        RuntimeSettingsGateway {
  DesktopCoreGateway({String? executablePath, HostCommandRunner? commandRunner})
    : executablePath = executablePath ?? _defaultExecutable(),
      // Linux status also verifies the installed host/core and systemd state.
      // Allow its bounded native inspection to finish after core discovery.
      _commandRunner =
          commandRunner ??
          ProcessHostCommandRunner(timeout: const Duration(seconds: 20));

  final String executablePath;
  final HostCommandRunner _commandRunner;
  DesktopProbeGateway? _probeAdapter;
  DesktopSettingsGateway? _settingsAdapter;
  DesktopProbeGateway get _probes =>
      _probeAdapter ??= DesktopProbeGateway(executablePath);
  DesktopSettingsGateway get _settings =>
      _settingsAdapter ??= DesktopSettingsGateway(executablePath);
  Future<CoreStatus>? _inspection;
  bool _disposed = false;
  HostSessionClient? _session;
  Future<void>? _handshake;
  int _connectionGeneration = 0;
  final _failures = StreamController<Exception>.broadcast();
  StreamSubscription<Exception>? _sessionFailures;

  HostSessionClient get _client {
    if (_session == null || (_session?.terminated ?? false)) {
      final previous = _session;
      if (previous != null) unawaited(previous.close());
      unawaited(_sessionFailures?.cancel());
      _handshake = null;
      final client = _session = HostSessionClient(executablePath);
      _sessionFailures = client.failures.listen((error) {
        _handshake = null;
        if (!_disposed) _failures.add(error);
      });
    }
    return _session ?? (throw StateError('Session initialization failed'));
  }

  @override
  Stream<Exception> get failures => _failures.stream;

  Future<void> _ready() async {
    _ensureActive();
    _client;
    return _handshake ??= _hello().catchError((Object error) {
      _handshake = null;
      Error.throwWithStackTrace(error, StackTrace.current);
    });
  }

  Future<void> _hello() async {
    final result = await _client.request('hello');
    if (result case {
      'protocolVersion': 2,
      'coreVersion': String version,
    } when version.isNotEmpty) {
      return;
    }
    throw const CoreGatewayException('invalid_response', '宿主会话版本不兼容');
  }

  static String _defaultExecutable() {
    const configured = String.fromEnvironment('RAINLINK_HOST_PATH');
    if (configured.isNotEmpty) return configured;
    return p.join(
      p.dirname(Platform.resolvedExecutable),
      Platform.isWindows ? 'rainlink-host.exe' : 'rainlink-host',
    );
  }

  @override
  Future<CoreStatus> inspect() {
    if (_disposed) {
      return Future.error(const CoreGatewayException('disposed', '核心接口已关闭'));
    }
    // Share only in-flight work. A later refresh still reads current host state.
    return _inspection ??= _inspect().whenComplete(() => _inspection = null);
  }

  Future<CoreStatus> _inspect() async {
    final exists = await File(executablePath).exists();
    _ensureActive();
    if (!exists) return const CoreStatus.unavailable('未找到桌面宿主');
    final result = await _commandRunner.run(executablePath, const ['status']);
    _ensureActive();
    if (result.exitCode != 0) {
      throw const CoreGatewayException('host_failed', '桌面宿主检查失败');
    }
    return HostStatusProtocol.decode(result.stdout);
  }

  @override
  Future<ActiveConnectionSnapshot> connect(ConnectRequest request) async {
    final generation = ++_connectionGeneration;
    await _ready();
    if (generation != _connectionGeneration) {
      throw const CoreGatewayException('cancelled', '连接已取消');
    }
    final node = request.node;
    final chain = request.chain;
    if (chain != null
        ? (node != null ||
            request.target.kind != 'chain' ||
            chain.chain.id != request.target.id ||
            chain.chain.revision != request.target.revision)
        : (node == null ||
            request.target.kind != 'node' ||
            node.id != request.target.id ||
            node.revision != request.target.revision)) {
      throw const CoreGatewayException('invalid_node', '请选择有效的连接节点');
    }
    final result = await _client.request('connect', {
      if (node != null) 'node': node.toHost(),
      if (chain != null) 'chain': chain.toHost(),
      'mode': request.mode.name,
      'systemProxy': request.systemProxy,
      'tun': request.tun,
      'runtimeSettings': request.runtimeSettings.validated().toJson(),
      if (request.routing case final plan?) 'routing': plan.toHost(),
    });
    _ensureActive();
    final observation = SessionProtocol.decode(result);
    final active = observation.active;
    if (observation.tun != request.tun ||
        observation.systemProxy != request.systemProxy) {
      await _client.request('disconnect');
      throw const CoreGatewayException(
        'invalid_response',
        '核心应用的系统代理或 TUN 状态与请求不一致',
      );
    }
    final appliedSettings = result['runtimeSettings'];
    if (appliedSettings is! Map<String, Object?> ||
        !request.runtimeSettings.toJson().entries.every(
          (entry) => appliedSettings[entry.key] == entry.value,
        )) {
      await _client.request('disconnect');
      throw const CoreGatewayException(
        'invalid_response',
        '核心应用的网络设置与保存配置不一致，请更新宿主后重试',
      );
    }
    if (active == null ||
        active.target.id != request.target.id ||
        active.target.kind != request.target.kind ||
        active.target.revision != request.target.revision) {
      await _client.request('disconnect');
      throw const CoreGatewayException('invalid_response', '核心应用的节点与选择不一致');
    }
    final plan = request.routing;
    if (plan != null &&
        (active.ruleRevision != plan.ruleSet.revision ||
            !plan.matchesBindings(active.routeBindings))) {
      await _client.request('disconnect');
      throw const CoreGatewayException('invalid_response', '核心应用的规则与保存配置不一致');
    }
    return active;
  }

  @override
  Future<void> validateRules(RouteRuleSet rules) async {
    await _ready();
    await _client.request('validateRules', rules.validated().toJson());
  }

  @override
  Future<void> validateChain(ChainSnapshot chain) =>
      _probes.validateChain(chain);
  @override
  Future<ChainTestResult> testChain(ChainSnapshot chain) =>
      _probes.testChain(chain);
  @override
  Future<void> cancelChainTest() => _probes.cancelChainTest();

  @override
  Future<NodeProbeResult> testNode(ProxyNode node) => _probes.testNode(node);
  @override
  Future<void> cancelNodeTests() => _probes.cancelNodeTests();

  @override
  Future<void> validateRuntime(CoreRuntimeSettings settings) =>
      _settings.validateRuntime(settings);
  @override
  Future<DnsTestResult> testDns(CoreRuntimeSettings settings) =>
      _settings.testDns(settings);
  @override
  Future<void> cancelDnsTest() => _settings.cancelDnsTest();

  @override
  Future<void> cancelValidation() => _settings.cancelValidation();

  @override
  Future<void> disconnect() async {
    _ensureActive();
    ++_connectionGeneration;
    if (_session != null) {
      await _ready();
      await _client.request('disconnect');
    }
  }

  @override
  Future<SessionObservation> observe() async {
    await _ready();
    return SessionProtocol.decode(await _client.request('snapshot'));
  }

  @override
  Future<void> setMode(ProxyMode mode) async {
    await _ready();
    await _client.request('mode', {'mode': mode.name});
  }

  @override
  Future<void> setSystemProxy(bool enabled) async {
    await _ready();
    await _client.request('capture', {'enabled': enabled});
  }

  @override
  Future<void> probe() async {
    await _ready();
    await _client.request('probe');
  }

  @override
  Future<ConnectionsSnapshot> connections({required String sessionId}) async {
    await _ready();
    return CoreTelemetryProtocol.readConnections(
      sessionId: sessionId,
      loadPage: (arguments) => _client.request('connections', arguments),
    );
  }

  @override
  Future<TrafficAccountingSnapshot> traffic({required String sessionId}) async {
    await _ready();
    return CoreTrafficProtocol.parse(
      await _client.request('traffic', {'sessionId': sessionId}),
      sessionId: sessionId,
    );
  }

  @override
  Future<void> closeConnections({
    required String sessionId,
    String? connectionId,
  }) async {
    await _ready();
    await _client.request('closeConnections', {
      'sessionId': sessionId,
      'connectionId': connectionId ?? '',
      'all': connectionId == null,
    });
  }

  @override
  Future<CoreLogBatch> logs({String stream = '', int after = 0}) async {
    await _ready();
    return CoreTelemetryProtocol.logs(
      await _client.request('logs', {'stream': stream, 'after': after}),
    );
  }

  @override
  Future<CoreLogBatch> clearLogs() async {
    await _ready();
    return CoreTelemetryProtocol.logs(await _client.request('clearLogs'));
  }

  @override
  Future<void> cancel() async {
    ++_connectionGeneration;
    if (_session != null) await _client.request('cancel');
  }

  @override
  Future<String> protect(
    String nodeId,
    String username,
    String password, {
    String obfsPassword = '',
  }) async {
    await _ready();
    final result = await _client.request('protect', {
      'id': nodeId,
      'username': username,
      'password': password,
      'obfsPassword': obfsPassword,
    });
    if (result case {'cipher': String cipher} when cipher.isNotEmpty) {
      return cipher;
    }
    throw const CoreGatewayException('invalid_response', '凭据保存响应无效');
  }

  @override
  Future<NodeCredentials> reveal(String id, String cipher) async {
    await _ready();
    final result = await _client.request('reveal', {
      'id': id,
      'cipher': cipher,
    });
    if (result case {
      'username': String username,
      'password': String password,
    }) {
      final obfs = result['obfsPassword'];
      if (obfs != null && obfs is! String) {
        throw const CoreGatewayException('invalid_response', '凭据读取响应无效');
      }
      return NodeCredentials(
        username: username,
        password: password,
        obfsPassword: obfs as String? ?? '',
      );
    }
    throw const CoreGatewayException('invalid_response', '凭据读取响应无效');
  }

  @override
  Future<void> close() async {
    final probes = _probeAdapter;
    final settings = _settingsAdapter;
    _probeAdapter = null;
    _settingsAdapter = null;
    await probes?.close();
    await settings?.close();
    await _sessionFailures?.cancel();
    _sessionFailures = null;
    final session = _session;
    _session = null;
    _handshake = null;
    await session?.close();
  }

  void _ensureActive() {
    if (_disposed) {
      throw const CoreGatewayException('disposed', '核心接口已关闭');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _commandRunner.dispose();
    unawaited(close());
    unawaited(_sessionFailures?.cancel());
    unawaited(_failures.close());
  }
}
