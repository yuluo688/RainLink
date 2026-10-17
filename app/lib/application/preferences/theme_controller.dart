import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/preferences/app_preferences.dart';

final preferencesRepositoryProvider = Provider<PreferencesRepository>((ref) {
  throw StateError('PreferencesRepository must be provided during bootstrap.');
});

final initialThemeProvider = Provider<AppTheme>((ref) => AppTheme.dark);

final themeControllerProvider =
    NotifierProvider<ThemeController, AppTheme>(ThemeController.new);

class ThemeController extends Notifier<AppTheme> {
  Future<void> _pending = Future<void>.value();
  Object? _generation;
  late PreferencesRepository _preferences;

  @override
  AppTheme build() {
    _preferences = ref.watch(preferencesRepositoryProvider);
    final initial = ref.watch(initialThemeProvider);
    _generation = Object();
    ref.onDispose(() => _generation = null);
    return initial;
  }

  Future<void> setTheme(AppTheme theme) {
    final generation = _generation;
    final preferences = _preferences;
    final operation = _pending.then((_) async {
      _ensureActive(generation);
      // Compare when the request executes: an earlier write may change state.
      if (theme == state) return;
      await preferences.saveTheme(theme);
      _ensureActive(generation);
      state = theme;
    });
    // Recover only the queue; each caller still receives its operation's error.
    _pending = operation.catchError((Object _, StackTrace __) {});
    return operation;
  }

  void _ensureActive(Object? generation) {
    if (generation == null || !identical(generation, _generation)) {
      throw const ThemeUpdateCancelled();
    }
  }
}

/// Lifecycle cancellation, distinct from an unexpected programming error.
class ThemeUpdateCancelled implements Exception {
  const ThemeUpdateCancelled();

  @override
  String toString() => 'ThemeController is no longer active.';
}
