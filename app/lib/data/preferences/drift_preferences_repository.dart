import 'dart:convert';

import '../../domain/core/runtime_settings.dart';
import '../../domain/core/advanced_config.dart';
import '../../domain/preferences/app_preferences.dart';
import '../../domain/preferences/device_settings.dart';
import '../../domain/preferences/general_preferences.dart';
import '../database/app_database.dart';

class DriftPreferencesRepository
    implements PreferencesRepository, DeviceSettingsRepository {
  DriftPreferencesRepository(this.database);

  final AppDatabase database;
  static const _themeKey = 'appearance.theme';
  static const _appearanceKey = 'appearance.preferences';
  static const _runtimeKey = 'network.runtime';
  static const _generalKey = 'general.preferences';
  static const _connectionKey = 'connection.preferences';
  static const _advancedHistoryKey = 'core.advanced.previous';

  Future<Map<String, Object?>?> _load(String key) async {
    final row = await (database.select(database.preferences)
          ..where((table) => table.key.equals(key)))
        .getSingleOrNull();
    if (row == null) return null;
    try {
      final value = jsonDecode(row.value);
      if (value is Map<String, Object?>) return value;
    } on FormatException {
      throw const SettingsException('本地设置损坏，无法读取');
    }
    throw const SettingsException('本地设置格式无效');
  }

  Future<void> _save(String key, Map<String, Object?> value) async {
    await database.into(database.preferences).insertOnConflictUpdate(
        PreferencesCompanion.insert(key: key, value: jsonEncode(value)));
  }

  @override
  Future<DeviceSettings> loadDeviceSettings() => database.transaction(() async {
        final appearance = await _load(_appearanceKey);
        final runtime = await _load(_runtimeKey);
        final general = await _load(_generalKey);
        final connection = await _load(_connectionKey);
        final previousAdvanced = await _load(_advancedHistoryKey);
        return DeviceSettings(
            previousAdvanced: previousAdvanced == null
                ? null
                : previousAdvanced['config'] is String
                    ? AdvancedConfig.parse(
                        previousAdvanced['config'] as String, ConfigFormat.json)
                    : throw const SettingsException('上次高级配置格式无效'),
            appearance: appearance == null
                ? const AppearancePreferences()
                : AppearancePreferences.fromJson(appearance),
            runtime: runtime == null
                ? const CoreRuntimeSettings()
                : CoreRuntimeSettings.fromJson(runtime),
            general: general == null
                ? const GeneralPreferences()
                : GeneralPreferences.fromJson(general),
            connection: connection == null
                ? const ConnectionPreferences()
                : ConnectionPreferences.fromJson(connection));
      });

  @override
  Future<void> saveAppearance(AppearancePreferences preferences) =>
      _save(_appearanceKey, preferences.toJson());

  @override
  Future<void> saveRuntime(CoreRuntimeSettings settings) =>
      _save(_runtimeKey, settings.validated().toJson());

  @override
  Future<void> saveAdvanced(
          CoreRuntimeSettings settings, AdvancedConfig previous) =>
      database.transaction(() async {
        await _save(_runtimeKey, settings.validated().toJson());
        await _save(_advancedHistoryKey, {'config': previous.canonicalJson});
      });

  @override
  Future<void> saveGeneral(GeneralPreferences preferences) =>
      _save(_generalKey, preferences.validated().toJson());

  @override
  Future<void> saveConnection(ConnectionPreferences preferences) =>
      _save(_connectionKey, preferences.toJson());

  @override
  Future<AppTheme> loadTheme() async {
    final row = await (database.select(database.preferences)
          ..where((table) => table.key.equals(_themeKey)))
        .getSingleOrNull();
    return AppTheme.values.firstWhere(
      (theme) => theme.name == row?.value,
      orElse: () => AppTheme.dark,
    );
  }

  @override
  Future<void> saveTheme(AppTheme theme) async {
    await database.into(database.preferences).insertOnConflictUpdate(
          PreferencesCompanion.insert(key: _themeKey, value: theme.name),
        );
  }
}
