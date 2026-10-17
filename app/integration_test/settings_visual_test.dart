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
import 'package:rainlink/domain/core/runtime_settings.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/domain/preferences/device_settings.dart';
import 'package:rainlink/platform/window/desktop_window.dart';
import '../test/support/ui_fixture.dart';
import '../test/support/fake_desktop_integration.dart';

class _VisualSettings implements RuntimeSettingsGateway {
  @override
  Future<void> validateRuntime(CoreRuntimeSettings settings) async {}
  @override
  Future<DnsTestResult> testDns(CoreRuntimeSettings settings) async =>
      const DnsTestResult(addresses: ['203.0.113.88'], latency: 12);
  @override
  Future<void> cancelDnsTest() async {}
  @override
  Future<void> cancelValidation() async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('all settings sections fit desktop and mobile themes',
      (tester) async {
    await initializeDesktopWindow();
    final output = Directory('../docs/verification/settings');
    await output.create(recursive: true);
    try {
      for (final (size, textSize) in [
        (const Size(1440, 900), AppTextSize.standard),
        (const Size(960, 640), AppTextSize.standard),
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
        tester.view.padding = safe;
        tester.view.viewPadding = safe;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        for (final theme in [AppTheme.dark, AppTheme.light]) {
          final router = createRouter(initialLocation: '/settings');
          final capture = GlobalKey();
          await tester.pumpWidget(RepaintBoundary(
              key: capture,
              child: ProviderScope(overrides: [
                ...visualOverrides(theme: theme),
                desktopIntegrationProvider.overrideWith((ref) {
                  if (mobile) return null;
                  final desktop = FakeDesktopIntegration()..tray = true;
                  ref.onDispose(() => unawaited(desktop.dispose()));
                  return desktop;
                }),
                initialDeviceSettingsProvider.overrideWithValue(DeviceSettings(
                    appearance: AppearancePreferences(textSize: textSize),
                    runtime:
                        const CoreRuntimeSettings(dnsMode: DnsMode.encrypted))),
                runtimeSettingsGatewayProvider
                    .overrideWithValue(_VisualSettings()),
              ], child: RainlinkApp(router: router))));
          await tester.pumpAndSettle();
          Future<void> screenshot(String state) async {
            expect(tester.takeException(), isNull);
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
                        '${output.path}/settings-$state-${size.width.toInt()}-${theme.name}-fixture.png')
                    .writeAsBytes(data.buffer.asUint8List());
              } finally {
                rendered.dispose();
              }
            });
          }

          if (mobile) await screenshot('home');
          for (final section in [
            'general',
            'appearance',
            'network',
            'core',
            'updates',
            'about'
          ]) {
            final category = find.byKey(ValueKey('settings-$section'));
            if (category.hitTestable().evaluate().isEmpty) {
              await tester.ensureVisible(category);
            }
            await tester.tap(category);
            await tester.pumpAndSettle();
            await screenshot(section);
            if (section == 'core') {
              await tester
                  .ensureVisible(find.byKey(const ValueKey('open-advanced')));
              await tester.tap(find.byKey(const ValueKey('open-advanced')));
              await tester.pumpAndSettle();
              await tester.enterText(
                  find.byKey(const ValueKey('advanced-editor')),
                  '# RainLink 高级配置\nlog:\n  level: info\ndns:\n  servers:\n    - type: https\n      server: dns.alidns.com');
              final back = find
                  .byKey(ValueKey(mobile ? 'settings-back' : 'advanced-back'));
              await tester.ensureVisible(back);
              await tester.pumpAndSettle();
              await screenshot('advanced');
              await tester.ensureVisible(
                  find.byKey(const ValueKey('validate-advanced')));
              await tester.tap(find.byKey(const ValueKey('validate-advanced')));
              await tester.pumpAndSettle();
              await screenshot('advanced-validated');
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
              await tester.ensureVisible(back);
              await tester.tap(back);
              await tester.pumpAndSettle();
            }
            if (section == 'network') {
              await tester
                  .ensureVisible(find.byKey(const ValueKey('mixed-port')));
              await tester.pumpAndSettle();
              await screenshot('network-listening');
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
