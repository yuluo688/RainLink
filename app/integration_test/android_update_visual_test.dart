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
import 'package:rainlink/application/updates/app_update_controller.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/domain/updates/app_update.dart';
import 'package:rainlink/features/settings/presentation/widgets/update_settings_panel.dart';
import 'package:rainlink/platform/window/desktop_window.dart';

import '../test/android_update_installer_test.dart' show androidUpdateFixture;
import '../test/support/ui_fixture.dart';
import '../test/support/update_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('update states and system-install confirmation fit both layouts', (
    tester,
  ) async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    await initializeDesktopWindow();
    final output = Directory(
      const String.fromEnvironment(
        'RAINLINK_VISUAL_OUTPUT',
        defaultValue: '../docs/verification/android-app-update/visual',
      ),
    );
    await output.create(recursive: true);
    try {
      for (final (size, scale) in [
        (const Size(1440, 900), 1.0),
        (const Size(960, 640), 1.0),
        (const Size(393, 852), 1.0),
        (const Size(320, 740), 1.3),
      ]) {
        final mobile = size.width < 600;
        debugDefaultTargetPlatformOverride =
            mobile ? TargetPlatform.android : TargetPlatform.windows;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        for (final theme in [AppTheme.dark, AppTheme.light]) {
          for (final phase in [
            AppUpdatePhase.idle,
            AppUpdatePhase.available,
            AppUpdatePhase.downloading,
            AppUpdatePhase.downloaded,
            if (mobile) AppUpdatePhase.restartRequired,
          ]) {
            final release =
                mobile ? androidUpdateFixture() : fixtureUpdateRelease();
            final controller = VisualUpdateController(
              AppUpdateState(
                phase: phase,
                release: phase == AppUpdatePhase.idle ? null : release,
                package:
                    phase == AppUpdatePhase.downloaded
                        ? DownloadedUpdate(
                          release: release,
                          path: 'fixture/update',
                        )
                        : null,
                received: 13 * 1024 * 1024,
                total: 40 * 1024 * 1024,
              ),
            );
            final router = createRouter(initialLocation: '/settings');
            final capture = GlobalKey();
            await tester.pumpWidget(
              RepaintBoundary(
                key: capture,
                child: ProviderScope(
                  overrides: [
                    ...visualOverrides(theme: theme, connected: false),
                    updateInstallationModeProvider.overrideWithValue(
                      mobile
                          ? UpdateInstallationMode.androidInstaller
                          : UpdateInstallationMode.desktopRestart,
                    ),
                    appUpdateControllerProvider.overrideWith(
                      (ref) => controller,
                    ),
                    updateInstallerProvider.overrideWithValue(
                      FixtureUpdateInstaller(),
                    ),
                  ],
                  child: RainlinkApp(router: router),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('更新').hitTestable());
            await tester.pumpAndSettle();
            expect(find.byType(UpdateSettingsPanel), findsOneWidget);
            final action = find.byKey(
              ValueKey(
                phase == AppUpdatePhase.available
                    ? 'download-update'
                    : phase == AppUpdatePhase.downloaded
                    ? 'install-update'
                    : phase == AppUpdatePhase.downloading
                    ? 'cancel-update'
                    : 'check-update',
              ),
            );
            if (action.hitTestable().evaluate().isEmpty) {
              await tester.ensureVisible(action);
            }
            await tester.pumpAndSettle();
            Future<void> shot(String name) async {
              expect(tester.takeException(), isNull);
              await tester.runAsync(() async {
                final boundary =
                    capture.currentContext?.findRenderObject()
                        as RenderRepaintBoundary;
                final rendered = await boundary.toImage(pixelRatio: 1);
                try {
                  final bytes = await rendered.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  if (bytes == null) {
                    throw StateError('PNG encoding failed');
                  }
                  await File(
                    '${output.path}/update-${size.width.toInt()}-${theme.name}-$name-fixture.png',
                  ).writeAsBytes(bytes.buffer.asUint8List());
                } finally {
                  rendered.dispose();
                }
              });
            }

            await shot(phase.name);
            if (phase == AppUpdatePhase.downloaded) {
              await tester.tap(action);
              await tester.pumpAndSettle();
              expect(
                find.text(mobile ? '安装应用更新？' : '安装更新并重启？'),
                findsOneWidget,
              );
              final confirm =
                  find
                      .widgetWithText(FilledButton, mobile ? '继续安装' : '安装并重启')
                      .hitTestable();
              expect(confirm, findsOneWidget);
              await shot('confirmation');
              await tester.tap(find.widgetWithText(TextButton, '取消').last);
              await tester.pumpAndSettle();
            }
            await tester.pumpWidget(const SizedBox());
            router.dispose();
          }
        }
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    }
  });
}
