import 'dart:async';
import 'package:rainlink/domain/platform/mobile_integration.dart';

class FakeMobileIntegration implements MobileIntegration {
  final events = StreamController<MobileAction>.broadcast();
  final configurations = <({bool connection, bool expiry})>[];
  MobileNotificationStatus status = const MobileNotificationStatus(
      allowed: true, connectionAllowed: true, expiryAllowed: true);
  Future<void> Function(bool, bool)? onConfigure;
  int requests = 0;
  int openedSettings = 0;
  bool connection = false;
  bool expiry = false;
  bool _disposed = false;
  @override
  Stream<MobileAction> get actions => events.stream;
  @override
  Future<MobileNotificationStatus> inspectNotifications() async => status;
  @override
  Future<MobileNotificationStatus> requestNotifications() async {
    requests++;
    return status;
  }

  @override
  Future<void> configureNotifications(
      {required bool connection, required bool subscriptionExpiry}) async {
    configurations.add((connection: connection, expiry: subscriptionExpiry));
    this.connection = connection;
    expiry = subscriptionExpiry;
    await onConfigure?.call(connection, subscriptionExpiry);
  }

  @override
  Future<void> openNotificationSettings() async {
    openedSettings++;
  }

  @override
  Future<bool> canNotifySubscriptionExpiry() async => status.expiryAllowed;
  @override
  Future<void> notifySubscriptionExpiry(
      {required int expiringSoon, required int expired}) async {}
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(events.close());
  }
}
