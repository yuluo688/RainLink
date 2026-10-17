import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/core/runtime_settings.dart';
import '../../domain/core/advanced_config.dart';
import '../../domain/preferences/device_settings.dart';
import '../../domain/preferences/general_preferences.dart';
import '../../domain/connection/connection_models.dart';
import 'desktop_integration_controller.dart';
import 'mobile_integration_controller.dart';
import '../core/core_providers.dart';
import '../connection/session_controller.dart';
import 'theme_controller.dart';

final initialDeviceSettingsProvider =
    Provider<DeviceSettings>((ref) => const DeviceSettings());
final deviceSettingsRepositoryProvider =
    Provider<DeviceSettingsRepository>((ref) {
  final repository = ref.watch(preferencesRepositoryProvider);
  if (repository is DeviceSettingsRepository) {
    return repository as DeviceSettingsRepository;
  }
  throw const SettingsException('当前存储不支持设备设置');
});
final runtimeSettingsGatewayProvider = Provider<RuntimeSettingsGateway?>((ref) {
  final gateway = ref.watch(coreGatewayProvider);
  return gateway is RuntimeSettingsGateway
      ? gateway as RuntimeSettingsGateway
      : null;
});
final deviceSettingsControllerProvider =
    NotifierProvider<DeviceSettingsController, DeviceSettings>(
        DeviceSettingsController.new);

class DeviceSettingsController extends Notifier<DeviceSettings> {
  Future<void> _pending = Future<void>.value();
  Object? _generation;

  /// Waits for settings already queued by the UI before the window exits.
  Future<void> flush() => _pending;

  @override
  DeviceSettings build() {
    _generation = Object();
    ref.onDispose(() => _generation = null);
    return ref.watch(initialDeviceSettingsProvider);
  }

  Future<void> saveAppearance(AppearancePreferences preferences) =>
      _enqueue((current, ensureActive) async {
        await ref
            .read(deviceSettingsRepositoryProvider)
            .saveAppearance(preferences);
        ensureActive();
        return current.copyWith(appearance: preferences);
      });

  Future<void> saveRuntime(CoreRuntimeSettings settings) =>
      _enqueue((current, ensureActive) async {
        // Forms only own their settings. Only applyAdvanced can replace a patch.
        final validated =
            settings.copyWith(advanced: current.runtime.advanced).validated();
        final gateway = ref.read(runtimeSettingsGatewayProvider);
        if (gateway == null) throw const SettingsException('当前平台尚未接入网络配置校验');
        await gateway.validateRuntime(validated);
        ensureActive();
        await ref.read(deviceSettingsRepositoryProvider).saveRuntime(validated);
        ensureActive();
        return current.copyWith(runtime: validated);
      });

  Future<void> applyAdvanced(AdvancedConfig config,
          {required CoreRuntimeSettings expectedRuntime,
          required int expectedSessionRevision}) =>
      _enqueue((current, ensureActive) async {
        if (jsonEncode(current.runtime.toJson()) !=
            jsonEncode(expectedRuntime.toJson())) {
          throw const SettingsException('网络设置已变化，请重新校验配置');
        }
        final gateway = ref.read(runtimeSettingsGatewayProvider);
        if (gateway == null) throw const SettingsException('当前平台尚未接入配置校验');
        final next = current.runtime.copyWith(advanced: config).validated();
        await gateway.validateRuntime(next);
        ensureActive();
        final session = ref.read(sessionControllerProvider.notifier);
        final view = ref.read(sessionControllerProvider);
        if (session.operationRevision != expectedSessionRevision ||
            view.working ||
            (view.active != null && !view.connected)) {
          throw const SettingsException('连接状态已变化，请重新确认应用');
        }
        final previousRuntime = session.appliedRuntimeSettings;
        if (view.connected) {
          await session.applyRuntime(next);
          ensureActive();
        }
        final appliedRevision = session.operationRevision;
        try {
          await ref
              .read(deviceSettingsRepositoryProvider)
              .saveAdvanced(next, current.runtime.advanced);
        } on Exception {
          // Do not reconnect if the user disconnected or selected another
          // operation during the disk write. Their cancellation takes priority.
          if (previousRuntime != null &&
              session.operationRevision == appliedRevision &&
              ref.read(sessionControllerProvider).connected) {
            try {
              await session.applyRuntime(previousRuntime);
            } on Exception {
              throw const SettingsException('配置未保存，原连接恢复未完成，请在概览检查连接状态');
            }
          }
          throw const SettingsException('配置未保存，原设置已保留；请检查磁盘空间后重试');
        }
        ensureActive();
        return current.copyWith(
            runtime: next, previousAdvanced: current.runtime.advanced);
      });

