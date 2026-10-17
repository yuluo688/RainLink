import 'package:flutter/material.dart';

import '../../../design_system/widgets/page_frame.dart';
import 'settings_section.dart';
import 'widgets/settings_navigation.dart';

class DesktopSettings extends StatelessWidget {
  const DesktopSettings({
    required this.selected,
    required this.onSelected,
    required this.child,
    this.detail = false,
    super.key,
  });

  final SettingsSection selected;
  final ValueChanged<SettingsSection> onSelected;
  final Widget child;
  final bool detail;

  @override
  Widget build(BuildContext context) => PageFrame(
        key: ValueKey((selected, detail)),
        title: '设置',
        description: detail ? '' : '偏好即时保存，网络设置在下次连接时应用。',
        child: LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth < 580) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsCategoryTabs(
                      selected: selected, onSelected: onSelected),
                  const SizedBox(height: 24),
                  child,
                ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: constraints.maxWidth < 900 ? 140 : 184,
              child: SettingsCategorySidebar(
                  selected: selected, onSelected: onSelected),
            ),
            const SizedBox(width: 20),
            Expanded(child: child),
          ]);
        }),
      );
}
