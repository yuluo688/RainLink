import 'package:flutter/material.dart';

import '../../../../design_system/widgets/rainlink_icon.dart';
import '../../../../design_system/widgets/rainlink_switch.dart';
import '../../../../design_system/layout/app_layout.dart';
import '../../../../design_system/theme/rainlink_density.dart';

class SettingsPanelHeading extends StatelessWidget {
  const SettingsPanelHeading(this.title, this.description, {super.key});
  final String title;
  final String description;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (AppLayout.current == AppLayout.desktop) ...[
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
        ],
        Text(description, style: Theme.of(context).textTheme.bodySmall),
      ]));
}

class SettingsRow extends StatelessWidget {
  const SettingsRow(
      {required this.title,
      required this.description,
      required this.control,
      this.controlWidth = 184,
      this.minInlineWidth = 420,
      super.key});
  final String title;
  final String description;
  final Widget control;
  final double controlWidth;
  final double minInlineWidth;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final label =
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.bodyLarge),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(description, style: Theme.of(context).textTheme.bodySmall),
          ],
        ]);
        final stack = controlWidth > 80 &&
            (constraints.maxWidth < minInlineWidth ||
                MediaQuery.textScalerOf(context).scale(14) > 17);
        return Padding(
            padding: EdgeInsets.symmetric(
                vertical: RainlinkDensity.of(context).settingsPadding),
            child: stack
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [label, const SizedBox(height: 12), control])
                : Row(children: [
                    Expanded(child: label),
                    const SizedBox(width: 16),
                    SizedBox(width: controlWidth, child: control)
                  ]));
      });
}

class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow(
      {required this.title,
      required this.description,
      required this.value,
      required this.onChanged,
      super.key});
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => SettingsRow(
      title: title,
      description: description,
      controlWidth: 44,
      control:
          RainlinkSwitch(label: title, value: value, onChanged: onChanged));
}

class SettingsLink extends StatelessWidget {
  const SettingsLink(
      {required this.title,
      required this.description,
      required this.onTap,
      super.key});
  final String title;
  final String description;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: Theme.of(context).textTheme.bodyLarge),
      subtitle: Text(description, style: Theme.of(context).textTheme.bodySmall),
      trailing: const RainlinkIcon(RainlinkGlyph.chevronRight, size: 18),
      onTap: onTap);
}
