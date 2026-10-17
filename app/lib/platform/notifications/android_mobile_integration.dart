import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/core/runtime_settings.dart';
import '../../domain/platform/mobile_integration.dart';

class AndroidMobileIntegration implements MobileIntegration {
  AndroidMobileIntegration({MethodChannel? channel, EventChannel? events})
      : _channel = channel ?? const MethodChannel('rainlink/mobile'),
        _events = events ?? const EventChannel('rainlink/mobile/actions');

  final MethodChannel _channel;
  final EventChannel _events;
  bool _disposed = false;
  int _requests = 0;

  Future<Object?> _call(String method,
      [Map<String, Object?>? arguments,
      Duration timeout = const Duration(seconds: 5)]) async {
    if (_disposed) throw const SettingsException('移动端系统接口已关闭');
    try {
      return await _channel
          .invokeMethod<Object?>(method, arguments)
          .timeout(timeout);
    } on PlatformException {
      throw const SettingsException('Android 未能完成此操作，请检查系统通知设置后重试');
    } on MissingPluginException {
      throw const SettingsException('当前构建未接入 Android 系统设置');
    } on TimeoutException {
      throw const SettingsException('Android 系统设置操作超时，请重新检查实际设置');
    }
  }

  MobileNotificationStatus _status(Object? value) {
    if (value
        case {
          'allowed': bool allowed,
          'connectionAllowed': bool connection,
          'expiryAllowed': bool expiry
        }) {
      return MobileNotificationStatus(
          allowed: allowed,
          connectionAllowed: connection,
          expiryAllowed: expiry);
    }
    throw const SettingsException('系统通知状态回执无效');
  }

  @override
  Stream<MobileAction> get actions =>
      _events.receiveBroadcastStream().map((value) {
        final action = MobileAction.values
            .where((action) => action.name == value)
            .firstOrNull;
        if (action == null) throw const SettingsException('系统通知操作回执无效');
        return action;
      });

  @override
  Future<MobileNotificationStatus> inspectNotifications() async =>
      _status(await _call('inspectNotifications'));

  @override
  Future<MobileNotificationStatus> requestNotifications() async {
    if (_disposed) throw const SettingsException('移动端系统接口已关闭');
    final id =
        'notification-${DateTime.now().microsecondsSinceEpoch}-${++_requests}';
    try {
      // A person may leave the Android permission dialog open for a while.
      return _status(await _channel.invokeMethod<Object?>(
          'requestNotifications',
          {'requestId': id}).timeout(const Duration(minutes: 2)));
    } on TimeoutException {
      await _call('cancelNotificationPermission', {'requestId': id});
      throw const SettingsException('通知授权等待超时，可在系统设置中开启通知后重试');
    } on PlatformException {
      throw const SettingsException('通知授权未完成，请稍后重试');
    } on MissingPluginException {
      throw const SettingsException('当前构建未接入 Android 系统设置');
    }
  }

  @override
  Future<void> configureNotifications(
      {required bool connection, required bool subscriptionExpiry}) async {
    final value = await _call('configureNotifications', {
      'connection': connection,
      'subscriptionExpiry': subscriptionExpiry,
    });
    if (value
        case {
          'connection': bool savedConnection,
          'subscriptionExpiry': bool savedExpiry
        }
        when savedConnection == connection &&
            savedExpiry == subscriptionExpiry) {
      return;
    }
    throw const SettingsException('系统通知偏好未通过回读确认');
  }

  @override
  Future<bool> canNotifySubscriptionExpiry() async =>
      (await inspectNotifications()).expiryAllowed;

  @override
  Future<void> notifySubscriptionExpiry(
      {required int expiringSoon, required int expired}) async {
    if (expiringSoon < 0 ||
        expired < 0 ||
        expiringSoon > 0x7fffffff ||
        expired > 0x7fffffff ||
        expiringSoon + expired == 0) {
      throw const SettingsException('订阅提醒数量无效');
    }
    if (await _call('notifySubscriptionExpiry',
            {'expiringSoon': expiringSoon, 'expired': expired}) !=
        true) {
      throw const SettingsException('系统未接收订阅到期提醒');
    }
  }

  @override
  Future<void> openNotificationSettings() async {
    if (await _call('openNotificationSettings') != true) {
      throw const SettingsException('系统未打开通知设置');
    }
  }

  @override
  void dispose() => _disposed = true;
}
