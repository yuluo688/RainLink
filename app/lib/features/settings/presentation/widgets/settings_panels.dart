import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/core/core_providers.dart';
import '../../../../application/preferences/theme_controller.dart';
import '../../../../application/preferences/device_settings_controller.dart';
import '../../../../application/connection/session_controller.dart';
import '../../../../design_system/theme/rainlink_colors.dart';
import '../../../../design_system/theme/rainlink_density.dart';
import '../../../../design_system/widgets/brand_mark.dart';
import '../../../../design_system/widgets/rainlink_icon.dart';
import '../../../../design_system/widgets/surface_card.dart';
import '../../../../domain/preferences/app_preferences.dart';
import '../../../../domain/preferences/device_settings.dart';
import '../../../../domain/core/runtime_settings.dart';
import '../../../../app/build_info.g.dart';
import 'settings_rows.dart';
import '../../../../design_system/layout/app_layout.dart';

class AppearanceSettingsPanel extends ConsumerStatefulWidget {
  const AppearanceSettingsPanel({super.key});

  @override
  ConsumerState<AppearanceSettingsPanel> createState() =>
      _AppearanceSettingsPanelState();
}

class _AppearanceSettingsPanelState
    extends ConsumerState<AppearanceSettingsPanel> {
  bool _saving = false;

  Future<void> _select(AppTheme theme) async {
    if (_saving || theme == ref.read(themeControllerProvider)) return;
    setState(() => _saving = true);
    var message = '外观设置已保存';
    try {
      await ref.read(themeControllerProvider.notifier).setTheme(theme);
    } on Exception {
      message = '保存外观设置失败，请重试。';
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _appearance(AppearancePreferences preferences) async {
    if (_saving) return;
    setState(() => _saving = true);
    String? error;
    try {
      await ref
          .read(deviceSettingsControllerProvider.notifier)
          .saveAppearance(preferences);
    } on Exception {
      error = '保存外观设置失败，请重试。';
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (mounted && error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(themeControllerProvider);
    final appearance =
        ref.watch(deviceSettingsControllerProvider.select((v) => v.appearance));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SettingsPanelHeading('外观', '选择适合你的界面风格。'),
      SurfaceCard(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('主题', style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              final choices = [
                for (final theme in AppTheme.values)
                  _ThemeChoice(
                    theme: theme,
                    selected: selected == theme,
                    compact: constraints.maxWidth < 480,
                    onTap: _saving ? null : () => _select(theme),
                  ),
              ];
              if (constraints.maxWidth < 220) {
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final choice in choices)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: choice),
                    ]);
              }
              return Row(children: [
                for (var index = 0; index < choices.length; index++) ...[
                  if (index > 0) const SizedBox(width: 8),
                  Expanded(child: choices[index]),
                ],
              ]);
            }),
            const SizedBox(height: 12),
            Text(_saving ? '正在保存…' : '主题在下次启动时保留。',
                style: Theme.of(context).textTheme.bodySmall),
          ])),
      const SizedBox(height: 12),
      SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SettingsRow(
                title: '界面密度',
                description: '调整列表和控件的留白',
                controlWidth: AppLayout.current == AppLayout.mobile ? 148 : 192,
                minInlineWidth: 280,
                control: _AppearanceSelector<AppDensity>(
                    key: const ValueKey('interface-density'),
                    label: '界面密度',
                    value: appearance.density,
                    items: [
                      for (final density in AppDensity.values)
                        DropdownMenuItem(
                            value: density, child: Text(density.label))
                    ],
                    onChanged: _saving
                        ? null
                        : (density) {
                            if (density != null) {
                              _appearance(
                                  appearance.copyWith(density: density));
                            }
                          })),
            const Divider(height: 1),
            SettingsRow(
                title: '文字大小',
                description: '跟随系统缩放，并应用所选字号',
                controlWidth: AppLayout.current == AppLayout.mobile ? 148 : 192,
                minInlineWidth: 280,
                control: _AppearanceSelector<AppTextSize>(
                    key: const ValueKey('text-size'),
                    label: '文字大小',
                    value: appearance.textSize,
                    items: [
                      for (final size in AppTextSize.values)
                        DropdownMenuItem(value: size, child: Text(size.label))
                    ],
                    onChanged: _saving
                        ? null
                        : (size) {
                            if (size != null) {
                              _appearance(appearance.copyWith(textSize: size));
                            }
                          })),
            const Divider(height: 1),
            SettingsToggleRow(
                key: const ValueKey('reduce-motion'),
                title: '减少动效',
                description: '简化页面切换和开关动画',
                value: appearance.reduceMotion,
                onChanged: _saving
                    ? null
                    : (value) =>
                        _appearance(appearance.copyWith(reduceMotion: value))),
          ])),
    ]);
  }
}

