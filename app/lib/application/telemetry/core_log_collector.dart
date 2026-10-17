import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/core/core_telemetry.dart';
import '../../domain/core/core_gateway.dart';
import '../core/core_providers.dart';

final coreLogRepositoryProvider = Provider<CoreLogRepository?>((ref) => null);
final coreLogsProvider = StreamProvider<List<CoreLogEntry>>((ref) =>
    ref.watch(coreLogRepositoryProvider)?.watch() ?? Stream.value(const []));
final coreLogCollectorProvider =
    StateNotifierProvider<CoreLogCollector, LogCollectionState>((ref) {
  final gateway = ref.watch(coreGatewayProvider);
  return CoreLogCollector(
      gateway is CoreTelemetryGateway ? gateway as CoreTelemetryGateway : null,
      ref.watch(coreLogRepositoryProvider));
});

class LogCollectionState {
  const LogCollectionState({this.error = '', this.dropped = false});
  final String error;
  final bool dropped;
}

/// Collection outlives the log page. Pausing its view never discards core events.
class CoreLogCollector extends StateNotifier<LogCollectionState> {
  CoreLogCollector(this.gateway, this.repository)
      : super(const LogCollectionState());
  final CoreTelemetryGateway? gateway;
  final CoreLogRepository? repository;
  Timer? _timer;
  String _stream = '';
  int _cursor = 0;
  Future<void> _operations = Future.value();
  bool _polling = false;
  bool _running = false;
  DateTime? _lastPrune;

  void resume() {
    if (_running || gateway == null || repository == null) return;
    _running = true;
    unawaited(collect());
    _timer =
        Timer.periodic(const Duration(seconds: 2), (_) => unawaited(collect()));
  }

  void pause() {
    _running = false;
    _timer?.cancel();
  }

  Future<void> suspend() async {
    pause();
    await _operations;
  }

  Future<void> _serial(Future<void> Function() action) {
    final next = _operations.then((_) => action());
    // Errors remain visible to the originating caller; don't poison the queue.
    _operations = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> collect() async {
    if (_polling || !mounted) return;
    _polling = true;
    try {
      await _serial(() async {
        final source = gateway;
        final store = repository;
        if (source == null || store == null || !mounted) return;
        final now = DateTime.now();
        final previousPrune = _lastPrune;
        if (previousPrune == null ||
            now.difference(previousPrune) >= const Duration(hours: 1)) {
          await store.prune();
          _lastPrune = now;
        }
        for (var page = 0; page < 10; page++) {
          if (!mounted) return;
          final batch = await source.logs(stream: _stream, after: _cursor);
          if (!mounted) return;
          if (batch.stream == _stream && batch.cursor < _cursor) {
            throw const CoreGatewayException(
                'invalid_response', '核心日志游标无效，请重新启动应用');
          }
          if (batch.entries.isNotEmpty) await store.append(batch.entries);
          _stream = batch.stream;
          _cursor = batch.cursor;
          if (mounted &&
              (state.error.isNotEmpty || batch.dropped && !state.dropped)) {
            state = LogCollectionState(dropped: state.dropped || batch.dropped);
          }
          if (!batch.more) break;
        }
      });
    } on Exception catch (error) {
      if (mounted) {
        state =
            LogCollectionState(error: error.toString(), dropped: state.dropped);
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> clear() => _serial(() async {
        final source = gateway;
        final store = repository;
        if (source == null || store == null) {
          throw const FormatException('当前平台尚不能清空核心日志');
        }
        final checkpoint = await source.clearLogs();
        await store.clear();
        _stream = checkpoint.stream;
        _cursor = checkpoint.cursor;
        if (mounted) state = const LogCollectionState();
      });

  @override
  void dispose() {
    pause();
    super.dispose();
  }
}
