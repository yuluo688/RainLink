/// Delivery checks use the actual platform permission/channel or tray state.
abstract interface class AppNotifications {
  Future<bool> canNotifySubscriptionExpiry();
  Future<void> notifySubscriptionExpiry(
      {required int expiringSoon, required int expired});
}