// These preferences have no draft form state. A controlled selector keeps its
// visible value in sync with the last successful save, including disk failures.
class _AppearanceSelector<T> extends StatelessWidget {
  const _AppearanceSelector({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    super.key,
  });
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final spacing = RainlinkDensity.of(context);
    final colors = RainlinkColors.of(context);
    final minimum =
        AppLayout.current == AppLayout.mobile ? 44.0 : spacing.segmentHeight;
    final height =
        math.max(minimum, MediaQuery.textScalerOf(context).scale(20) + 16);
    return Semantics(
        label: label,
        child: SizedBox(
            height: height,
            child: Material(
                color: colors.raised,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: colors.border)),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: DropdownButtonHideUnderline(
                        child: DropdownButton<T>(
                            value: value,
                            isDense: true,
                            isExpanded: true,
                            style: Theme.of(context).textTheme.bodyLarge,
                            dropdownColor: colors.raised,
                            borderRadius: BorderRadius.circular(8),
                            focusColor: colors.primarySurface,
                            icon: const RainlinkIcon(RainlinkGlyph.chevronDown,
                                size: 16),
                            items: items,
                            onChanged: onChanged))))));
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice(
      {required this.theme,
      required this.selected,
      required this.onTap,
      this.compact = false});
  final AppTheme theme;
  final bool selected;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = RainlinkColors.of(context);
    final label = switch (theme) {
      AppTheme.system => '跟随系统',
      AppTheme.dark => '深色',
      AppTheme.light => '浅色',
    };
    final preview =
        theme == AppTheme.light ? RainlinkColors.light : RainlinkColors.dark;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        key: ValueKey('theme-${theme.name}'),
        color: colors.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
              color: selected ? colors.primary : colors.border, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: compact ? 44 : 54,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: preview.background,
                        borderRadius: BorderRadius.circular(4)),
                    child: Row(children: [
                      Expanded(
                          flex: 2,
                          child: Container(
                              decoration: BoxDecoration(
                                  color: preview.raised,
                                  borderRadius: BorderRadius.circular(3)))),
                      const SizedBox(width: 4),
                      Expanded(
                          flex: 8,
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FractionallySizedBox(
                                    widthFactor: .65,
                                    child: Container(
                                        height: 5, color: preview.secondary)),
                                const SizedBox(height: 4),
                                FractionallySizedBox(
                                    widthFactor: .78,
                                    child: Container(
                                        height: 10,
                                        color: preview.primarySurface)),
                                const SizedBox(height: 4),
                                FractionallySizedBox(
                                    widthFactor: .62,
                                    child: Container(
                                        height: 4, color: preview.border)),
                              ])),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 24),
                      child: Row(children: [
                        Expanded(
                            child: Text(label,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: selected
                                            ? colors.primary
                                            : colors.secondary))),
                        if (selected)
                          RainlinkIcon(RainlinkGlyph.check,
                              size: 14, color: colors.primary),
                      ])),
                ]),
          ),
        ),
      ),
    );
  }
}

class CoreSettingsPanel extends ConsumerStatefulWidget {
  const CoreSettingsPanel({required this.onAdvanced, super.key});
  final VoidCallback onAdvanced;

  @override
  ConsumerState<CoreSettingsPanel> createState() => _CoreSettingsPanelState();
}

class _CoreSettingsPanelState extends ConsumerState<CoreSettingsPanel> {
  bool _saving = false;

