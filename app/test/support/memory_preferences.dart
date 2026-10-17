import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/domain/preferences/device_settings.dart';
import 'package:rainlink/domain/core/runtime_settings.dart';
import 'package:rainlink/domain/core/advanced_config.dart';
import 'package:rainlink/domain/preferences/general_preferences.dart';

class MemoryPreferences
    implements PreferencesRepository, DeviceSettingsRepository {
  AppTheme theme = AppTheme.dark;
  Object? writeFailure;
  DeviceSettings settings = const DeviceSettings();

  @override
  Future<void> saveGeneral(GeneralPreferences value) async {
    if (writeFailure case final error?) throw error;
    settings = settings.copyWith(general: value);
  }

  @override
  Future<void> saveConnection(ConnectionPreferences value) async {
    if (writeFailure case final error?) throw error;
    settings = settings.copyWith(connection: value);
  }

  @override
  Future<DeviceSettings> loadDeviceSettings() async => settings;
  @override
  Future<void> saveAppearance(AppearancePreferences value) async {
    if (writeFailure case final error?) throw error;
    settings = settings.copyWith(appearance: value);
  }

  @override
  Future<void> saveRuntime(CoreRuntimeSettings value) async {
    if (writeFailure case final error?) throw error;
    settings = settings.copyWith(runtime: value);
  }

  @override
  Future<void> saveAdvanced(
      CoreRuntimeSettings value, AdvancedConfig previous) async {
    if (writeFailure case final error?) throw error;
    settings = settings.copyWith(runtime: value, previousAdvanced: previous);
  }

  @override
  Future<AppTheme> loadTheme() async => theme;

  @override
  Future<void> saveTheme(AppTheme value) async {
    if (writeFailure case final error?) throw error;
    theme = value;
  }
}
