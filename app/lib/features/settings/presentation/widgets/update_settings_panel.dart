import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/build_info.g.dart';
import '../../../../application/updates/app_update_controller.dart';
import '../../../../design_system/theme/rainlink_colors.dart';
import '../../../../design_system/layout/app_layout.dart';
import '../../../../design_system/widgets/brand_mark.dart';
import '../../../../design_system/widgets/rainlink_icon.dart';
import '../../../../design_system/widgets/surface_card.dart';
import 'settings_rows.dart';

class UpdateSettingsPanel extends ConsumerStatefulWidget {
  const UpdateSettingsPanel({super.key});
  @override
  ConsumerState<UpdateSettingsPanel> createState() =>
      _UpdateSettingsPanelState();
}

class _UpdateSettingsPanelState extends ConsumerState<UpdateSettingsPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(appUpdateControllerProvider.notifier).initialize();
    });
  }

  Future<void> _install() async {
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('安装更新并重启？'),
                content: const Text(
                    '当前连接将断开。RainLink 会先恢复网络并保存设置，再安装已校验的更新包。安装失败时保留或恢复原版本。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('安装并重启'))
                ]));
    if (accepted == true && mounted) {
      await ref.read(appUpdateControllerProvider.notifier).install();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appUpdateControllerProvider);
    final controller = ref.read(appUpdateControllerProvider.notifier);
    final colors = RainlinkColors.of(context);
    final available = state.phase != AppUpdatePhase.unavailable;
    final checking = state.phase == AppUpdatePhase.checking;
    final downloading = state.phase == AppUpdatePhase.downloading;
    final preparing = state.phase == AppUpdatePhase.preparing;
    final installing = state.phase == AppUpdatePhase.installing;
    final release = state.release;
    final asset = release?.asset;
    final supported = ref.watch(updateInstallerProvider) != null;
    final canDownload = asset?.sha256 != null && supported;
    final status = switch (state.phase) {
      AppUpdatePhase.unavailable => '此平台的应用更新尚未接入',
      AppUpdatePhase.idle => '检查可用版本',
      AppUpdatePhase.checking => '正在检查更新…',
      AppUpdatePhase.empty => '尚无可用发布版本',
      AppUpdatePhase.current => '当前版本无需更新',
      AppUpdatePhase.available => '发现新版本 ${release?.tag ?? ''}',
      AppUpdatePhase.downloading => '正在下载更新…',
      AppUpdatePhase.downloaded => '更新包已下载并通过校验',
      AppUpdatePhase.preparing => '正在准备安装…',
      AppUpdatePhase.installing => '正在恢复网络并交接安装…',
      AppUpdatePhase.failed => '更新操作未完成',
    };
    final mobile = AppLayout.current == AppLayout.mobile;
    Widget action(Widget child) => mobile
        ? SizedBox(width: double.infinity, child: child)
        : ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 156), child: child);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SettingsPanelHeading('更新', '管理应用版本与更新渠道。'),
      SurfaceCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const BrandMark(),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('RainLink $rainlinkVersion',
                    style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 4),
                Text('当前版本 · 开发预览',
                    style: Theme.of(context).textTheme.bodySmall),
              ])),
          if (!mobile && MediaQuery.textScalerOf(context).scale(14) <= 17) ...[
            const SizedBox(width: 12),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: colors.raised,
                    borderRadius: BorderRadius.circular(6)),
                child: Text(
                    state.phase == AppUpdatePhase.available ? '发现更新' : '当前版本',
                    style: Theme.of(context).textTheme.bodySmall))
          ],
        ]),
        const SizedBox(height: 16),
        Text(status,
            key: const ValueKey('update-status'),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontSize: mobile ? 14 : 18, fontWeight: FontWeight.w500)),
        if (state.phase == AppUpdatePhase.empty)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('发布源还没有适合当前渠道的版本。你可以稍后重新检查。',
                  style: Theme.of(context).textTheme.bodySmall)),
        if (downloading) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(
              value: state.total == 0 ? null : state.received / state.total),
          const SizedBox(height: 8),
          Text(
              '${(state.received / 1048576).toStringAsFixed(1)} / ${(state.total / 1048576).toStringAsFixed(1)} MB',
              style: Theme.of(context).textTheme.bodySmall),
        ],
        if (state.error.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(state.error,
                  key: const ValueKey('update-error'),
                  style: TextStyle(color: colors.error))),
        if (state.notice.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(state.notice,
                  style: Theme.of(context).textTheme.bodySmall)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (checking || downloading || preparing)
            action(OutlinedButton(
                key: const ValueKey('cancel-update'),
                onPressed: controller.cancel,
                child: const Text('取消')))
          else
            action(OutlinedButton.icon(
                key: const ValueKey('check-update'),
                onPressed:
                    !available || state.working ? null : controller.check,
                icon: const RainlinkIcon(RainlinkGlyph.refresh, size: 16),
                label: const Text('检查更新'))),
          if (!checking &&
              !downloading &&
              !preparing &&
              !installing &&
              state.package != null &&
              supported)
            action(FilledButton(
                key: const ValueKey('install-update'),
                onPressed: state.working ? null : _install,
                child: const Text('安装并重启')))
          else if (state.phase == AppUpdatePhase.available ||
              (state.phase == AppUpdatePhase.failed && release != null))
            action(FilledButton.icon(
                key: const ValueKey('download-update'),
                onPressed:
                    !canDownload || state.working ? null : controller.download,
                icon: const RainlinkIcon(RainlinkGlyph.download, size: 16),
                label: const Text('下载更新'))),
        ]),
        if (release != null &&
            state.phase == AppUpdatePhase.available &&
            !canDownload)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                  asset == null
                      ? '此版本尚未提供当前平台的更新包。'
                      : asset.sha256 == null
                          ? '发布包缺少 SHA-256 校验信息，暂不可下载。'
                          : '当前构建尚未接入安装交接。',
                  style: Theme.of(context).textTheme.bodySmall)),
        const SizedBox(height: 12),
        Text(
            state.checkedAt == null
                ? '上次检查：尚未检查'
                : '上次检查：${state.checkedAt?.toLocal().toString().split('.').first}',
            style: Theme.of(context).textTheme.bodySmall),
      ])),
      ...[
        const SizedBox(height: 12),
        SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(children: [
              SettingsToggleRow(
                  key: const ValueKey('startup-update-check'),
                  title: '自动检查更新',
                  description: available ? '启动时检查，不自动下载或安装' : '此平台尚未接入版本检查',
                  value: state.preferences.checkOnStartup,
                  onChanged: !available || state.working
                      ? null
                      : (value) => controller.savePreferences(
                          state.preferences.copyWith(checkOnStartup: value))),
              const Divider(height: 1),
              SettingsRow(
                  key: const ValueKey('preview-update-channel'),
                  title: '更新渠道',
                  description: available ? '选择接收版本的范围' : '随安装来源管理更新',
                  control: available
                      ? DropdownButtonFormField<bool>(
                          value: state.preferences.includePreview,
                          isExpanded: true,
                          icon: const RainlinkIcon(RainlinkGlyph.chevronDown,
                              size: 16),
                          items: const [
                            DropdownMenuItem(value: false, child: Text('稳定版')),
                            DropdownMenuItem(value: true, child: Text('包含预览版')),
                          ],
                          onChanged: state.working
                              ? null
                              : (value) {
                                  if (value != null) {
                                    controller.savePreferences(state.preferences
                                        .copyWith(includePreview: value));
                                  }
                                })
                      : const Text('尚未配置')),
            ])),
      ],
      if (release != null && release.notes.isNotEmpty) ...[
        const SizedBox(height: 12),
        SurfaceCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('更新内容 · ${release.tag}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SelectableText(release.notes,
              style: Theme.of(context).textTheme.bodySmall),
        ])),
      ],
    ]);
  }
}
