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
import 'package:rainlink/application/routing/routing_providers.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/platform/window/desktop_window.dart';
import '../test/support/ui_fixture.dart';
import '../test/support/routing_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('rules render at desktop and mobile sizes in both themes',
      (tester) async {
    await initializeDesktopWindow();
    final output = Directory('../docs/verification/routing');
    for (final size in [
      const Size(1440, 900),
      const Size(960, 640),
      const Size(393, 852)
    ]) {
      for (final theme in [AppTheme.dark, AppTheme.light]) {
        final mobile = size.width < 600;
        debugDefaultTargetPlatformOverride =
            mobile ? TargetPlatform.android : TargetPlatform.windows;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        final capture = GlobalKey();
        final router = createRouter(initialLocation: '/rules');
        await tester.pumpWidget(RepaintBoundary(
            key: capture,
            child: ProviderScope(overrides: [
              ...visualOverrides(theme: theme),
              routeRulesProvider
                  .overrideWith((ref) => Stream.value(routingFixtureRules())),
            ], child: RainlinkApp(router: router))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        Future<void> screenshot(String state) async {
          await tester.runAsync(() async {
            final boundary = capture.currentContext?.findRenderObject()
                as RenderRepaintBoundary;
            final rendered = await boundary.toImage(pixelRatio: 1);
            try {
              final data =
                  await rendered.toByteData(format: ui.ImageByteFormat.png);
              await output.create(recursive: true);
              await File(
                      '${output.path}/rules-$state-${size.width.toInt()}-${theme.name}-fixture.png')
                  .writeAsBytes(data!.buffer.asUint8List());
            } finally {
              rendered.dispose();
            }
          });
        }

        await screenshot('list');
        await tester.tap(find.byKey(const ValueKey('add-rule')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await screenshot('editor');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        router.dispose();
      }
    }
    debugDefaultTargetPlatformOverride = null;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
