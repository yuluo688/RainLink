import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/core/core_telemetry.dart';
import '../connection/session_controller.dart';
import '../core/core_providers.dart';

class ConnectionsView {
  const ConnectionsView({
    this.snapshot,
    this.recent,
    this.error = '',
    this.loading = false,
    this.paused = false,
    this.closing = false,
  });
  final ConnectionsSnapshot? snapshot;

  /// Most recently started connection observed in this session, in memory only.
  final CoreConnection? recent;
  final String error;
  final bool loading;
  final bool paused;
  final bool closing;
}

final connectionsControllerProvider = StateNotifierProvider.autoDispose<
  ConnectionsController,
  ConnectionsView
>((ref) {
  final gateway = ref.watch(coreGatewayProvider);
  final controller = ConnectionsController(
    gateway is CoreTelemetryGateway ? gateway as CoreTelemetryGateway : null,
  );
  ref.listen(
    sessionControllerProvider.select(
      (state) => state.connected ? state.active?.sessionId : null,
    ),
    (_, session) => controller.setSession(session),
    fireImmediately: true,
  );
  return controller;
});

class ConnectionsController extends StateNotifier<ConnectionsView> {
  ConnectionsController(this.gateway) : super(const ConnectionsView());
  final CoreTelemetryGateway? gateway;
  Timer? _timer;
  String? _session;
  int _generation = 0;
  bool _foreground = true;
  Future<void>? _refreshing;

  void setSession(String? session) {
    if (_session == session) return;
    ++_generation;
    _session = session;
    _timer?.cancel();
    state = ConnectionsView(error: gateway == null ? '当前平台尚不能读取核心连接' : '');
    if (session != null) {
      unawaited(refresh());
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (_foreground && _session != null && !state.paused && gateway != null) {
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(refresh()),
      );
    }
  }

  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    _schedule();
    if (foreground && !state.paused) unawaited(refresh());
  }

  void togglePaused() {
    state = ConnectionsView(
      snapshot: state.snapshot,
      recent: state.recent,
      paused: !state.paused,
      error: state.error,
      closing: state.closing,
    );
    _schedule();
    if (!state.paused) unawaited(refresh());
  }

  Future<void> refresh() =>
      _refreshing ??= _refresh().whenComplete(() {
        _refreshing = null;
        // A session change while awaiting a request must not suppress the new read.
        if (mounted &&
            _foreground &&
            _session != null &&
            !state.paused &&
            !state.closing &&
            state.snapshot?.sessionId != _session &&
            state.error.isEmpty) {
          scheduleMicrotask(() {
            if (mounted) unawaited(refresh());
          });
        }
      });

  Future<void> _refresh() async {
    final source = gateway;
    final session = _session;
    if (source == null ||
        session == null ||
        state.paused ||
        !_foreground ||
        state.closing) {
      return;
    }
    final generation = _generation;
    state = ConnectionsView(
      snapshot: state.snapshot,
      recent: state.recent,
      loading: state.snapshot == null,
      closing: state.closing,
    );
    try {
      final snapshot = await source.connections(sessionId: session);
      if (!mounted || generation != _generation || state.paused) return;
      state = ConnectionsView(
        snapshot: snapshot,
        recent: _mostRecent(snapshot),
        closing: state.closing,
      );
    } on Exception catch (error) {
      if (mounted && generation == _generation) {
        state = ConnectionsView(
          snapshot: state.snapshot,
          recent: state.recent,
          error: error.toString(),
          paused: state.paused,
          closing: state.closing,
        );
      }
    }
  }

  Future<void> closeConnection([String? id]) async {
    final source = gateway;
    final snapshot = state.snapshot;
    if (source == null ||
        snapshot == null ||
        state.closing ||
        _session == null) {
      return;
    }
    final generation = ++_generation;
    state = ConnectionsView(
      snapshot: snapshot,
      recent: state.recent,
      paused: state.paused,
      closing: true,
    );
    try {
      await source.closeConnections(
        sessionId: snapshot.sessionId,
        connectionId: id,
      );
      if (!mounted || generation != _generation) return;
      // Closing is an explicit action, including while the view is paused.
      final refreshed = await source.connections(sessionId: snapshot.sessionId);
      if (!mounted || generation != _generation) return;
      state = ConnectionsView(
        snapshot: refreshed,
        recent: _mostRecent(refreshed),
        paused: state.paused,
      );
    } on Exception catch (error) {
      if (mounted && generation == _generation) {
        state = ConnectionsView(
          snapshot: state.snapshot,
          recent: state.recent,
          error: error.toString(),
          paused: state.paused,
        );
      }
    }
  }

  CoreConnection? _mostRecent(ConnectionsSnapshot snapshot) {
    var recent = state.recent;
    for (final entry in snapshot.entries) {
      final previous = recent;
      if (previous == null ||
          entry.startedAt.isAfter(previous.startedAt) ||
          entry.startedAt.isAtSameMomentAs(previous.startedAt) &&
              entry.id.compareTo(previous.id) >= 0) {
        recent = entry;
      }
    }
    return recent;
  }

  @override
  void dispose() {
    ++_generation;
    _timer?.cancel();
    super.dispose();
  }
}
