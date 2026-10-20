import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/connection/connection_models.dart';
import '../../domain/connection/traffic_repository.dart';
import '../../domain/connection/traffic_accounting.dart';
import '../../domain/core/core_traffic.dart';
import '../../domain/core/core_gateway.dart';
import '../../domain/core/session_gateway.dart';
import '../../domain/nodes/proxy_node.dart';
import '../../domain/chains/proxy_chain.dart';
import '../../domain/routing/routing_plan.dart';
import '../routing/routing_providers.dart';
import '../core/core_providers.dart';
import 'connection_providers.dart';
import 'traffic_attribution.dart';
import '../../domain/connection/traffic_history.dart';
import '../../domain/core/runtime_settings.dart';
import '../preferences/device_settings_controller.dart';

final trafficRepositoryProvider = Provider<TrafficRepository?>((ref) => null);
final dailyTrafficProvider = StreamProvider<DailyTraffic>(
  (ref) =>
      ref.watch(trafficRepositoryProvider)?.watchToday() ??
      Stream.value(const DailyTraffic()),
);
final trafficHistoryProvider = StreamProvider<List<TrafficDay>>(
  (ref) =>
      ref.watch(trafficRepositoryProvider)?.watchHistory() ??
      Stream.value(const []),
);
final trafficArchiveProvider = StreamProvider.autoDispose
    .family<TrafficArchive, TrafficPeriod>((ref, period) {
      final repository = ref.watch(trafficRepositoryProvider);
      return repository is TrafficArchiveRepository
          ? repository.watchArchive(period)
          : Stream.value(const TrafficArchive());
    });

class SessionView {
  const SessionView({
    this.phase = ConnectionPhase.idle,
    this.active,
    this.systemProxy = false,
    this.tun = false,
    this.error = '',
    this.telemetry,
    this.latencies = const [],
    this.speeds = const [],
    this.busy = false,
  });
  final ConnectionPhase phase;
  final ActiveConnectionSnapshot? active;
  final bool systemProxy;
  final bool tun;
  final String error;
  final SessionTelemetry? telemetry;
  final List<int> latencies;
  final List<TrafficRateSample> speeds;
  final bool busy;
  bool get connected => phase == ConnectionPhase.connected;
  String get statusLabel => switch (phase) {
    ConnectionPhase.idle => '未连接',
    ConnectionPhase.starting => '正在连接…',
    ConnectionPhase.connected => '已连接',
    ConnectionPhase.stopping => '正在断开…',
    ConnectionPhase.failed => '连接异常',
  };
  bool get working =>
      busy ||
      phase == ConnectionPhase.starting ||
      phase == ConnectionPhase.stopping;
}

final sessionControllerProvider =
    StateNotifierProvider<SessionController, SessionView>(
      (ref) => SessionController(
        ref.watch(coreGatewayProvider),
        requiresTun: ref.watch(requiredTunnelProvider),
        initialSystemProxy:
            ref.read(initialDeviceSettingsProvider).connection.systemProxy,
        initialTun: ref.read(initialDeviceSettingsProvider).connection.tun,
        routing: ref.watch(routingResolverProvider),
        traffic: ref.watch(trafficRepositoryProvider),
        runtimeSettings:
            () => ref.read(deviceSettingsControllerProvider).runtime,
        serviceBusy: () => ref.read(coreServiceBusyProvider),
        updateHold: () => ref.read(connectionUpdateHoldProvider),
        onMode: (mode) => ref.read(proxyModeProvider.notifier).state = mode,
      ),
    );

