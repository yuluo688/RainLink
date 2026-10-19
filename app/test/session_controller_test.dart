import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/connection/traffic_repository.dart';
import 'package:rainlink/domain/core/core_gateway.dart';
import 'package:rainlink/domain/core/core_status.dart';
import 'package:rainlink/domain/core/session_gateway.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/core/runtime_settings.dart';

const node = ProxyNode(
    id: 'a',
    name: 'A',
    protocol: NodeProtocol.http,
    server: '127.0.0.1',
    port: 8080);
const active = ActiveConnectionSnapshot(
    sessionId: 'test-session',
    target: ProxyTarget(id: 'a', name: 'A', revision: 1),
    mode: ProxyMode.rule,
    configRevision: 'config');

class _Gateway implements SessionGateway {
  final errors = StreamController<Exception>.broadcast();
  Completer<ActiveConnectionSnapshot>? connecting;
  bool rejectMode = false;
  bool rejectTun = false;
  bool observedTun = false;
  Completer<void>? modeChange;
  Completer<void>? captureChange;
  int disconnects = 0;
  int cancels = 0;
  final requests = <ConnectRequest>[];
  ProxyMode observedMode = ProxyMode.rule;
  @override
  Stream<Exception> get failures => errors.stream;
  @override
  Future<CoreStatus> inspect() async =>
      const CoreStatus(hostAvailable: true, message: 'ready');
  @override
  Future<ActiveConnectionSnapshot> connect(ConnectRequest request) {
    requests.add(request);
    observedMode = request.mode;
    if (request.tun && rejectTun) {
      throw const CoreGatewayException('tun_permission_denied', '已取消 TUN 权限申请');
    }
    observedTun = request.tun;
    return connecting?.future ?? Future.value(active);
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }

  @override
  Future<SessionObservation> observe() async => SessionObservation(
      phase: ConnectionPhase.connected,
      tun: observedTun,
      active: ActiveConnectionSnapshot(
          sessionId: active.sessionId,
          target: active.target,
          mode: observedMode,
          configRevision: active.configRevision),
      telemetry: const SessionTelemetry(
          uploadTotal: 100, downloadTotal: 200, latency: 17, latencyAt: 1));
  @override
  Future<void> setMode(ProxyMode mode) async {
    await modeChange?.future;
    if (rejectMode) throw const CoreGatewayException('mode_failed', '核心拒绝模式');
    observedMode = mode;
  }

  @override
  Future<void> setSystemProxy(bool enabled) async {
    await captureChange?.future;
  }

  @override
  Future<void> probe() async {}
  @override
  Future<void> close() async {}
  @override
  void dispose() {}
}

class _BrokenTraffic implements TrafficRepository {
  @override
  Stream<List<TrafficDay>> watchHistory() => Stream.value(const []);
  @override
  Stream<DailyTraffic> watchToday() => Stream.value(const DailyTraffic());
  @override
  Future<void> record(String sessionId, int uploadTotal, int downloadTotal,
          {TrafficAttribution attribution =
              TrafficAttribution.unassigned}) async =>
      throw const NodeException('磁盘写入失败');
}

class _RecoverableGateway extends _Gateway implements SessionRecoveryGateway {
  @override
  Future<RecoveredSession> recoverSession() async => RecoveredSession(
      await observe(),
      ConnectRequest(
          target: active.target,
          node: node,
          mode: observedMode,
          tun: true,
          runtimeSettings: const CoreRuntimeSettings(proxyPort: 17891)));
}

