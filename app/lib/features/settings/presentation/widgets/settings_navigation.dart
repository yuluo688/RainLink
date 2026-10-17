import 'package:flutter/material.dart';

import '../../../../design_system/theme/rainlink_colors.dart';
import '../../../../design_system/widgets/rainlink_icon.dart';
import '../../../../design_system/widgets/surface_card.dart';
import '../../../../design_system/theme/rainlink_density.dart';
import '../settings_section.dart';

class SettingsCategoryTabs extends StatelessWidget {
  const SettingsCategoryTabs({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final SettingsSection selected;
  final ValueChanged<SettingsSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = RainlinkColors.of(context);
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final section in SettingsSection.values)
        ChoiceChip(
          key: ValueKey('settings-${section.name}'),
          label: Text(section.label),
          avatar: RainlinkIcon(section.icon,
              size: 16,
              color: selected == section ? colors.primary : colors.secondary),
          showCheckmark: false,
          selectedColor: colors.primarySurface,
          labelStyle: TextStyle(
              fontSize: 13,
              color: selected == section ? colors.primary : colors.secondary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          selected: selected == section,
          onSelected: (_) => onSelected(section),
        ),
    ]);
  }
}

class SettingsCategorySidebar extends StatelessWidget {
  const SettingsCategorySidebar({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final SettingsSection selected;
  final ValueChanged<SettingsSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = RainlinkColors.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.all(8),
      child: Column(children: [
        for (final section in SettingsSection.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: selected == section
                  ? colors.primarySurface
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: ListTile(
                key: ValueKey('settings-${section.name}'),
                dense: RainlinkDensity.of(context).compact,
                minLeadingWidth: 18,
                horizontalTitleGap: 10,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                selected: selected == section,
                selectedTileColor: colors.primarySurface,
                selectedColor: colors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                leading: RainlinkIcon(section.icon, size: 18),
                title: Text(section.label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        height: 19 / 13,
                        color: selected == section
                            ? colors.primary
                            : colors.secondary)),
                onTap: () => onSelected(section),
              ),
            ),
          ),
      ]),
    );
  }
}
