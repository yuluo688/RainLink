import 'dart:async';

import 'package:rainlink/domain/platform/desktop_integration.dart';
import 'package:rainlink/domain/core/runtime_settings.dart';

class FakeDesktopIntegration implements DesktopIntegration {
  @override
  Future<bool> canNotifySubscriptionExpiry() async {
    final status = await inspect();
    return status.notificationsAvailable &&
        (!status.notificationsRequireTray || status.trayVisible);
  }

  final events = StreamController<DesktopAction>.broadcast();
  final trayChanges = <bool>[];
  final notices = <String>[];
  final expiryNotices = <({int expiringSoon, int expired})>[];
  Future<DesktopIntegrationStatus> Function()? onInspect;
  Future<void> Function(int, int)? onExpiry;
  bool launch = false;
  bool tray = false;
  bool visible = true;
  bool rejectTray = false;
  bool rejectLaunch = false;
  bool closeCalled = false;
  @override
  Stream<DesktopAction> get actions => events.stream;
  @override
  Future<DesktopIntegrationStatus> inspect() async {
    if (onInspect case final inspect?) return inspect();
    return DesktopIntegrationStatus(launchAtLogin: launch, trayVisible: tray);
  }

  @override
  Future<void> setLaunchAtLogin(bool enabled) async {
    if (!rejectLaunch) launch = enabled;
  }

  @override
  Future<void> setTrayVisible(bool enabled) async {
    if (rejectTray) throw const SettingsException('托盘接口拒绝');
    trayChanges.add(enabled);
    tray = enabled;
  }

  @override
  Future<void> updateTray({
    required String label,
    required String actionLabel,
    required bool busy,
  }) async {}
  @override
  Future<void> showWindow() async {
    visible = true;
  }

  @override
  Future<void> hideWindow() async {
    if (!tray) throw const SettingsException('托盘尚未就绪');
    visible = false;
  }

  @override
  Future<void> notifyConnection(String message) async {
    notices.add(message);
  }

  @override
  Future<void> notifySubscriptionExpiry({
    required int expiringSoon,
    required int expired,
  }) async {
    await onExpiry?.call(expiringSoon, expired);
    expiryNotices.add((expiringSoon: expiringSoon, expired: expired));
  }

  @override
  Future<void> close() async {
    closeCalled = true;
    tray = false;
  }

  Future<void> dispose() => events.close();
}
