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
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/domain/preferences/device_settings.dart';
import 'package:rainlink/platform/window/desktop_window.dart';

import '../test/support/ui_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Windows renderer captures Figma and compact layouts with isolated fixtures',
      (tester) async {
    await initializeDesktopWindow();
    final output = Directory(const String.fromEnvironment(
        'RAINLINK_VISUAL_OUTPUT',
        defaultValue: '../docs/verification/ui-alignment'));
    for (final size in [const Size(1440, 900), const Size(960, 640)]) {
      for (final theme in [AppTheme.dark, AppTheme.light]) {
        final routes = theme == AppTheme.dark
            ? ['/overview', '/traffic', '/nodes', '/groups', '/settings']
            : ['/overview', '/traffic', '/nodes'];
        for (final route in routes) {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          final captureKey = GlobalKey();
          final router = createRouter(initialLocation: route);
          await tester.pumpWidget(RepaintBoundary(
              key: captureKey,
              child: ProviderScope(
                  overrides: visualOverrides(theme: theme),
                  child: RainlinkApp(router: router))));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await _captureScreenshot(tester, captureKey, output,
              '${route.substring(1)}-${size.width.toInt()}-${theme.name}-fixture.png');
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          router.dispose();
        }
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('mobile primary pages render compactly on the Windows renderer',
      (tester) async {
    final output = Directory(const String.fromEnvironment(
        'RAINLINK_VISUAL_OUTPUT',
        defaultValue: '../docs/verification/ui-alignment'));
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    try {
      for (final size in [const Size(393, 852), const Size(320, 640)]) {
        debugDefaultTargetPlatformOverride =
            size.width == 393 ? TargetPlatform.iOS : TargetPlatform.android;
        final safe = size.width == 393
            ? const FakeViewPadding(top: 54, bottom: 34)
            : const FakeViewPadding(top: 24, bottom: 24);
        tester.view.padding = safe;
        tester.view.viewPadding = safe;
        for (final theme in [AppTheme.dark, AppTheme.light]) {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          for (final route in [
            '/overview',
            '/nodes',
            '/groups',
            '/traffic',
            '/settings'
          ]) {
            final captureKey = GlobalKey();
            final router = createRouter(initialLocation: route);
            await tester.pumpWidget(RepaintBoundary(
                key: captureKey,
                child: ProviderScope(
                    overrides: visualOverrides(theme: theme),
                    child: RainlinkApp(router: router))));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await _captureScreenshot(tester, captureKey, output,
                '${route.substring(1)}-mobile-${size.width.toInt()}-${theme.name}-fixture.png');
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            router.dispose();
          }
        }
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPadding();
      tester.view.resetViewPadding();
    }
  });

  testWidgets('mobile enlarged IPv6 and statistics remain accessible',
      (tester) async {
    const ip = '2001:db8:ffff:ffff:ffff:ffff:ffff:ffff';
    final output = Directory(const String.fromEnvironment(
        'RAINLINK_VISUAL_OUTPUT',
        defaultValue: '../docs/verification/ui-alignment'));
    final router = createRouter();
    final capture = GlobalKey();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    try {
      await tester.pumpWidget(RepaintBoundary(
          key: capture,
          child: ProviderScope(overrides: [
            ...visualOverrides(ip: ip),
            initialDeviceSettingsProvider.overrideWithValue(
                const DeviceSettings(
                    appearance: AppearancePreferences(
                        textSize: AppTextSize.extraLarge))),
          ], child: RainlinkApp(router: router))));
      await tester.pumpAndSettle();
      await tester
          .ensureVisible(find.byKey(const ValueKey('overview-outlet-ip')));
      await tester.pumpAndSettle();
      expect(find.text(ip), findsOneWidget);
      await _captureScreenshot(tester, capture, output,
          'overview-mobile-320-large-ipv6-fixture.png');
      await tester
          .ensureVisible(find.byKey(const ValueKey('mobile-traffic-summary')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _captureScreenshot(tester, capture, output,
          'overview-mobile-320-large-summary-fixture.png');
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      router.dispose();
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
      tester.view.resetViewPadding();
    }
  });
}

Future<void> _captureScreenshot(WidgetTester tester, GlobalKey captureKey,
    Directory output, String fileName) async {
  final boundary = captureKey.currentContext?.findRenderObject();
  expect(boundary, isA<RenderRepaintBoundary>());
  await tester.runAsync(() async {
    final image =
        await (boundary as RenderRepaintBoundary).toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Screenshot encoding failed');
      await output.create(recursive: true);
      await File('${output.path}/$fileName')
          .writeAsBytes(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
