import 'package:flutter/material.dart';

import '../../../design_system/widgets/page_frame.dart';
import '../../../design_system/widgets/brand_mark.dart';
import '../../../design_system/widgets/rainlink_icon.dart';
import '../../../design_system/widgets/surface_card.dart';
import '../../../design_system/theme/rainlink_density.dart';
import 'settings_section.dart';
import '../../../app/build_info.g.dart';

class MobileSettings extends StatelessWidget {
  const MobileSettings({
    required this.selected,
    required this.onSelected,
    required this.onBack,
    required this.child,
    this.detailTitle,
    super.key,
  });

  final SettingsSection? selected;
  final ValueChanged<SettingsSection> onSelected;
  final VoidCallback onBack;
  final Widget child;
  final String? detailTitle;

  @override
  Widget build(BuildContext context) {
    if (selected case final section?) {
      return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) onBack();
          },
          child: PageFrame(
              key: ValueKey((section, detailTitle)),
              title: detailTitle ?? section.label,
              description: '',
              leading: IconButton(
                  key: const ValueKey('settings-back'),
                  tooltip: '返回设置',
                  onPressed: onBack,
                  icon: const RainlinkIcon(RainlinkGlyph.back)),
              child: child));
    }
    return PageFrame(
        title: '设置',
        description: '管理偏好与网络选项',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const BrandMark(size: 40),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('RainLink',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text('$rainlinkVersion · 开发预览',
                          style: Theme.of(context).textTheme.bodySmall),
                    ])),
              ])),
          const SizedBox(height: 12),
          SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(children: [
                for (var i = 0; i < SettingsSection.values.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                      key: ValueKey(
                          'settings-${SettingsSection.values[i].name}'),
                      contentPadding: EdgeInsets.zero,
                      minVerticalPadding:
                          RainlinkDensity.of(context).logPadding,
                      title: Text(SettingsSection.values[i].label,
                          style: Theme.of(context).textTheme.bodyLarge),
                      subtitle: Text(
                          switch (SettingsSection.values[i]) {
                            SettingsSection.general => '语言与启动行为',
                            SettingsSection.appearance => '主题、文字大小与动效',
                            SettingsSection.network => 'DNS 与本地监听',
                            SettingsSection.core => 'sing-box · 状态与日志',
                            SettingsSection.updates => '版本与更新渠道',
                            SettingsSection.about => '隐私与开源许可',
                          },
                          style: Theme.of(context).textTheme.bodySmall),
                      trailing: const RainlinkIcon(RainlinkGlyph.chevronRight,
                          size: 18),
                      onTap: () => onSelected(SettingsSection.values[i])),
                ],
              ])),
        ]));
  }
}
