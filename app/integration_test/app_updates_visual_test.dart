import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/app/router.dart';
import 'package:rainlink/application/preferences/device_settings_controller.dart';
import 'package:rainlink/application/updates/app_update_controller.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/domain/preferences/device_settings.dart';
import 'package:rainlink/domain/updates/app_update.dart';
import 'package:rainlink/platform/window/desktop_window.dart';

import '../test/support/ui_fixture.dart';
import '../test/support/update_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('update states fit both platform layouts, themes and large text',
      (tester) async {
    await initializeDesktopWindow();
    final output = Directory('../docs/verification/app-updates');
    await output.create(recursive: true);
    var screenshots = 0;
    try {
      for (final (size, textSize) in [
        (const Size(1440, 900), AppTextSize.standard),
        (const Size(960, 640), AppTextSize.standard),
        (const Size(393, 852), AppTextSize.standard),
        (const Size(320, 640), AppTextSize.extraLarge),
      ]) {
        final mobile = size.width < 600;
        debugDefaultTargetPlatformOverride =
            mobile ? TargetPlatform.iOS : TargetPlatform.windows;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        final safe = mobile
            ? const FakeViewPadding(top: 54, bottom: 34)
            : const FakeViewPadding();
        tester.view.padding = safe;
        tester.view.viewPadding = safe;
        for (final theme in [AppTheme.dark, AppTheme.light]) {
          for (final phase in [
            AppUpdatePhase.idle,
            AppUpdatePhase.empty,
            AppUpdatePhase.available,
            AppUpdatePhase.downloading,
            AppUpdatePhase.downloaded,
            AppUpdatePhase.failed,
            AppUpdatePhase.unavailable,
          ]) {
            final release = [
              AppUpdatePhase.available,
              AppUpdatePhase.downloading,
              AppUpdatePhase.downloaded,
            ].contains(phase)
                ? fixtureUpdateRelease()
                : null;
            final state = AppUpdateState(
                phase: phase,
                release: release,
                checkedAt: phase == AppUpdatePhase.idle
                    ? null
                    : DateTime(2026, 10, 17, 14, 30),
                received: 20 * 1024 * 1024,
                total: 40 * 1024 * 1024,
                package: phase == AppUpdatePhase.downloaded && release != null
                    ? DownloadedUpdate(
                        release: release, path: 'fixture/update.zip')
                    : null,
                error: phase == AppUpdatePhase.failed ? '检查更新超时，请检查网络后重试' : '');
            final router = createRouter(initialLocation: '/settings');
            final capture = GlobalKey();
            await tester.pumpWidget(RepaintBoundary(
                key: capture,
                child: ProviderScope(overrides: [
                  ...visualOverrides(theme: theme),
                  initialDeviceSettingsProvider.overrideWithValue(
                      DeviceSettings(
                          appearance:
                              AppearancePreferences(textSize: textSize))),
                  appUpdateControllerProvider
                      .overrideWith((ref) => VisualUpdateController(state)),
                  updateInstallerProvider
                      .overrideWithValue(FixtureUpdateInstaller()),
                ], child: RainlinkApp(router: router))));
            await tester.pumpAndSettle();
            await tester
                .ensureVisible(find.byKey(const ValueKey('settings-updates')));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const ValueKey('settings-updates')));
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('update-status')), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.runAsync(() async {
              final boundary = capture.currentContext?.findRenderObject()
                  as RenderRepaintBoundary;
              final rendered = await boundary.toImage(pixelRatio: 1);
              try {
                final data =
                    await rendered.toByteData(format: ui.ImageByteFormat.png);
                if (data == null) throw StateError('PNG encoding failed');
                await File(
                        '${output.path}/updates-${phase.name}-${size.width.toInt()}-${theme.name}-fixture.png')
                    .writeAsBytes(data.buffer.asUint8List());
                screenshots++;
              } finally {
                rendered.dispose();
              }
            });
            await tester.pumpWidget(const SizedBox());
            await tester.pumpAndSettle();
            router.dispose();
          }
        }
      }
      expect(screenshots, 56);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.view.resetPadding();
      tester.view.resetViewPadding();
    }
  });
}
