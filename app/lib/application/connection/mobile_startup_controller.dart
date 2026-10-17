import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/connection/connection_models.dart';
import '../updates/app_update_controller.dart';
import '../preferences/device_settings_controller.dart';
import '../preferences/mobile_integration_controller.dart';
import '../preferences/desktop_integration_controller.dart';
import 'connect_selected.dart';
import 'session_controller.dart';

final mobileStartupControllerProvider =
    Provider<MobileStartupController>((ref) {
  final controller = MobileStartupController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

/// Runs once per UI process, after native session recovery. Resuming the app or
/// returning from a permission dialog never reconnects a manually stopped core.
class MobileStartupController {
  MobileStartupController(this._ref);
  final Ref _ref;
  bool _started = false;
  bool _disposed = false;

  Future<void> start({required bool Function() isForeground}) async {
    if (_started || _disposed) return;
    _started = true;
    final mobile = _ref.read(mobileIntegrationProvider);
    if (mobile == null) return;
    final session = _ref.read(sessionControllerProvider.notifier);
    final revision = session.operationRevision;
    await _ref.read(startupReadyProvider);
    if (_disposed) return;
    try {
      await _ref
          .read(deviceSettingsControllerProvider.notifier)
          .synchronizeMobileNotifications();
    } on Exception {
      if (!_disposed) {
        _ref.read(desktopIntegrationNoticeProvider.notifier).state =
            '系统通知偏好同步失败，请在通用设置中检查；连接操作仍可继续';
      }
    }
    await session.initialized;
    if (_disposed ||
        !isForeground() ||
        revision != session.operationRevision ||
        _ref.read(sessionControllerProvider).phase != ConnectionPhase.idle ||
        _ref.read(sessionControllerProvider).working ||
        !_ref.read(deviceSettingsControllerProvider).general.autoConnect) {
      return;
    }
    await _ref.read(connectSelectedProvider)(
        cancelled: () =>
            _disposed ||
            !isForeground() ||
            !_ref.read(deviceSettingsControllerProvider).general.autoConnect);
  }

  void dispose() => _disposed = true;
}
