import 'app_notifications.dart';

enum DesktopAction {
  show,
  showGroups,
  toggleConnection,
  quit,
  capabilitiesChanged,
}

class DesktopIntegrationStatus {
  const DesktopIntegrationStatus({
    required this.launchAtLogin,
    required this.trayVisible,
    this.trayAvailable = true,
    this.notificationsAvailable = true,
    this.notificationsRequireTray = true,
  });
  final bool launchAtLogin;
  final bool trayVisible;
  final bool trayAvailable;
  final bool notificationsAvailable;
  final bool notificationsRequireTray;
}

abstract interface class DesktopIntegration implements AppNotifications {
  Stream<DesktopAction> get actions;
  Future<DesktopIntegrationStatus> inspect();
  Future<void> setLaunchAtLogin(bool enabled);
  Future<void> setTrayVisible(bool visible);
  Future<void> updateTray({
    required String label,
    required String actionLabel,
    required bool busy,
  });
  Future<void> showWindow();
  Future<void> hideWindow();
  Future<void> notifyConnection(String message);
  Future<void> close();
}