class SessionController extends StateNotifier<SessionView> {
  SessionController(
    this.gateway, {
    this.traffic,
    this.routing,
    this.runtimeSettings,
    this.serviceBusy,
    this.updateHold,
    required this.onMode,
    this.requiresTun = false,
    bool initialTun = false,
    bool initialSystemProxy = false,
  }) : super(
         SessionView(
           systemProxy: requiresTun ? false : initialSystemProxy,
           tun: requiresTun || initialTun,
           busy: requiresTun,
         ),
       ) {
    final interactive = gateway;
    if (interactive is SessionGateway) {
      _failures = interactive.failures.listen((error) {
        if (!mounted) return;
        ++_generation;
        _timer?.cancel();
        state = SessionView(
          phase: ConnectionPhase.failed,
          systemProxy: state.systemProxy,
          tun: state.tun,
          error: error.toString(),
        );
      });
      if (requiresTun) _initialized = _restoreSession(interactive);
    }
  }
  final bool requiresTun;
  final bool Function()? serviceBusy;
  final bool Function()? updateHold;
  Future<void> _initialized = Future<void>.value();
  Future<void> get initialized => _initialized;

  Future<void> _restoreSession(SessionGateway interactive) async {
    final generation = _generation;
    try {
      final recovered =
          interactive is SessionRecoveryGateway
              ? await (interactive as SessionRecoveryGateway).recoverSession()
              : RecoveredSession(await interactive.observe(), null);
      final observation = recovered.observation;
      if (!mounted || generation != _generation) return;
      final active = observation.active;
      if (active != null && (!observation.tun || observation.systemProxy)) {
        await interactive.disconnect();
        throw const CoreGatewayException('invalid_capture', '后台服务的接管状态无效，已断开');
      }
      if (active != null) {
        _lastRequest = recovered.request;
        _attribution.start(active);
        onMode(active.mode);
      }
      state = SessionView(
        phase: observation.phase,
        active: active,
        tun: active == null ? requiresTun : observation.tun,
        systemProxy: observation.systemProxy,
        telemetry: observation.telemetry,
        error: observation.error,
      );
      setObserving(_observing);
    } on Exception catch (error) {
      if (mounted && generation == _generation) {
        state = SessionView(
          phase: ConnectionPhase.failed,
          tun: requiresTun,
          error: error.toString(),
        );
      }
    }
  }

  final CoreGateway gateway;
  final TrafficRepository? traffic;
  final RoutingResolver? routing;
  final CoreRuntimeSettings Function()? runtimeSettings;
  final void Function(ProxyMode) onMode;
  final _attribution = SessionTrafficAttribution();
  StreamSubscription<Exception>? _failures;
  Timer? _timer;
  bool _observing = false;
  bool _sampling = false;
  int _generation = 0;
  int get operationRevision => _generation;
  int _lastLatencyAt = 0;
  DateTime _lastProbe = DateTime.now();
  ConnectRequest? _lastRequest;
  bool get canRestart => state.connected && _lastRequest != null;
  CoreRuntimeSettings? get appliedRuntimeSettings =>
      state.connected ? _lastRequest?.runtimeSettings : null;

