import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/preferences/desktop_integration_controller.dart';
import '../../../../application/preferences/device_settings_controller.dart';
import '../../../../application/groups/subscription_expiry_monitor.dart';
import '../../../../design_system/layout/app_layout.dart';
import '../../../../design_system/theme/rainlink_colors.dart';
import '../../../../design_system/widgets/rainlink_icon.dart';
import '../../../../design_system/widgets/surface_card.dart';
import '../../../../domain/preferences/general_preferences.dart';
import 'settings_rows.dart';
import '../../../../application/preferences/mobile_integration_controller.dart';
import 'mobile_general_settings.dart';

class GeneralSettingsPanel extends ConsumerStatefulWidget {
  const GeneralSettingsPanel({required this.onAppearance, super.key});
  final VoidCallback onAppearance;
  @override
  ConsumerState<GeneralSettingsPanel> createState() =>
      _GeneralSettingsPanelState();
}

class _GeneralSettingsPanelState extends ConsumerState<GeneralSettingsPanel> {
  bool _saving = false;
  String _error = '';

  Future<void> _save(GeneralPreferences preferences) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await ref
          .read(deviceSettingsControllerProvider.notifier)
          .saveGeneral(preferences);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _launch(bool enabled) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await ref
          .read(desktopIntegrationStatusProvider.notifier)
          .setLaunchAtLogin(enabled);
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
    final expiryError = ref.watch(subscriptionExpiryErrorProvider);
    final available = AppLayout.current == AppLayout.desktop &&
        ref.watch(desktopIntegrationProvider) != null;
    final status =
        available ? ref.watch(desktopIntegrationStatusProvider) : null;
    final mobile = ref.watch(mobileIntegrationProvider) != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SettingsPanelHeading('通用', mobile ? '管理启动与系统通知。' : '管理启动、窗口与通知偏好。'),
      if (available) ...[
        SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(children: [
              SettingsToggleRow(
                  key: const ValueKey('launch-at-login'),
                  title: '开机启动',
                  description: status?.hasError == true
                      ? '无法读取系统设置，请重新检查'
                      : '登录当前 Windows 用户后运行 RainLink',
                  value: status?.valueOrNull?.launchAtLogin ?? false,
                  onChanged:
                      _saving || status?.hasValue != true ? null : _launch),
              const Divider(height: 1),
              SettingsToggleRow(
                  key: const ValueKey('auto-connect'),
                  title: '启动时自动连接',
                  description: '恢复上次目标、代理模式和系统代理选项',
                  value: general.autoConnect,
                  onChanged: _saving
                      ? null
                      : (v) => _save(general.copyWith(autoConnect: v))),
              const Divider(height: 1),
              SettingsRow(
                  title: '关闭窗口时',
                  description: '退出会先断开连接并恢复系统代理',
                  controlWidth: 180,
                  control: DropdownButtonFormField<WindowCloseBehavior>(
                      key: const ValueKey('window-close-behavior'),
                      value: general.closeBehavior,
                      isExpanded: true,
                      style: Theme.of(context).textTheme.bodyLarge,
                      decoration: const InputDecoration(isDense: true),
                      icon: const RainlinkIcon(RainlinkGlyph.chevronDown,
                          size: 16),
                      items: [
                        const DropdownMenuItem(
                            value: WindowCloseBehavior.exit,
                            child: Text('退出应用')),
                        DropdownMenuItem(
                            value: WindowCloseBehavior.tray,
                            enabled: general.showTray,
                            child: const Text('最小化到托盘')),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) {
                              if (value != null) {
                                _save(general.copyWith(closeBehavior: value));
                              }
                            })),
            ])),
        const SizedBox(height: 12),
        SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(children: [
              SettingsToggleRow(
                  key: const ValueKey('show-tray'),
                  title: '显示托盘图标',
                  description: '从系统栏恢复窗口或退出；关闭后停用托盘通知',
                  value: general.showTray,
                  onChanged: _saving
                      ? null
                      : (v) => _save(v
                          ? general.copyWith(showTray: true)
                          : general.copyWith(
                              showTray: false,
                              connectionNotifications: false,
                              subscriptionExpiryNotifications: false,
                              closeBehavior: WindowCloseBehavior.exit))),
              const Divider(height: 1),
              SettingsToggleRow(
                  key: const ValueKey('connection-notifications'),
                  title: '连接状态通知',
                  description: '系统允许时提醒连接、断开与异常',
                  value: general.connectionNotifications,
                  onChanged: _saving || !general.showTray
                      ? null
                      : (v) =>
                          _save(general.copyWith(connectionNotifications: v))),
              const Divider(height: 1),
              SettingsToggleRow(
                  key: const ValueKey('subscription-expiry-notifications'),
                  title: '订阅到期提醒',
                  description: '提前 3 天和到期时提醒，不显示订阅名称',
                  value: general.subscriptionExpiryNotifications,
                  onChanged: _saving || !general.showTray
                      ? null
                      : (value) => _save(general.copyWith(
                          subscriptionExpiryNotifications: value))),
              if (general.subscriptionExpiryNotifications &&
                  expiryError != null)
                Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(
                          child: Text(expiryError,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color:
                                          RainlinkColors.of(context).error))),
                      TextButton(
                          key: const ValueKey('retry-subscription-expiry'),
                          onPressed: _saving
                              ? null
                              : () => ref
                                  .read(subscriptionExpiryMonitorProvider)
                                  ?.checkNow(),
                          child: const Text('重试')),
                    ])),
              const Divider(height: 1),
              const SettingsRow(
                  title: '界面语言',
                  description: '默认使用简体中文',
                  control: Text('简体中文', textAlign: TextAlign.end)),
            ])),
        if (status?.hasError == true)
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  onPressed: _saving
                      ? null
                      : () => ref.invalidate(desktopIntegrationStatusProvider),
                  icon: const RainlinkIcon(RainlinkGlyph.refresh, size: 16),
                  label: const Text('重新检查系统设置'))),
      ] else if (mobile)
        const MobileGeneralSettings()
      else
        SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(children: [
              const SettingsRow(
                  title: '界面语言',
                  description: '默认使用简体中文',
                  control: Text('简体中文', textAlign: TextAlign.end)),
              const Divider(height: 1),
              const SettingsRow(
                  title: '启动行为',
                  description: '导入或选择节点后，仍由你开启连接。',
                  control: Text('保持未连接', textAlign: TextAlign.end)),
            ])),
      if (_error.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error,
                style: TextStyle(color: RainlinkColors.of(context).error))),
      const SizedBox(height: 12),
      SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SettingsLink(
              title: '外观与主题',
              description: '主题、文字大小与动效',
              onTap: widget.onAppearance)),
    ]);
  }
}
