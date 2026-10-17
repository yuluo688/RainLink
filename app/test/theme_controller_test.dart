import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/preferences/theme_controller.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';

import 'support/memory_preferences.dart';

void main() {
  test('overlapping requests persist in order, including the initial theme',
      () async {
    final repository = DeferredPreferences();
    final container = ProviderContainer(overrides: [
      preferencesRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);
    final controller = container.read(themeControllerProvider.notifier);
    final light = controller.setTheme(AppTheme.light);
    final dark = controller.setTheme(AppTheme.dark);
    await Future<void>.delayed(Duration.zero);
    expect(repository.writes, [AppTheme.light]);
    repository.pending.single.complete();
    await light;
    await Future<void>.delayed(Duration.zero);
    expect(repository.writes, [AppTheme.light, AppTheme.dark]);
    repository.pending.last.complete();
    await dark;
    expect(repository.theme, AppTheme.dark);
    expect(container.read(themeControllerProvider), AppTheme.dark);
  });

  test('theme changes only after a successful persistent write', () async {
    final repository = MemoryPreferences();
    final container = ProviderContainer(overrides: [
      preferencesRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);
    await container
        .read(themeControllerProvider.notifier)
        .setTheme(AppTheme.light);
    expect(repository.theme, AppTheme.light);
    expect(container.read(themeControllerProvider), AppTheme.light);

    repository.writeFailure = StateError('Storage unavailable');
    await expectLater(
        container
            .read(themeControllerProvider.notifier)
            .setTheme(AppTheme.dark),
        throwsStateError);
    expect(container.read(themeControllerProvider), AppTheme.light);
    expect(repository.theme, AppTheme.light);
  });

  test('a failed write does not block a later queued request', () async {
    final repository = DeferredPreferences();
    final container = ProviderContainer(overrides: [
      preferencesRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);
    final controller = container.read(themeControllerProvider.notifier);
    final failed =
        expectLater(controller.setTheme(AppTheme.light), throwsStateError);
    final next = controller.setTheme(AppTheme.system);
    await Future<void>.delayed(Duration.zero);
    repository.pending.single.completeError(StateError('Disk full'));
    await failed;
    await Future<void>.delayed(Duration.zero);
    expect(repository.writes, [AppTheme.light, AppTheme.system]);
    expect(container.read(themeControllerProvider), AppTheme.dark);
    repository.pending.last.complete();
    await next;
    expect(repository.theme, AppTheme.system);
    expect(container.read(themeControllerProvider), AppTheme.system);
  });

  test('disposal prevents late state updates and queued writes', () async {
    final repository = DeferredPreferences();
    final container = ProviderContainer(overrides: [
      preferencesRepositoryProvider.overrideWithValue(repository),
    ]);
    final controller = container.read(themeControllerProvider.notifier);
    final first = expectLater(controller.setTheme(AppTheme.light),
        throwsA(isA<ThemeUpdateCancelled>()));
    final queued = expectLater(controller.setTheme(AppTheme.system),
        throwsA(isA<ThemeUpdateCancelled>()));
    await Future<void>.delayed(Duration.zero);
    container.dispose();
    repository.pending.single.complete();
    await Future.wait([first, queued]);
    expect(repository.writes, [AppTheme.light]);
    await expectLater(controller.setTheme(AppTheme.dark),
        throwsA(isA<ThemeUpdateCancelled>()));
  });
}

class DeferredPreferences extends MemoryPreferences {
  final writes = <AppTheme>[];
  final pending = <Completer<void>>[];

  @override
  Future<void> saveTheme(AppTheme value) async {
    writes.add(value);
    final completion = Completer<void>();
    pending.add(completion);
    await completion.future;
    await super.saveTheme(value);
  }
}
