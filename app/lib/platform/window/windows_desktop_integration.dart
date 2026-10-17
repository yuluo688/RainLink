import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/platform/desktop_integration.dart';
import '../../domain/core/runtime_settings.dart';

class WindowsDesktopIntegration implements DesktopIntegration {
  WindowsDesktopIntegration() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'action' || _closed) return;
      final action = DesktopAction.values
          .where((v) => v.name == call.arguments)
          .firstOrNull;
      if (action != null) _actions.add(action);
    });
  }
  static const _channel = MethodChannel('dev.rainlink/desktop');
  static const _timeout = Duration(seconds: 5);
  final _actions = StreamController<DesktopAction>.broadcast();
  bool _closed = false;

  Future<T?> _call<T>(String method, [Map<String, Object?>? arguments]) async {
    if (_closed) throw const SettingsException('桌面接口已关闭');
    try {
      return await _channel
          .invokeMethod<T>(method, arguments)
          .timeout(_timeout);
    } on PlatformException {
      throw const SettingsException('Windows 未能完成此操作，请保持窗口打开并重试');
    } on MissingPluginException {
      throw const SettingsException('当前构建未接入桌面系统功能');
    } on TimeoutException {
      throw const SettingsException('桌面操作超时，请重试并检查实际设置');
    }
  }

  @override
  Stream<DesktopAction> get actions => _actions.stream;
  @override
  Future<DesktopIntegrationStatus> inspect() async {
    final value = await _call<Object?>('inspect');
    if (value case {'launchAtLogin': bool launch, 'trayVisible': bool tray}) {
      return DesktopIntegrationStatus(launchAtLogin: launch, trayVisible: tray);
    }
    throw const SettingsException('桌面系统回执无效');
  }

  @override
  Future<void> setLaunchAtLogin(bool enabled) =>
      _call<void>('setLaunchAtLogin', {'enabled': enabled});
  @override
  Future<void> setTrayVisible(bool visible) =>
      _call<void>('setTrayVisible', {'visible': visible});
  @override
  Future<void> updateTray(
          {required String label,
          required String actionLabel,
          required bool busy}) =>
      _call<void>('updateTray',
          {'label': label, 'actionLabel': actionLabel, 'busy': busy});
  @override
  Future<void> showWindow() => _call<void>('showWindow');
  @override
  Future<void> hideWindow() => _call<void>('hideWindow');
  @override
  Future<void> notifyConnection(String message) =>
      _call<void>('notifyConnection', {'message': message});
  @override
  Future<bool> canNotifySubscriptionExpiry() async =>
      (await inspect()).trayVisible;
  @override
  Future<void> notifySubscriptionExpiry(
      {required int expiringSoon, required int expired}) {
    // The native API uses nonnegative signed 32-bit counts, not private names.
    const maximumCount = 0x7fffffff;
    if (expiringSoon < 0 ||
        expired < 0 ||
        expiringSoon > maximumCount ||
        expired > maximumCount ||
        expiringSoon + expired == 0) {
      throw const SettingsException('订阅提醒数量无效');
    }
    return _call<void>('notifySubscriptionExpiry',
        {'expiringSoon': expiringSoon, 'expired': expired});
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    await setTrayVisible(false);
    dispose();
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    _channel.setMethodCallHandler(null);
    unawaited(_actions.close());
  }
}
