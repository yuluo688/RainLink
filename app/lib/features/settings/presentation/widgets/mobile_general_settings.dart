import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/groups/subscription_expiry_monitor.dart';
import '../../../../application/preferences/device_settings_controller.dart';
import '../../../../application/preferences/mobile_integration_controller.dart';
import '../../../../design_system/theme/rainlink_colors.dart';
import '../../../../design_system/widgets/surface_card.dart';
import '../../../../domain/core/runtime_settings.dart';
import '../../../../domain/preferences/general_preferences.dart';
import 'settings_rows.dart';

enum _NotificationKind { connection, expiry }

class MobileGeneralSettings extends ConsumerStatefulWidget {
  const MobileGeneralSettings({super.key});
  @override
  ConsumerState<MobileGeneralSettings> createState() =>
      _MobileGeneralSettingsState();
}

class _MobileGeneralSettingsState extends ConsumerState<MobileGeneralSettings> {
  bool _saving = false;
  String _error = '';

  Future<void> _save(GeneralPreferences preferences,
      {_NotificationKind? notification}) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      final mobile = ref.read(mobileIntegrationProvider);
      if (mobile == null) throw const SettingsException('当前平台尚未接入系统通知');
      if (notification != null) {
        var status = await mobile.inspectNotifications();
        if (!status.allowed) status = await mobile.requestNotifications();
        ref.invalidate(mobileNotificationStatusProvider);
        if (!mounted) return;
        if (!status.allowed ||
            (notification == _NotificationKind.connection &&
                !status.connectionAllowed) ||
            (notification == _NotificationKind.expiry &&
                !status.expiryAllowed)) {
          throw const SettingsException('系统未允许这类通知，请在系统通知设置中开启后重试');
        }
      }
      if (!mounted) return;
      await ref
          .read(deviceSettingsControllerProvider.notifier)
          .saveGeneral(preferences);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openSettings() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await ref.read(mobileIntegrationProvider)?.openNotificationSettings();
    } on Exception catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final general =
        ref.watch(deviceSettingsControllerProvider.select((v) => v.general));
    final status = ref.watch(mobileNotificationStatusProvider);
    final value = status.valueOrNull;
    final expiryError = ref.watch(subscriptionExpiryErrorProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: [
            SettingsToggleRow(
                key: const ValueKey('auto-connect'),
                title: '启动时自动连接',
                description: '打开应用时连接上次选中的目标',
                value: general.autoConnect,
                onChanged: _saving
                    ? null
                    : (v) => _save(general.copyWith(autoConnect: v))),
            const Divider(height: 1),
            const SettingsRow(
                title: '界面语言',
                description: '默认使用简体中文',
                controlWidth: 80,
                control: Text('简体中文', textAlign: TextAlign.end)),
          ])),
      const SizedBox(height: 12),
      SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: [
            SettingsRow(
                title: '系统通知',
                controlWidth: 84,
                minInlineWidth: 280,
                description: status.isLoading
                    ? '正在读取系统权限…'
                    : status.hasError
                        ? '无法读取通知权限，请重新检查'
                        : value?.allowed != true
                            ? '尚未允许通知，可在开启提醒时授权'
                            : value?.connectionAllowed != true ||
                                    value?.expiryAllowed != true
                                ? '部分通知通道已关闭'
                                : '系统已允许通知',
                control: TextButton(
                    key: const ValueKey('mobile-notification-settings'),
                    onPressed: _saving ? null : _openSettings,
                    child: const Text('系统设置'))),
            const Divider(height: 1),
            SettingsToggleRow(
                key: const ValueKey('connection-notifications'),
                title: '连接状态通知',
                description: '提醒连接、断开与异常，保留常驻通知',
                value: general.connectionNotifications,
                onChanged: _saving
                    ? null
                    : (v) => _save(general.copyWith(connectionNotifications: v),
                        notification: v ? _NotificationKind.connection : null)),
            const Divider(height: 1),
            SettingsToggleRow(
                key: const ValueKey('subscription-expiry-notifications'),
                title: '订阅到期提醒',
                description: '应用运行时在到期前 3 天和到期时提醒，只显示数量',
                value: general.subscriptionExpiryNotifications,
                onChanged: _saving
                    ? null
                    : (v) => _save(
                        general.copyWith(subscriptionExpiryNotifications: v),
                        notification: v ? _NotificationKind.expiry : null)),
          ])),
      if (_error.isNotEmpty ||
          (general.subscriptionExpiryNotifications && expiryError != null))
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error.isNotEmpty ? _error : (expiryError ?? ''),
                style: TextStyle(color: RainlinkColors.of(context).error))),
      if (status.hasError ||
          (general.subscriptionExpiryNotifications && expiryError != null))
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
                key: const ValueKey('retry-mobile-notifications'),
                onPressed: _saving
                    ? null
                    : () {
                        ref.invalidate(mobileNotificationStatusProvider);
                        ref.read(subscriptionExpiryMonitorProvider)?.checkNow();
                      },
                child: const Text('重新检查通知'))),
    ]);
  }
}
