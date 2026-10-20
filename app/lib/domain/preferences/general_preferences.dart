import '../connection/connection_models.dart';
import '../core/runtime_settings.dart';

enum WindowCloseBehavior { exit, tray }

class GeneralPreferences {
  const GeneralPreferences({
    this.autoConnect = false,
    this.showTray = true,
    this.connectionNotifications = false,
    this.subscriptionExpiryNotifications = false,
    this.closeBehavior = WindowCloseBehavior.exit,
  });
  final bool autoConnect;
  final bool showTray;
  final bool connectionNotifications;
  final bool subscriptionExpiryNotifications;
  final WindowCloseBehavior closeBehavior;

  GeneralPreferences copyWith({
    bool? autoConnect,
    bool? showTray,
    bool? connectionNotifications,
    bool? subscriptionExpiryNotifications,
    WindowCloseBehavior? closeBehavior,
  }) => GeneralPreferences(
    autoConnect: autoConnect ?? this.autoConnect,
    showTray: showTray ?? this.showTray,
    connectionNotifications:
        connectionNotifications ?? this.connectionNotifications,
    subscriptionExpiryNotifications:
        subscriptionExpiryNotifications ?? this.subscriptionExpiryNotifications,
    closeBehavior: closeBehavior ?? this.closeBehavior,
  );

  GeneralPreferences validated() {
    if (!showTray && closeBehavior == WindowCloseBehavior.tray) {
      throw const SettingsException('关闭到托盘需要开启托盘图标');
    }
    return this;
  }

  GeneralPreferences validatedForDesktop({
    bool notificationsRequireTray = true,
  }) {
    validated();
    if (notificationsRequireTray &&
        !showTray &&
        (connectionNotifications || subscriptionExpiryNotifications)) {
      throw const SettingsException('系统通知需要开启托盘图标');
    }
    return this;
  }

  Map<String, Object?> toJson() => {
    'autoConnect': autoConnect,
    'showTray': showTray,
    'connectionNotifications': connectionNotifications,
    'subscriptionExpiryNotifications': subscriptionExpiryNotifications,
    'closeBehavior': closeBehavior.name,
  };

  factory GeneralPreferences.fromJson(Map<String, Object?> value) {
    if (value case {
      'autoConnect': bool autoConnect,
      'showTray': bool showTray,
      'connectionNotifications': bool notifications,
      'closeBehavior': String close,
    }) {
      final behavior =
          WindowCloseBehavior.values.where((v) => v.name == close).firstOrNull;
      final expiry =
          value.containsKey('subscriptionExpiryNotifications')
              ? value['subscriptionExpiryNotifications']
              : false;
      if (behavior != null && expiry is bool) {
        return GeneralPreferences(
          autoConnect: autoConnect,
          showTray: showTray,
          connectionNotifications: notifications,
          subscriptionExpiryNotifications: expiry,
          closeBehavior: behavior,
        ).validated();
      }
    }
    throw const SettingsException('通用设置格式无效');
  }
}

/// Only confirmed mode/capture choices are remembered, never an active session.
class ConnectionPreferences {
  const ConnectionPreferences({
    this.mode = ProxyMode.rule,
    this.systemProxy = false,
    this.tun = false,
  });
  final ProxyMode mode;
  final bool systemProxy;
  final bool tun;
  ConnectionPreferences copyWith({
    ProxyMode? mode,
    bool? systemProxy,
    bool? tun,
  }) => ConnectionPreferences(
    mode: mode ?? this.mode,
    systemProxy: systemProxy ?? this.systemProxy,
    tun: tun ?? this.tun,
  );
  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'systemProxy': systemProxy,
    'tun': tun,
  };
  factory ConnectionPreferences.fromJson(Map<String, Object?> value) {
    if (value case {'mode': String name, 'systemProxy': bool proxy}) {
      final mode = ProxyMode.values.where((v) => v.name == name).firstOrNull;
      final tun = value['tun'] ?? false;
      if (mode != null && tun is bool) {
        return ConnectionPreferences(mode: mode, systemProxy: proxy, tun: tun);
      }
    }
    throw const SettingsException('连接偏好格式无效');
  }
}
