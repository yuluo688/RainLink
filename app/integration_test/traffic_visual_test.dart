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
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/platform/window/desktop_window.dart';
import '../test/support/ui_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('persistent traffic fits desktop and mobile in both themes',
      (tester) async {
    await initializeDesktopWindow();
    final output = Directory('../docs/verification/traffic');
    await output.create(recursive: true);
    try {
      for (final size in [
        const Size(1440, 900),
        const Size(960, 640),
        const Size(393, 852)
      ]) {
        debugDefaultTargetPlatformOverride =
            size.width < 600 ? TargetPlatform.android : TargetPlatform.windows;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        for (final theme in [AppTheme.dark, AppTheme.light]) {
          final router = createRouter(initialLocation: '/traffic');
          final capture = GlobalKey();
          await tester.pumpWidget(RepaintBoundary(
              key: capture,
              child: ProviderScope(
                  overrides: visualOverrides(theme: theme),
                  child: RainlinkApp(router: router))));
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
                        '${output.path}/traffic-$state-${size.width.toInt()}-${theme.name}-fixture.png')
                    .writeAsBytes(data.buffer.asUint8List());
              } finally {
                rendered.dispose();
              }
            });
          }

          for (final (name, label) in [
            ('today', '今日'),
            ('week', '本周'),
            ('month', '本月')
          ]) {
            await tester.tap(find.text(label));
            await tester.pumpAndSettle();
            await screenshot(name);
          }
          await tester.tap(find.text('今日'));
          await tester.pumpAndSettle();
          final plot = find.byKey(const ValueKey('traffic-chart-plot'));
          await tester.ensureVisible(plot);
          await tester.tap(plot);
          await tester.pumpAndSettle();
          await screenshot('selected');
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          router.dispose();
        }
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    }
  });
}
