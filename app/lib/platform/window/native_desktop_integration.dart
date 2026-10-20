import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/core/runtime_settings.dart';
import '../../domain/platform/desktop_integration.dart';

/// Shared channel contract; the runner owns each platform's OS resources.
class NativeDesktopIntegration implements DesktopIntegration {
  NativeDesktopIntegration({
    required this.platformName,
    this.requireCapabilities = false,
  }) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'action' || _closed) return;
      final action =
          DesktopAction.values
              .where((value) => value.name == call.arguments)
              .firstOrNull;
      if (action != null) _actions.add(action);
    });
  }

  final String platformName;
  final bool requireCapabilities;
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
    } on PlatformException catch (error) {
      final message = switch (error.code) {
        'tray_unavailable' => '当前桌面没有可用的托盘，请保持窗口打开',
        'notifications_unavailable' => '当前桌面没有可用的通知服务，请检查后重试',
        'startup_conflict' => '开机启动项属于另一份 RainLink，请先在原应用中关闭',
        'tray_registration_cancelled' => '托盘操作已取消，请重试',
        _ => '$platformName 未能完成此操作，请保持窗口打开并重试',
      };
      throw SettingsException(message);
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
      // Existing Windows runners use the original two-field response.
      final keys = [
        'trayAvailable',
        'notificationsAvailable',
        'notificationsRequireTray',
      ];
      if (requireCapabilities && keys.any((key) => !value.containsKey(key))) {
        throw const SettingsException('桌面系统回执无效');
      }
      final trayAvailable = value.containsKey(keys[0]) ? value[keys[0]] : true;
      final notificationsAvailable =
          value.containsKey(keys[1]) ? value[keys[1]] : true;
      final notificationsRequireTray =
          value.containsKey(keys[2]) ? value[keys[2]] : true;
      if (trayAvailable is bool &&
          notificationsAvailable is bool &&
          notificationsRequireTray is bool &&
          (!tray || trayAvailable)) {
        return DesktopIntegrationStatus(
          launchAtLogin: launch,
          trayVisible: tray,
          trayAvailable: trayAvailable,
          notificationsAvailable: notificationsAvailable,
          notificationsRequireTray: notificationsRequireTray,
        );
      }
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
  Future<void> updateTray({
    required String label,
    required String actionLabel,
    required bool busy,
  }) {
    _validateText(label, 100);
    _validateText(actionLabel, 32);
    return _call<void>('updateTray', {
      'label': label,
      'actionLabel': actionLabel,
      'busy': busy,
    });
  }

  @override
  Future<void> showWindow() => _call<void>('showWindow');
  @override
  Future<void> hideWindow() => _call<void>('hideWindow');
  @override
  Future<void> notifyConnection(String message) {
    _validateText(message, 160);
    return _call<void>('notifyConnection', {'message': message});
  }

  @override
  Future<bool> canNotifySubscriptionExpiry() async {
    final status = await inspect();
    return status.notificationsAvailable &&
        (!status.notificationsRequireTray || status.trayVisible);
  }

  @override
  Future<void> notifySubscriptionExpiry({
    required int expiringSoon,
    required int expired,
  }) {
    const maximumCount = 0x7fffffff;
    if (expiringSoon < 0 ||
        expired < 0 ||
        expiringSoon > maximumCount ||
        expired > maximumCount ||
        expiringSoon + expired == 0) {
      throw const SettingsException('订阅提醒数量无效');
    }
    return _call<void>('notifySubscriptionExpiry', {
      'expiringSoon': expiringSoon,
      'expired': expired,
    });
  }

  void _validateText(String value, int maximum) {
    if (value.isEmpty ||
        value.runes.length > maximum ||
        value.codeUnits.any((character) => character < 0x20)) {
      throw const SettingsException('桌面提示内容无效');
    }
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
