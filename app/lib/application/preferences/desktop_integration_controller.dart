import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/platform/desktop_integration.dart';
import '../../domain/core/runtime_settings.dart';

final desktopIntegrationProvider = Provider<DesktopIntegration?>((ref) => null);
final desktopIntegrationNoticeProvider = StateProvider<String?>((ref) => null);
final desktopIntegrationStatusProvider = AsyncNotifierProvider<
    DesktopIntegrationController,
    DesktopIntegrationStatus?>(DesktopIntegrationController.new);

class DesktopIntegrationController
    extends AsyncNotifier<DesktopIntegrationStatus?> {
  bool _saving = false;
  Object? _generation;

  @override
  Future<DesktopIntegrationStatus?> build() async {
    _generation = Object();
    ref.onDispose(() => _generation = null);
    return ref.watch(desktopIntegrationProvider)?.inspect();
  }

  Future<void> setLaunchAtLogin(bool enabled) async {
    if (_saving) return;
    final gateway = ref.read(desktopIntegrationProvider);
    if (gateway == null) throw const SettingsException('当前平台尚未接入开机启动');
    final generation = _generation;
    _saving = true;
    try {
      await gateway.setLaunchAtLogin(enabled);
      final observed = await gateway.inspect();
      if (generation == null || !identical(generation, _generation)) {
        throw const SettingsException('桌面设置操作已取消');
      }
      if (observed.launchAtLogin != enabled) {
        throw const SettingsException('开机启动设置未通过系统回读确认');
      }
      state = AsyncData(observed);
    } finally {
      _saving = false;
    }
  }
}