  void setObserving(bool observing) {
    _observing = observing;
    _timer?.cancel();
    if (observing && state.connected) {
      unawaited(refresh());
      _timer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(refresh()),
      );
    }
  }

  Future<void> connect(ProxyNode node, ProxyMode mode) async {
    await _connect(node, null, mode);
  }

  Future<void> connectChain(ProxyChain chain, ProxyMode mode) =>
      _connect(null, chain, mode);

  Future<void> _connect(
    ProxyNode? node,
    ProxyChain? chain,
    ProxyMode mode,
  ) async {
    if (state.working || state.connected || state.active != null) return;
    if (updateHold?.call() ?? false) {
      state = SessionView(
        systemProxy: state.systemProxy,
        tun: state.tun,
        error: '正在准备应用更新，请完成或取消安装后连接',
      );
      return;
    }
    if (serviceBusy?.call() ?? false) {
      state = SessionView(
        systemProxy: state.systemProxy,
        tun: state.tun,
        error: '权限服务正在更新，请等待操作完成后连接',
      );
      return;
    }
    final generation = ++_generation;
    final capture = state.systemProxy;
    final tun = state.tun;
    final runtime = runtimeSettings?.call() ?? const CoreRuntimeSettings();
    _lastLatencyAt = 0;
    _lastProbe = DateTime.now();
    state = SessionView(
      phase: ConnectionPhase.starting,
      systemProxy: capture,
      tun: tun,
    );
    try {
      final plan = await routing?.resolve(node, chain: chain);
      if (!mounted || generation != _generation) return;
      if (chain != null && plan?.primaryChain == null) {
        throw const ChainException('代理链连接尚未接入');
      }
      final request = ConnectRequest(
        target: ProxyTarget(
          id: chain?.id ?? node!.id,
          name: chain?.name ?? node!.name,
          revision: chain?.revision ?? node!.revision,
          kind: chain == null ? 'node' : 'chain',
        ),
        mode: mode,
        node: node,
        chain: plan?.primaryChain,
        routing: plan,
        runtimeSettings: runtime,
        tun: tun,
        systemProxy: capture,
      );
      await _establish(request, generation);
    } on Exception catch (error) {
      if (mounted && generation == _generation) {
        state = SessionView(
          phase: ConnectionPhase.failed,
          error: error.toString(),
          tun: tun,
          systemProxy: capture,
        );
      }
    }
  }

  Future<void> _establish(ConnectRequest request, int generation) async {
    final active = await gateway.connect(request);
    if (!mounted || generation != _generation) return;
    _lastRequest = request;
    _attribution.start(active);
    state = SessionView(
      phase: ConnectionPhase.connected,
      active: active,
      tun: request.tun,
      systemProxy: request.systemProxy,
    );
    setObserving(_observing);
  }

  /// Retains the active target/rule snapshot even if selection changed meanwhile.
  Future<void> restart() async {
    await _restart();
  }

  /// Applies a validated settings snapshot while retaining the actual active
  /// target, mode, rules and capture. Failure restores the preceding session.
  Future<void> applyRuntime(CoreRuntimeSettings settings) async {
    if (!await _restart(runtime: settings)) {
      throw SettingsException(
        state.error.isEmpty ? '配置应用已取消或连接状态已变化' : state.error,
      );
    }
  }

  Future<void> setTun(bool enabled) async {
    if (requiresTun && !enabled) return;
    if (state.working || state.tun == enabled) return;
    if (!state.connected) {
      if (state.active != null) return;
      state = SessionView(
        phase: state.phase,
        systemProxy: state.systemProxy,
        tun: enabled,
        error: state.error,
      );
      return;
    }
    await _restart(tun: enabled);
  }

  Future<bool> _restart({bool? tun, CoreRuntimeSettings? runtime}) async {
    if (updateHold?.call() ?? false) return false;
    final original = _lastRequest;
    final active = state.active;
    if (original == null ||
        active == null ||
        !state.connected ||
        state.working) {
      return false;
    }
    final capture = state.systemProxy;
    final previousTun = state.tun;
    final requestedTun = tun ?? previousTun;
    final stopGeneration = _generation + 1;
    await disconnect();
    if (!mounted ||
        _generation != stopGeneration ||
        state.phase != ConnectionPhase.idle) {
      return false;
    }
    final generation = ++_generation;
    _lastLatencyAt = 0;
    _lastProbe = DateTime.now();
    state = SessionView(
      phase: ConnectionPhase.starting,
      systemProxy: capture,
      tun: requestedTun,
    );
    try {
      await _establish(
        ConnectRequest(
          target: original.target,
          mode: active.mode,
          node: original.node,
          chain: original.chain,
          routing: original.routing,
          systemProxy: capture,
          tun: requestedTun,
          runtimeSettings:
              runtime ??
              (tun == null
                  ? runtimeSettings?.call() ?? original.runtimeSettings
                  : original.runtimeSettings),
        ),
        generation,
      );
      return mounted && generation == _generation && state.connected;
    } on Exception catch (error) {
      if (mounted && generation == _generation) {
        final action = tun != null ? 'TUN 修改' : '配置应用';
        try {
          await _establish(
            ConnectRequest(
              target: original.target,
              mode: active.mode,
              node: original.node,
              chain: original.chain,
              routing: original.routing,
              runtimeSettings: original.runtimeSettings,
              systemProxy: capture,
              tun: previousTun,
            ),
            generation,
          );
          if (mounted && generation == _generation) {
            state = SessionView(
              phase: ConnectionPhase.connected,
              active: state.active,
              systemProxy: capture,
              tun: previousTun,
              error: '$action未完成，已恢复原连接：$error',
            );
          }
          return false;
        } on Exception catch (rollbackError) {
          if (!mounted || generation != _generation) return false;
          state = SessionView(
            phase: ConnectionPhase.failed,
            systemProxy: capture,
            tun: previousTun,
            error: '$action失败，原连接也未能恢复：$rollbackError',
          );
          return false;
        }
      }
      return false;
    }
  }

  Future<void> disconnect() async {
    final generation = ++_generation;
    _timer?.cancel();
    final previous = state;
    state = SessionView(
      phase: ConnectionPhase.stopping,
      active: previous.active,
      tun: previous.tun,
      systemProxy: previous.systemProxy,
    );
    try {
      if (previous.phase == ConnectionPhase.starting &&
          gateway is SessionGateway) {
        await (gateway as SessionGateway).cancel();
      }
      String warning = '';
      try {
        await _sampleFinal();
      } on Exception {
        warning = '连接已断开，最后一段流量统计未能保存';
      }
      await gateway.disconnect();
      if (mounted && generation == _generation) {
        state = SessionView(
          systemProxy: previous.systemProxy,
          tun: previous.tun,
          error: warning,
        );
      }
    } on Exception catch (error) {
      if (mounted && generation == _generation) {
        state = SessionView(
          phase: ConnectionPhase.failed,
          active: previous.active,
          tun: previous.tun,
          error: error.toString(),
          systemProxy: previous.systemProxy,
        );
      }
    }
  }

  Future<void> _sampleFinal() async {
    final interactive = gateway;
    if (interactive is! SessionGateway || state.active == null) return;
    final observation = await interactive.observe();
    final data = observation.telemetry;
    final active = observation.active;
    if (active != null) await _recordTraffic(active, data);
  }

  Future<void> _recordTraffic(
    ActiveConnectionSnapshot active,
    SessionTelemetry? data,
  ) async {
    final repository = traffic;
    if (repository == null) return;
    final source = gateway;
    if (repository is TrafficAccountingRepository &&
        source is CoreTrafficGateway) {
      final sample = await source.traffic(sessionId: active.sessionId);
      if (sample.sessionId != active.sessionId) {
        throw const CoreGatewayException('session_changed', '连接会话已改变，请刷新');
      }
      await repository.recordAccounting(sample);
    } else if (data != null) {
      await repository.record(
        active.sessionId,
        data.uploadTotal,
        data.downloadTotal,
        attribution: _attribution.resolve(active),
      );
    }
  }

  Future<void> refresh() async {
    final interactive = gateway;
    if (interactive is! SessionGateway || !state.connected || _sampling) return;
    _sampling = true;
    final generation = _generation;
    try {
      final observation = await interactive.observe();
      if (!mounted || generation != _generation || state.working) return;
      final data = observation.telemetry;
      final active = observation.active;
      var warning = '';
      if (active != null) {
        try {
          await _recordTraffic(active, data);
        } on Exception {
          warning = '流量统计未能保存，连接仍可使用';
        }
      }
      if (!mounted || generation != _generation) return;
      final latency = data?.latency;
      final samples = [...state.latencies];
      if (latency != null && data != null && data.latencyAt != _lastLatencyAt) {
        samples.add(latency);
        _lastLatencyAt = data.latencyAt;
      }
      if (samples.length > 30) samples.removeAt(0);
      final speeds = [...state.speeds];
      if (data != null) {
        speeds.add(
          TrafficRateSample(
            at: DateTime.now(),
            upload: data.upload,
            download: data.download,
          ),
        );
        if (speeds.length > 60) speeds.removeAt(0);
      }
      state = SessionView(
        phase: observation.phase,
        active: active,
        systemProxy:
            active == null ? state.systemProxy : observation.systemProxy,
        tun: active == null ? state.tun : observation.tun,
        telemetry: data,
        error: observation.error.isEmpty ? warning : observation.error,
        latencies: samples,
        speeds: List.unmodifiable(speeds),
      );
      if (!state.connected) _timer?.cancel();
      if (state.connected &&
          DateTime.now().difference(_lastProbe) >=
              const Duration(seconds: 30)) {
        _lastProbe = DateTime.now();
        await interactive.probe();
      }
    } on Exception catch (error) {
      if (mounted && generation == _generation) {
        state = SessionView(
          phase: ConnectionPhase.failed,
          active: state.active,
          systemProxy: state.systemProxy,
          tun: state.tun,
          error: error.toString(),
        );
      }
      _timer?.cancel();
    } finally {
      _sampling = false;
    }
  }

  Future<void> setMode(ProxyMode mode) async {
    if (state.working) return;
    if (!state.connected) {
      onMode(mode);
      return;
    }
    final interactive = gateway;
    if (interactive is! SessionGateway) return;
    final previous = state;
    final generation = _generation;
    if (mode != previous.active?.mode) _attribution.invalidate();
    state = SessionView(
      phase: previous.phase,
      active: previous.active,
      systemProxy: previous.systemProxy,
      tun: previous.tun,
      telemetry: previous.telemetry,
      latencies: previous.latencies,
      speeds: previous.speeds,
      busy: true,
    );
    try {
      await interactive.setMode(mode);
      if (!mounted || generation != _generation) return;
      onMode(mode);
      state = previous;
      await refresh();
    } on Exception catch (error) {
      if (mounted && generation == _generation) {
        state = SessionView(
          phase: previous.phase,
          active: previous.active,
          systemProxy: previous.systemProxy,
          tun: previous.tun,
          telemetry: previous.telemetry,
          latencies: previous.latencies,
          speeds: previous.speeds,
          error: error.toString(),
        );
      }
    }
  }

  Future<void> setSystemProxy(bool enabled) async {
    if (requiresTun) return;
    if (state.working) return;
    final previous = state;
    final generation = _generation;
    if (!state.connected) {
      if (state.active != null) return;
      state = SessionView(
        phase: state.phase,
        active: state.active,
        systemProxy: enabled,
        tun: state.tun,
        error: state.error,
      );
      return;
    }
    final interactive = gateway;
    if (interactive is! SessionGateway) return;
    state = SessionView(
      phase: previous.phase,
      active: previous.active,
      systemProxy: previous.systemProxy,
      tun: previous.tun,
      telemetry: previous.telemetry,
      latencies: previous.latencies,
      speeds: previous.speeds,
      busy: true,
    );
    try {
      await interactive.setSystemProxy(enabled);
      if (mounted && generation == _generation) {
        state = SessionView(
          phase: previous.phase,
          active: previous.active,
          systemProxy: enabled,
          tun: previous.tun,
          telemetry: previous.telemetry,
          latencies: previous.latencies,
          speeds: previous.speeds,
        );
      }
    } on Exception catch (error) {
      if (mounted && generation == _generation) {
        state = SessionView(
          phase: previous.phase,
          active: previous.active,
          systemProxy: previous.systemProxy,
          tun: previous.tun,
          telemetry: previous.telemetry,
          latencies: previous.latencies,
          speeds: previous.speeds,
          error: error.toString(),
        );
      }
    }
  }

  Future<void> probe() async {
    final interactive = gateway;
    if (interactive is! SessionGateway || !state.connected) return;
    final generation = _generation;
    try {
      await interactive.probe();
    } on Exception catch (error) {
      if (mounted && generation == _generation) {
        state = SessionView(
          phase: state.phase,
          active: state.active,
          systemProxy: state.systemProxy,
          tun: state.tun,
          telemetry: state.telemetry,
          latencies: state.latencies,
          speeds: state.speeds,
          error: error.toString(),
        );
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    _timer?.cancel();
    unawaited(_failures?.cancel());
    super.dispose();
  }
}