void main() {
  test('service installation prevents a concurrent connection attempt',
      () async {
    final gateway = _Gateway();
    addTearDown(gateway.errors.close);
    var serviceBusy = true;
    final controller = SessionController(gateway,
        onMode: (_) {}, serviceBusy: () => serviceBusy);
    addTearDown(controller.dispose);
    await controller.connect(node, ProxyMode.rule);
    expect(gateway.requests, isEmpty);
    expect(controller.state.error, contains('权限服务正在更新'));
    serviceBusy = false;
    await controller.connect(node, ProxyMode.rule);
    expect(gateway.requests, hasLength(1));
    expect(controller.state.connected, isTrue);
  });
  test('restored Android session can restart its original encrypted request',
      () async {
    final gateway = _RecoverableGateway()..observedTun = true;
    addTearDown(gateway.errors.close);
    final controller =
        SessionController(gateway, onMode: (_) {}, requiresTun: true);
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);
    expect(controller.canRestart, isTrue);
    expect(controller.appliedRuntimeSettings?.proxyPort, 17891);
    await controller.applyRuntime(const CoreRuntimeSettings(proxyPort: 17892));
    expect(gateway.requests.single.node, same(node));
    expect(gateway.requests.single.runtimeSettings.proxyPort, 17892);
    expect(controller.state.connected, isTrue);
  });
  test('Android adopts its existing service and enforces system tunnel capture',
      () async {
    final gateway = _Gateway()..observedTun = true;
    addTearDown(gateway.errors.close);
    final controller = SessionController(gateway,
        onMode: (_) {}, requiresTun: true, initialSystemProxy: true);
    addTearDown(controller.dispose);
    expect(controller.state.busy, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.active?.sessionId, active.sessionId);
    expect(controller.state.tun, isTrue);
    expect(controller.state.systemProxy, isFalse);
    await controller.setTun(false);
    await controller.setSystemProxy(true);
    expect(controller.state.tun, isTrue);
    expect(controller.state.systemProxy, isFalse);
    expect(gateway.requests, isEmpty);
    await controller.disconnect();
    await controller.connect(node, ProxyMode.rule);
    expect(gateway.requests.single.tun, isTrue);
    expect(gateway.requests.single.systemProxy, isFalse);
  });

  test('Android refuses a restored service with an invalid capture receipt',
      () async {
    final gateway = _Gateway();
    addTearDown(gateway.errors.close);
    final controller =
        SessionController(gateway, onMode: (_) {}, requiresTun: true);
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.active, isNull);
    expect(controller.state.phase, ConnectionPhase.failed);
    expect(gateway.disconnects, 1);
  });
  test('TUN selection, reconnect and settings restart retain the active target',
      () async {
    final gateway = _Gateway();
    addTearDown(gateway.errors.close);
    var runtime = const CoreRuntimeSettings();
    final controller = SessionController(gateway,
        onMode: (_) {}, runtimeSettings: () => runtime);
    addTearDown(controller.dispose);
    await controller.setTun(true);
    expect(gateway.requests, isEmpty);
    await controller.connect(node, ProxyMode.rule);
    expect(gateway.requests.single.tun, isTrue);
    expect(controller.state.tun, isTrue);
    await controller.refresh();
    expect(controller.state.tun, isTrue);
    runtime = runtime.copyWith(proxyPort: 17890);
    await controller.setTun(false);
    expect(gateway.requests.last.node, same(node));
    expect(gateway.requests.last.runtimeSettings.proxyPort, 0);
    expect(gateway.requests.last.tun, isFalse);
    expect(controller.state.connected, isTrue);
    await controller.setTun(true);
    await controller.restart();
    expect(gateway.requests.last.tun, isTrue);
    expect(gateway.requests.last.runtimeSettings.proxyPort, 17890);
    await controller.disconnect();
    expect(controller.state.tun, isTrue);
    expect(controller.state.active, isNull);
  });

  test(
      'declining TUN restores the previous working session without changing its snapshot',
      () async {
    final gateway = _Gateway()..rejectTun = true;
    addTearDown(gateway.errors.close);
    final controller = SessionController(gateway, onMode: (_) {});
    addTearDown(controller.dispose);
    await controller.connect(node, ProxyMode.global);
    await controller.setTun(true);
    expect(
        gateway.requests.map((request) => request.tun), [false, true, false]);
    expect(gateway.requests.last.node, same(node));
    expect(gateway.requests.last.runtimeSettings,
        same(gateway.requests.first.runtimeSettings));
    expect(controller.state.connected, isTrue);
    expect(controller.state.tun, isFalse);
    expect(controller.state.error, contains('已恢复原连接'));
  });

  test(
      'cancelling a pending TUN reconnect cannot revive or roll back behind the user',
      () async {
    final gateway = _Gateway();
    addTearDown(gateway.errors.close);
    final controller = SessionController(gateway, onMode: (_) {});
    addTearDown(controller.dispose);
    await controller.connect(node, ProxyMode.rule);
    gateway.connecting = Completer<ActiveConnectionSnapshot>();
    final switching = controller.setTun(true);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.phase, ConnectionPhase.starting);
    await controller.disconnect();
    gateway.connecting?.complete(active);
    await switching;
    expect(controller.state.phase, ConnectionPhase.idle);
    expect(controller.state.active, isNull);
    expect(gateway.requests.length, 2);
    expect(gateway.cancels, 1);
  });
  test('restart retains target and active mode while applying saved settings',
      () async {
    final gateway = _Gateway();
    addTearDown(gateway.errors.close);
    var runtime = const CoreRuntimeSettings();
    final controller = SessionController(gateway,
        onMode: (_) {}, runtimeSettings: () => runtime);
    addTearDown(controller.dispose);
    await controller.connect(node, ProxyMode.rule);
    expect(controller.canRestart, isTrue);
    await controller.setMode(ProxyMode.global);
    runtime = runtime.copyWith(proxyPort: 17890, logLevel: CoreLogLevel.error);
    expect(gateway.requests.single.runtimeSettings.proxyPort, 0);
    await controller.restart();
    expect(gateway.disconnects, 1);
    expect(gateway.requests.length, 2);
    expect(gateway.requests.last.node, same(node));
    expect(gateway.requests.last.target.id, node.id);
    expect(gateway.requests.last.mode, ProxyMode.global);
    expect(gateway.requests.last.runtimeSettings.proxyPort, 17890);
    expect(gateway.requests.last.runtimeSettings.logLevel, CoreLogLevel.error);
    expect(controller.state.connected, isTrue);
  });

  test('cancelled restart cannot revive a late successful session', () async {
    final gateway = _Gateway();
    addTearDown(gateway.errors.close);
    final controller = SessionController(gateway, onMode: (_) {});
    addTearDown(controller.dispose);
    await controller.connect(node, ProxyMode.rule);
    gateway.connecting = Completer<ActiveConnectionSnapshot>();
    final restarting = controller.restart();
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.phase, ConnectionPhase.starting);
    await controller.disconnect();
    gateway.connecting?.complete(active);
    await restarting;
    expect(controller.state.phase, ConnectionPhase.idle);
    expect(controller.state.active, isNull);
    expect(controller.canRestart, isFalse);
  });
  test('telemetry samples remain bounded and survive a mode change', () async {
    final gateway = _Gateway();
    addTearDown(gateway.errors.close);
    final controller = SessionController(gateway, onMode: (_) {});
    addTearDown(controller.dispose);
    await controller.connect(node, ProxyMode.rule);
    for (var i = 0; i < 75; i++) {
      await controller.refresh();
    }
    expect(controller.state.speeds.length, 60);
    expect(controller.state.latencies, [17]);
    final firstBeforeMode = controller.state.speeds.first.at;
    await controller.setMode(ProxyMode.global);
    expect(controller.state.speeds.length, 60);
    expect(controller.state.speeds.first.at.isBefore(firstBeforeMode), isFalse);
  });
  test('cancellation ignores a late successful connection and performs cleanup',
      () async {
    final gateway = _Gateway()
      ..connecting = Completer<ActiveConnectionSnapshot>();
    addTearDown(gateway.errors.close);
    final controller = SessionController(gateway, onMode: (_) {});
    addTearDown(controller.dispose);
    final connecting = controller.connect(node, ProxyMode.rule);
    expect(controller.state.phase, ConnectionPhase.starting);
    await controller.disconnect();
    expect(gateway.cancels, 1);
    expect(gateway.disconnects, 1);
    gateway.connecting?.complete(active);
    await connecting;
    expect(controller.state.phase, ConnectionPhase.idle);
    expect(controller.state.active, isNull);
  });

  test('rejected live mode keeps the confirmed selection', () async {
    final gateway = _Gateway()..rejectMode = true;
    addTearDown(gateway.errors.close);
    var mode = ProxyMode.rule;
    final controller =
        SessionController(gateway, onMode: (next) => mode = next);
    addTearDown(controller.dispose);
    await controller.connect(node, mode);
    await controller.setMode(ProxyMode.global);
    expect(mode, ProxyMode.rule);
    expect(controller.state.connected, isTrue);
    expect(controller.state.error, '核心拒绝模式');
  });

  test('statistics persistence failure cannot prevent disconnect', () async {
    final gateway = _Gateway();
    addTearDown(gateway.errors.close);
    final controller =
        SessionController(gateway, traffic: _BrokenTraffic(), onMode: (_) {});
    addTearDown(controller.dispose);
    await controller.connect(node, ProxyMode.rule);
    await controller.disconnect();
    expect(gateway.disconnects, 1);
    expect(controller.state.phase, ConnectionPhase.idle);
    expect(controller.state.error, contains('流量统计未能保存'));
  });

  test('repeated snapshots do not fabricate latency history', () async {
    final gateway = _Gateway();
    addTearDown(gateway.errors.close);
    final controller = SessionController(gateway, onMode: (_) {});
    addTearDown(controller.dispose);
    await controller.connect(node, ProxyMode.rule);
    await controller.refresh();
    await controller.refresh();
    expect(controller.state.latencies, [17]);
  });

  test(
      'late mode and capture acknowledgements cannot revive a disconnected session',
      () async {
    final gateway = _Gateway();
    addTearDown(gateway.errors.close);
    final appliedModes = <ProxyMode>[];
    final controller = SessionController(gateway, onMode: appliedModes.add);
    addTearDown(controller.dispose);
    await controller.connect(node, ProxyMode.rule);
    gateway.modeChange = Completer<void>();
    final modeChange = controller.setMode(ProxyMode.global);
    await controller.disconnect();
    gateway.modeChange?.complete();
    await modeChange;
    expect(controller.state.phase, ConnectionPhase.idle);
    expect(appliedModes, isEmpty);

    await controller.connect(node, ProxyMode.rule);
    gateway.captureChange = Completer<void>();
    final captureChange = controller.setSystemProxy(true);
    await controller.disconnect();
    gateway.captureChange?.complete();
    await captureChange;
    expect(controller.state.phase, ConnectionPhase.idle);
    expect(controller.state.systemProxy, isFalse);
    expect(controller.state.active, isNull);
  });

  test('statistics failure reports a warning and keeps live observations',
      () async {
    final gateway = _Gateway();
    addTearDown(gateway.errors.close);
    final controller =
        SessionController(gateway, traffic: _BrokenTraffic(), onMode: (_) {});
    addTearDown(controller.dispose);
    await controller.connect(node, ProxyMode.rule);
    await controller.refresh();
    expect(controller.state.connected, isTrue);
    expect(controller.state.telemetry?.downloadTotal, 200);
    expect(controller.state.error, contains('流量统计未能保存'));
  });
}
