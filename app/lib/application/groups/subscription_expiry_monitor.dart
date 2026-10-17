import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/core/runtime_settings.dart';
import '../../domain/groups/node_group.dart';
import '../../domain/groups/subscription_expiry.dart';
import '../../domain/platform/app_notifications.dart';

final subscriptionExpiryMonitorProvider =
    Provider<SubscriptionExpiryMonitor?>((ref) => null);
final subscriptionExpiryErrorProvider = StateProvider<String?>((ref) => null);

/// Observes local expiry metadata; it never fetches subscription URLs or stops a
/// live connection. Delivery is serialized and receipts survive normal restart.
class SubscriptionExpiryMonitor {
  SubscriptionExpiryMonitor({
    required this.groups,
    required this.store,
    required this.notifications,
    required this.enabled,
    required this.onError,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final GroupRepository groups;
  final SubscriptionExpiryStore store;
  final AppNotifications notifications;
  final bool Function() enabled;
  final void Function(String?) onError;
  final DateTime Function() _now;
  StreamSubscription<List<NodeGroup>>? _subscription;
  Timer? _timer;
  List<NodeGroup>? _groups;
  Set<String> _validGroupIds = {};
  List<SubscriptionExpiryAlert> _accepted = [];
  Future<void>? _running;
  Future<void>? _closing;
  Future<void> _cancelSubscription = Future.value();
  bool _active = false;
  bool _disposed = false;
  bool _requested = false;
  int _generation = 0;
  String? _lastError;

  void resume() {
    if (_active || _disposed || _closing != null) return;
    _active = true;
    final generation = ++_generation;
    _subscription = groups.watchGroups().listen((values) {
      if (!_current(generation)) return;
      _groups = List.unmodifiable(values);
      _validGroupIds = {
        for (final group in values)
          if (group.kind == GroupKind.subscription) group.id,
      };
      unawaited(checkNow());
    }, onError: (Object error, StackTrace stack) {
      if (!_current(generation)) return;
      _groups = null;
      _error('无法读取订阅信息，请稍后重试提醒');
    });
    _timer = Timer.periodic(
        const Duration(minutes: 1), (_) => unawaited(checkNow()));
  }

  bool _current(int generation) =>
      !_disposed && _closing == null && _active && _generation == generation;

  Future<void> checkNow() {
    if (!_active || _disposed || _closing != null) return Future.value();
    if (_groups == null) {
      // A stream error is recoverable without restarting the application.
      pause();
      resume();
      return Future.value();
    }
    _requested = true;
    if (_running case final running?) return running;
    final completed = Completer<void>();
    _running = completed.future;
    unawaited(_drain(completed));
    return completed.future;
  }

  Future<void> _drain(Completer<void> completed) async {
    try {
      do {
        _requested = false;
        try {
          await _check(_generation);
          _error(null);
        } on SettingsException catch (error) {
          _error(error.message);
        } on Exception {
          _error('订阅到期提醒未完成，请稍后重试');
        }
      } while (_requested && _active && !_disposed);
    } finally {
      _running = null;
      completed.complete();
    }
  }

  Future<void> _check(int generation) async {
    // An accepted notification must not repeat if the subsequent disk write
    // fails. Retry the receipt before considering any further delivery.
    await _saveAccepted();
    if (!_current(generation) || !enabled()) return;
    final Map<String, SubscriptionExpiryAlert> receipts;
    try {
      receipts = await store.load();
      await store.record(const [], validGroupIds: _validGroupIds);
    } on Exception {
      throw const SettingsException('无法读取或保存订阅提醒记录，请检查本地存储后重试');
    }
    if (!_current(generation) || !enabled()) return;
    List<SubscriptionExpiryAlert> pending() =>
        pendingSubscriptionExpiryAlerts(_groups ?? const [], receipts, _now());
    if (pending().isEmpty) return;
    final bool allowed;
    try {
      allowed = await notifications.canNotifySubscriptionExpiry();
    } on Exception {
      throw const SettingsException('无法检查系统通知，请稍后重试');
    }
    if (!_current(generation) || !enabled()) return;
    // Re-evaluate after the native await: disabling reminders, renewal or
    // deletion while checking the tray must not send a stale notification.
    final alerts = pending();
    if (alerts.isEmpty) return;
    if (!allowed) {
      throw const SettingsException('系统通知尚未就绪，请检查通知权限和通知设置后重试');
    }
    try {
      await notifications.notifySubscriptionExpiry(
          expiringSoon: alerts
              .where((alert) => alert.stage == SubscriptionExpiryStage.soon)
              .length,
          expired: alerts
              .where((alert) => alert.stage == SubscriptionExpiryStage.expired)
              .length);
    } on Exception {
      throw const SettingsException('系统未接收订阅到期提醒，请稍后重试');
    }
    _accepted = alerts;
    await _saveAccepted();
  }

  Future<void> _saveAccepted() async {
    if (_accepted.isEmpty) return;
    try {
      await store.record(_accepted, validGroupIds: _validGroupIds);
      _accepted = [];
    } on Exception {
      throw const SettingsException('提醒已提交，但记录未保存；请检查本地存储后重试');
    }
  }

  void _error(String? message) {
    if (_disposed || _lastError == message) return;
    _lastError = message;
    onError(message);
  }

  void pause() {
    _active = false;
    ++_generation;
    _timer?.cancel();
    _timer = null;
    final subscription = _subscription;
    _subscription = null;
    _groups = null;
    if (subscription != null) {
      final cancelling =
          subscription.cancel().catchError((Object error, StackTrace stack) {
        _error('订阅提醒监听未能正常结束');
      });
      _cancelSubscription =
          Future.wait([_cancelSubscription, cancelling]).then<void>((_) {});
    }
  }

  /// Wait for a native operation already dispatched and its receipt. A receipt
  /// failure is reported, but must not prevent a normal network-safe exit.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    await suspend();
    _disposed = true;
  }

  /// Stop background work without disposing it if an exit is later refused.
  Future<void> suspend() async {
    pause();
    await _cancelSubscription;
    await _running;
    try {
      await _saveAccepted();
    } on SettingsException catch (error) {
      _error(error.message);
    }
  }

  void dispose() {
    pause();
    _disposed = true;
  }
}
