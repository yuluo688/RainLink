import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rainlink/app/dependencies.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/preferences/theme_controller.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/data/database/open_database.dart';
import 'package:rainlink/data/preferences/drift_preferences_repository.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop host handshake and theme persist to real SQLite', (
    tester,
  ) async {
    await app.main();
    await tester.pumpAndSettle();
    expect(find.byType(RainlinkApp), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RainlinkApp)),
    );
    final status = await container.read(coreStatusProvider.future);
    expect(
      status.hostAvailable,
      isTrue,
      reason:
          'Run tools/dev.ps1 smoke or tools/dev.sh smoke to build and locate the host.',
    );
    expect(status.capabilities.connect, Platform.isWindows || Platform.isLinux);
    if (Platform.isWindows || Platform.isLinux) {
      expect(status.coreVersion, isNotEmpty);
    }
    if (Platform.isWindows) {
      expect(status.capabilities.systemProxy, isTrue);
    }
    if (Platform.isLinux) {
      expect(status.capabilities.tun, isFalse);
    }
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('connect-button')))
          .onPressed,
      isNull,
    );

    final original = container.read(themeControllerProvider);
    final database = container.read(databaseProvider);
    final next = original == AppTheme.light ? AppTheme.dark : AppTheme.light;
    try {
      await tester.tap(find.byKey(const ValueKey('nav-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-appearance')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(ValueKey('theme-${next.name}')));
      await tester.tap(find.byKey(ValueKey('theme-${next.name}')));
      await tester.pumpAndSettle();
      expect(container.read(themeControllerProvider), next);

      expect(tester.takeException(), isNull);
    } finally {
      // Dispose the first app before reopening the on-disk database.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await database.close();
      final reopened = await openAppDatabase();
      try {
        final preferences = DriftPreferencesRepository(reopened);
        final saved = await preferences.loadTheme();
        await preferences.saveTheme(original);
        expect(saved, next);
      } finally {
        await reopened.close();
      }
    }
  });
}