  Future<void> saveGeneral(GeneralPreferences preferences) =>
      _enqueue((current, ensureActive) async {
        final validated = preferences.validated();
        final gateway = ref.read(desktopIntegrationProvider);
        final mobile = ref.read(mobileIntegrationProvider);
        if (gateway == null && mobile == null) {
          throw const SettingsException('当前平台尚未接入通用设置');
        }
        if (gateway != null) validated.validatedForDesktop();
        if (mobile != null) {
          if (validated.showTray != current.general.showTray ||
              validated.closeBehavior != current.general.closeBehavior) {
            throw const SettingsException('移动端不支持桌面托盘与窗口选项');
          }
        }
        final trayChanged = current.general.showTray != validated.showTray;
        final notificationsChanged = current.general.connectionNotifications !=
                validated.connectionNotifications ||
            current.general.subscriptionExpiryNotifications !=
                validated.subscriptionExpiryNotifications;
        if (trayChanged) await gateway?.setTrayVisible(validated.showTray);
        try {
          if (mobile != null && notificationsChanged) {
            await mobile.configureNotifications(
                connection: validated.connectionNotifications,
                subscriptionExpiry: validated.subscriptionExpiryNotifications);
          }
          ensureActive();
          await ref
              .read(deviceSettingsRepositoryProvider)
              .saveGeneral(validated);
        } on Exception {
          if (mobile != null && notificationsChanged) {
            try {
              await mobile.configureNotifications(
                  connection: current.general.connectionNotifications,
                  subscriptionExpiry:
                      current.general.subscriptionExpiryNotifications);
            } on Exception {
              throw const SettingsException('设置未保存，系统通知偏好恢复失败，请重新打开应用后检查');
            }
          }
          if (trayChanged) {
            try {
              await gateway?.setTrayVisible(current.general.showTray);
            } on Exception {
              throw const SettingsException('通用设置保存失败，托盘恢复也未完成，请保持窗口打开并重试');
            }
          }
          rethrow;
        }
        ensureActive();
        return current.copyWith(general: validated);
      });

  /// Shares the save queue so startup cannot overwrite a user's newer choice
  /// while its native acknowledgement or database write is still in flight.
  Future<void> synchronizeMobileNotifications() =>
      _enqueue((current, ensureActive) async {
        final mobile = ref.read(mobileIntegrationProvider);
        if (mobile == null) {
          throw const SettingsException('当前平台尚未接入系统通知');
        }
        await mobile.configureNotifications(
            connection: current.general.connectionNotifications,
            subscriptionExpiry:
                current.general.subscriptionExpiryNotifications);
        ensureActive();
        return current;
      });

  Future<void> saveConnection(
          {ProxyMode? mode, bool? systemProxy, bool? tun}) =>
      _enqueue((current, ensureActive) async {
        final preferences = current.connection
            .copyWith(mode: mode, systemProxy: systemProxy, tun: tun);
        await ref
            .read(deviceSettingsRepositoryProvider)
            .saveConnection(preferences);
        ensureActive();
        return current.copyWith(connection: preferences);
      });

  Future<void> _enqueue(
      Future<DeviceSettings> Function(DeviceSettings, void Function()) update) {
    final generation = _generation;
    void ensureActive() {
      if (generation == null || !identical(generation, _generation)) {
        throw const SettingsException('设置操作已取消');
      }
    }

    final operation = _pending.then((_) async {
      ensureActive();
      final updated = await update(state, ensureActive);
      ensureActive();
      state = updated;
    });
    // Only recover the serial queue. The original caller receives the failure.
    _pending = operation.then((_) {}, onError: (Object _) {});
    return operation;
  }
}
