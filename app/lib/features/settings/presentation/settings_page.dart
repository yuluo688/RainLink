import 'package:flutter/material.dart';

import '../../../design_system/layout/app_layout.dart';
import 'desktop_settings.dart';
import 'mobile_settings.dart';
import 'settings_section.dart';
import 'widgets/settings_panels.dart';
import 'widgets/network_settings_panel.dart';
import 'widgets/general_settings_panel.dart';
import 'widgets/advanced_settings_panel.dart';
import 'widgets/update_settings_panel.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SettingsSection? _section;
  bool _advanced = false;

  void _selectSection(SettingsSection section) {
    setState(() {
      _section = section;
      _advanced = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = _advanced
        ? AdvancedSettingsPanel(onBack: () => setState(() => _advanced = false))
        : switch (_section ?? SettingsSection.general) {
            SettingsSection.general => GeneralSettingsPanel(
                onAppearance: () => _selectSection(SettingsSection.appearance)),
            SettingsSection.appearance => const AppearanceSettingsPanel(),
            SettingsSection.network => const NetworkSettingsPanel(),
            SettingsSection.core => CoreSettingsPanel(
                onAdvanced: () => setState(() => _advanced = true)),
            SettingsSection.updates => const UpdateSettingsPanel(),
            SettingsSection.about => const AboutSettingsPanel(),
          };
    return switch (AppLayout.current) {
      AppLayout.desktop => DesktopSettings(
          detail: _advanced,
          selected: _section ?? SettingsSection.general,
          onSelected: _selectSection,
          child: content),
      AppLayout.mobile => MobileSettings(
          selected: _section,
          detailTitle: _advanced ? '高级配置' : null,
          onSelected: _selectSection,
          onBack: () => setState(() {
                if (_advanced) {
                  _advanced = false;
                } else {
                  _section = null;
                }
              }),
          child: content),
    };
  }
}
