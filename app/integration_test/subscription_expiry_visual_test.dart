import 'dart:async';
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
import 'package:rainlink/application/groups/subscription_expiry_monitor.dart';
import 'package:rainlink/application/preferences/desktop_integration_controller.dart';
import 'package:rainlink/application/preferences/device_settings_controller.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/domain/preferences/device_settings.dart';
import 'package:rainlink/domain/preferences/general_preferences.dart';
import 'package:rainlink/platform/window/desktop_window.dart';

import '../test/support/fake_desktop_integration.dart';
import '../test/support/ui_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('expiry settings fit themes, densities, large text and mobile',
      (tester) async {
    await initializeDesktopWindow();
    final output = Directory('../docs/verification/subscription-expiry');
    await output.create(recursive: true);
    var captures = 0;
    try {
      for (final (size, textSize) in [
        (const Size(1440, 900), AppTextSize.standard),
        (const Size(960, 640), AppTextSize.standard),
        (const Size(960, 640), AppTextSize.extraLarge),
        (const Size(393, 852), AppTextSize.standard),
        (const Size(320, 640), AppTextSize.extraLarge),
      ]) {
        final mobile = size.width < 600;
        debugDefaultTargetPlatformOverride = mobile
            ? size.width == 393
                ? TargetPlatform.iOS
                : TargetPlatform.android
            : TargetPlatform.windows;
        final safe = mobile
            ? size.width == 393
                ? const FakeViewPadding(top: 54, bottom: 34)
                : const FakeViewPadding(top: 24, bottom: 24)
            : const FakeViewPadding();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        tester.view.padding = safe;
        tester.view.viewPadding = safe;
        for (final theme in [AppTheme.dark, AppTheme.light]) {
          for (final density in AppDensity.values) {
            final router = createRouter(initialLocation: '/settings');
            final capture = GlobalKey();
            await tester.pumpWidget(RepaintBoundary(
                key: capture,
                child: ProviderScope(overrides: [
                  ...visualOverrides(theme: theme),
                  initialDeviceSettingsProvider.overrideWithValue(
                      DeviceSettings(
                          appearance: AppearancePreferences(
                              density: density, textSize: textSize),
                          general: GeneralPreferences(
                              subscriptionExpiryNotifications: !mobile))),
                  desktopIntegrationProvider.overrideWith((ref) {
                    if (mobile) return null;
                    final desktop = FakeDesktopIntegration()..tray = true;
                    ref.onDispose(() => unawaited(desktop.dispose()));
                    return desktop;
                  }),
                ], child: RainlinkApp(router: router))));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const ValueKey('settings-general')));
            await tester.pumpAndSettle();
            Future<void> save(String state) async {
              expect(tester.takeException(), isNull);
              await tester.runAsync(() async {
                final boundary = capture.currentContext?.findRenderObject()
                    as RenderRepaintBoundary;
                final rendered = await boundary.toImage(pixelRatio: 1);
                try {
                  final data =
                      await rendered.toByteData(format: ui.ImageByteFormat.png);
                  if (data == null) {
                    throw StateError('Could not encode screenshot');
                  }
                  await File(
                          '${output.path}/$state-${size.width.toInt()}-${textSize.name}-${theme.name}-${density.name}-fixture.png')
                      .writeAsBytes(data.buffer.asUint8List());
                  captures++;
                } finally {
                  rendered.dispose();
                }
              });
            }

            final expiry =
                find.byKey(const ValueKey('subscription-expiry-notifications'));
            if (mobile) {
              expect(expiry, findsNothing);
              expect(
                  find.byKey(const ValueKey('settings-back')), findsOneWidget);
            } else {
              expect(expiry, findsOneWidget);
              await tester.ensureVisible(expiry);
              await tester.pumpAndSettle();
            }
            await save('general');
            if (!mobile) {
              final container = ProviderScope.containerOf(
                  tester.element(find.byType(RainlinkApp)));
              container.read(subscriptionExpiryErrorProvider.notifier).state =
                  '提醒已提交，但记录未保存；请检查本地存储后重试';
              await tester.pumpAndSettle();
              final retry =
                  find.byKey(const ValueKey('retry-subscription-expiry'));
              await tester.ensureVisible(retry);
              await tester.pumpAndSettle();
              expect(retry.hitTestable(), findsOneWidget);
              expect(tester.getSize(retry).height, greaterThanOrEqualTo(40));
              await save('receipt-error');
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            router.dispose();
          }
        }
      }
      expect(captures, 32);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.view.resetPadding();
      tester.view.resetViewPadding();
    }
  });
}
