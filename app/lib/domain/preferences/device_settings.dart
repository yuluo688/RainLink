import '../core/runtime_settings.dart';
import '../core/advanced_config.dart';
import 'general_preferences.dart';

enum AppTextSize {
  standard(1.0, '标准'),
  large(1.15, '较大'),
  extraLarge(1.3, '大');

  const AppTextSize(this.scale, this.label);
  final double scale;
  final String label;
}

enum AppDensity {
  compact('紧凑'),
  standard('标准');

  const AppDensity(this.label);
  final String label;
}

class AppearancePreferences {
  const AppearancePreferences(
      {this.textSize = AppTextSize.standard,
      this.reduceMotion = false,
      this.density = AppDensity.compact});
  final AppTextSize textSize;
  final bool reduceMotion;
  final AppDensity density;

  AppearancePreferences copyWith(
          {AppTextSize? textSize, bool? reduceMotion, AppDensity? density}) =>
      AppearancePreferences(
          textSize: textSize ?? this.textSize,
          reduceMotion: reduceMotion ?? this.reduceMotion,
          density: density ?? this.density);

  Map<String, Object?> toJson() => {
        'textSize': textSize.name,
        'reduceMotion': reduceMotion,
        'density': density.name,
      };

  factory AppearancePreferences.fromJson(Map<String, Object?> value) {
    if (value case {'textSize': String size, 'reduceMotion': bool reduce}) {
      final sizes = AppTextSize.values.where((v) => v.name == size);
      // Older preferences retain RainLink's compact default without a schema
      // change. A present but invalid density must not silently reset settings.
      final density = value.containsKey('density')
          ? AppDensity.values
              .where((v) => v.name == value['density'])
              .firstOrNull
          : AppDensity.compact;
      if (sizes.isNotEmpty && density != null) {
        return AppearancePreferences(
            textSize: sizes.first, reduceMotion: reduce, density: density);
      }
    }
    throw const SettingsException('外观偏好格式无效');
  }
}

class DeviceSettings {
  const DeviceSettings(
      {this.appearance = const AppearancePreferences(),
      this.runtime = const CoreRuntimeSettings(),
      this.general = const GeneralPreferences(),
      this.previousAdvanced,
      this.connection = const ConnectionPreferences()});
  final AppearancePreferences appearance;
  final CoreRuntimeSettings runtime;
  final GeneralPreferences general;
  final ConnectionPreferences connection;
  final AdvancedConfig? previousAdvanced;
  DeviceSettings copyWith(
          {AppearancePreferences? appearance,
          CoreRuntimeSettings? runtime,
          GeneralPreferences? general,
          AdvancedConfig? previousAdvanced,
          ConnectionPreferences? connection}) =>
      DeviceSettings(
          appearance: appearance ?? this.appearance,
          runtime: runtime ?? this.runtime,
          general: general ?? this.general,
          previousAdvanced: previousAdvanced ?? this.previousAdvanced,
          connection: connection ?? this.connection);
}

abstract interface class DeviceSettingsRepository {
  Future<DeviceSettings> loadDeviceSettings();
  Future<void> saveAppearance(AppearancePreferences preferences);
  Future<void> saveRuntime(CoreRuntimeSettings settings);

  /// Stores the patch and its preceding version in one transaction.
  Future<void> saveAdvanced(
      CoreRuntimeSettings settings, AdvancedConfig previous);
  Future<void> saveGeneral(GeneralPreferences preferences);
  Future<void> saveConnection(ConnectionPreferences preferences);
}
