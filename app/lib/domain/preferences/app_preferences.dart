enum AppTheme { system, dark, light }

abstract interface class PreferencesRepository {
  Future<AppTheme> loadTheme();

  Future<void> saveTheme(AppTheme theme);
}