  Future<void> _level(CoreLogLevel level) async {
    if (_saving) return;
    setState(() => _saving = true);
    String message = '日志级别已保存，下次连接时应用。';
    try {
      final runtime = ref.read(deviceSettingsControllerProvider).runtime;
      await ref
          .read(deviceSettingsControllerProvider.notifier)
          .saveRuntime(runtime.copyWith(logLevel: level));
    } on Exception catch (error) {
      message = '$error';
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _restart() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('重新启动核心？'),
                content: const Text('当前连接会短暂断开，随后使用原连接目标和规则快照，以及已保存的网络设置重新连接。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('重启核心'))
                ]));
    if (confirmed == true && mounted) {
      await ref.read(sessionControllerProvider.notifier).restart();
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(coreStatusProvider);
    final session = ref.watch(sessionControllerProvider);
    final runtime =
        ref.watch(deviceSettingsControllerProvider.select((v) => v.runtime));
    final settingsAvailable = ref.watch(runtimeSettingsGatewayProvider) != null;
    final advancedLog = runtime.advanced.fields['log'];
    final advancedLevel =
        advancedLog is Map<String, Object?> ? advancedLog['level'] : null;
    final displayLevel = CoreLogLevel.values
            .where((level) => level.name == advancedLevel)
            .firstOrNull ??
        runtime.logLevel;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SettingsPanelHeading('核心引擎', '查看引擎状态，管理日志与连接。'),
      SurfaceCard(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const RainlinkIcon(RainlinkGlyph.terminal, size: 24),
              const SizedBox(width: 12),
              Expanded(
                  child: Text('sing-box',
                      style: Theme.of(context).textTheme.titleMedium)),
              Text(session.statusLabel,
                  style: Theme.of(context).textTheme.bodySmall)
            ]),
            const SizedBox(height: 12),
            status.when(
                data: (value) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('核心版本 ${value.coreVersion ?? '未获取'}',
                              style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 8),
                          Text(
                              value.hostAvailable
                                  ? '桌面宿主已就绪${value.hostVersion == null ? '' : ' · ${value.hostVersion}'}'
                                  : value.message,
                              style: Theme.of(context).textTheme.bodySmall),
                        ]),
                loading: () => const LinearProgressIndicator(),
                error: (error, stackTrace) => const Text('无法读取核心状态，请重新检查。')),
            if (session.active case final active?
                when active.proxyPort > 0) ...[
              const SizedBox(height: 12),
              Text('本地代理 127.0.0.1:${active.proxyPort}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            if (session.error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(session.error,
                  style: TextStyle(color: RainlinkColors.of(context).error))
            ],
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                  key: const ValueKey('restart-core'),
                  onPressed: session.connected &&
                          !session.working &&
                          !_saving &&
                          ref
                              .read(sessionControllerProvider.notifier)
                              .canRestart
                      ? _restart
                      : null,
                  icon: const RainlinkIcon(RainlinkGlyph.power, size: 18),
                  label: const Text('重启核心')),
              OutlinedButton.icon(
                  key: const ValueKey('refresh-core'),
                  onPressed: status.isLoading
                      ? null
                      : () => ref.invalidate(coreStatusProvider),
                  icon: const RainlinkIcon(RainlinkGlyph.refresh, size: 18),
                  label: const Text('重新检查')),
            ]),
          ])),
      const SizedBox(height: 12),
      SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SettingsRow(
              title: '日志级别',
              description: runtime.advanced.overrides('log', 'level')
                  ? '由高级配置覆盖，清除覆盖后使用此选项'
                  : '保存后在下次连接时应用',
              control: DropdownButtonFormField<CoreLogLevel>(
                  key: const ValueKey('core-log-level'),
                  value: displayLevel,
                  isExpanded: true,
                  style: Theme.of(context).textTheme.bodyLarge,
                  icon: const RainlinkIcon(RainlinkGlyph.chevronDown, size: 16),
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    for (final level in CoreLogLevel.values)
                      DropdownMenuItem(
                          value: level,
                          child: Text(switch (level) {
                            CoreLogLevel.debug => '调试',
                            CoreLogLevel.info => '信息',
                            CoreLogLevel.warn => '警告',
                            CoreLogLevel.error => '错误'
                          }))
                  ],
                  onChanged: _saving ||
                          !settingsAvailable ||
                          runtime.advanced.overrides('log', 'level')
                      ? null
                      : (level) {
                          if (level != null) _level(level);
                        }))),
      const SizedBox(height: 12),
      SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SettingsLink(
              key: const ValueKey('open-advanced'),
              title: '高级配置',
              description: '查看与编辑 YAML / JSON',
              onTap: widget.onAdvanced)),
    ]);
  }
}

class AboutSettingsPanel extends StatelessWidget {
  const AboutSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) => SurfaceCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const BrandMark(size: 48),
          const SizedBox(height: 20),
          Text('RainLink', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('开发预览'),
          const SizedBox(height: 8),
          const Text('版本 $rainlinkVersion · 预览渠道'),
          const SizedBox(height: 24),
          Text('多协议网络客户端', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Text('在本机管理节点、订阅与可视化代理链。',
              style: Theme.of(context).textTheme.bodySmall),
          const Divider(height: 28),
          SettingsLink(
              title: '隐私说明',
              description: '本地数据、连接与必要网络请求',
              onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                          title: const Text('隐私说明'),
                          content: const SingleChildScrollView(
                              child: Text(
                                  '节点、订阅、偏好及用量保存在本机。Windows 凭据通过当前用户的系统保护加密保存。\n\n'
                                  '仅在导入或更新订阅、连接、测速、出口检测及手动 DNS 测试时请求相应服务。出口检测会访问公开 IP 查询服务。\n\n'
                                  '应用没有账户、云同步或分析上报。导出文件由你选择保存；分享前请检查内容。')),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('关闭'))
                          ]))),
          SettingsLink(
              title: '开源许可',
              description: 'Flutter、字体与网络核心许可',
              onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'RainLink',
                  applicationVersion: rainlinkVersion)),
        ]),
      );
}
