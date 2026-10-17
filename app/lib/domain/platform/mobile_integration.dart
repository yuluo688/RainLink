import 'app_notifications.dart';

enum MobileAction { overview, groups }

class MobileNotificationStatus {
  const MobileNotificationStatus({
    required this.allowed,
    required this.connectionAllowed,
    required this.expiryAllowed,
  });
  final bool allowed;
  final bool connectionAllowed;
  final bool expiryAllowed;
}

abstract interface class MobileIntegration implements AppNotifications {
  Stream<MobileAction> get actions;
  Future<MobileNotificationStatus> inspectNotifications();
  Future<MobileNotificationStatus> requestNotifications();
  Future<void> openNotificationSettings();
  Future<void> configureNotifications(
      {required bool connection, required bool subscriptionExpiry});
  void dispose();
}
