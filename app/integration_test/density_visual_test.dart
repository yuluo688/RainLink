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
import 'package:rainlink/application/preferences/device_settings_controller.dart';
import 'package:rainlink/application/preferences/desktop_integration_controller.dart';
import 'package:rainlink/application/routing/routing_providers.dart';
import 'package:rainlink/application/telemetry/connections_controller.dart';
import 'package:rainlink/application/telemetry/core_log_collector.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/domain/preferences/device_settings.dart';
import 'package:rainlink/platform/window/desktop_window.dart';

import '../test/support/fake_desktop_integration.dart';
import '../test/support/routing_fixture.dart';
import '../test/support/telemetry_fixture.dart';
import '../test/support/ui_fixture.dart';

// Native Windows rendering of isolated fixtures. Mobile platform/safe-area and
// keyboard overrides prove layout only, not native mobile network integration.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('density layout and all settings remain reachable',
      (tester) async {
    await initializeDesktopWindow();
    final output = Directory('../docs/verification/density');
    await output.create(recursive: true);
    try {
      for (final (size, theme, textSize) in [
        (const Size(960, 640), AppTheme.dark, AppTextSize.standard),
        (const Size(1440, 900), AppTheme.light, AppTextSize.standard),
        (const Size(393, 852), AppTheme.dark, AppTextSize.standard),
        (const Size(320, 640), AppTheme.light, AppTextSize.extraLarge),
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
        for (final density in AppDensity.values) {
          final router = createRouter(initialLocation: '/nodes');
          final capture = GlobalKey();
          final gateway = FixtureTelemetryGateway();
          await tester.pumpWidget(RepaintBoundary(
              key: capture,
              child: ProviderScope(overrides: [
                ...visualOverrides(theme: theme),
                initialDeviceSettingsProvider.overrideWithValue(DeviceSettings(
                    appearance: AppearancePreferences(
                        density: density, textSize: textSize))),
                desktopIntegrationProvider.overrideWith((ref) {
                  if (mobile) return null;
                  final desktop = FakeDesktopIntegration()..tray = true;
                  ref.onDispose(() => unawaited(desktop.dispose()));
                  return desktop;
                }),
                connectionsControllerProvider.overrideWith((ref) =>
                    ConnectionsController(gateway)..setSession('fixture')),
                coreLogsProvider.overrideWith(
                    (ref) => Stream.value(telemetryFixtureLogs())),
                routeRulesProvider
                    .overrideWith((ref) => Stream.value(routingFixtureRules())),
              ], child: RainlinkApp(router: router))));
          await tester.pumpAndSettle();
          Future<void> screenshot(String state) async {
            expect(tester.takeException(), isNull, reason: state);
            await tester.runAsync(() async {
              final boundary = capture.currentContext?.findRenderObject()
                  as RenderRepaintBoundary;
              final rendered = await boundary.toImage(pixelRatio: 1);
              try {
                final data =
                    await rendered.toByteData(format: ui.ImageByteFormat.png);
                if (data == null) {
                  throw StateError('Screenshot encoding failed');
                }
                await File(
                        '${output.path}/$state-${size.width.toInt()}-${theme.name}-${density.name}-fixture.png')
                    .writeAsBytes(data.buffer.asUint8List());
              } finally {
                rendered.dispose();
              }
            });
          }

          await screenshot('nodes');
          await tester.tap(find.byKey(const ValueKey('add-node')));
          await tester.pumpAndSettle();
          await screenshot('add-node');
          await tester.ensureVisible(find.text('取消').last);
          await tester.tap(find.text('取消').last);
          await tester.pumpAndSettle();
          for (final route in [
            'overview',
            'groups',
            'rules',
            'connections',
            'logs',
            'chain',
          ]) {
            router.go('/$route');
            await tester.pumpAndSettle();
            await screenshot(route);
            if (mobile && (route == 'connections' || route == 'logs')) {
              await tester.ensureVisible(find.byType(ListView).last);
              await tester.pumpAndSettle();
              await screenshot('$route-list');
            }
          }
          router.go('/settings');
          await tester.pumpAndSettle();
          for (final section in [
            'general',
            'appearance',
            'network',
            'core',
            'updates',
            'about',
          ]) {
            final category = find.byKey(ValueKey('settings-$section'));
            await tester.ensureVisible(category);
            await tester.tap(category);
            await tester.pumpAndSettle();
            await screenshot('settings-$section');
            if (section == 'appearance') {
              final selector = find.byKey(const ValueKey('interface-density'));
              await tester.ensureVisible(selector);
              await tester.tap(selector);
              await tester.pumpAndSettle();
              await screenshot('density-menu');
              await tester.tap(find.text(density.label).last);
              await tester.pumpAndSettle();
            }
            if (section == 'core') {
              await tester
                  .ensureVisible(find.byKey(const ValueKey('open-advanced')));
              await tester.tap(find.byKey(const ValueKey('open-advanced')));
              await tester.pumpAndSettle();
              await screenshot('advanced');
              if (mobile) {
                tester.view.viewInsets = const FakeViewPadding(bottom: 280);
                await tester.pumpAndSettle();
                await tester.ensureVisible(
                    find.byKey(const ValueKey('apply-advanced')));
                await tester.pumpAndSettle();
                await screenshot('advanced-keyboard');
                tester.view.resetViewInsets();
                await tester.pumpAndSettle();
              }
              final back = find
                  .byKey(ValueKey(mobile ? 'settings-back' : 'advanced-back'));
              await tester.ensureVisible(back);
              await tester.tap(back);
              await tester.pumpAndSettle();
            }
            if (mobile) {
              final back = find.byKey(const ValueKey('settings-back'));
              await tester.ensureVisible(back);
              await tester.tap(back);
              await tester.pumpAndSettle();
            }
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          router.dispose();
        }
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.view.resetPadding();
      tester.view.resetViewPadding();
      tester.view.resetViewInsets();
    }
  });
}
