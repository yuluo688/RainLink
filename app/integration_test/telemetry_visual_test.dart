import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/app/router.dart';
import 'package:rainlink/application/telemetry/connections_controller.dart';
import 'package:rainlink/application/telemetry/core_log_collector.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/platform/window/desktop_window.dart';

import '../test/support/telemetry_fixture.dart';
import '../test/support/ui_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows renders telemetry pages at compact and Figma sizes',
      (tester) async {
    await initializeDesktopWindow();
    final output = Directory('../docs/verification/telemetry');
    for (final size in [const Size(1440, 900), const Size(960, 640)]) {
      for (final theme in [AppTheme.dark, AppTheme.light]) {
        for (final route in ['/connections', '/logs']) {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          final capture = GlobalKey();
          final gateway = FixtureTelemetryGateway();
          final router = createRouter(initialLocation: route);
          await tester.pumpWidget(RepaintBoundary(
              key: capture,
              child: ProviderScope(overrides: [
                ...visualOverrides(theme: theme),
                connectionsControllerProvider.overrideWith((ref) =>
                    ConnectionsController(gateway)..setSession('visual')),
                coreLogsProvider.overrideWith(
                    (ref) => Stream.value(telemetryFixtureLogs())),
              ], child: RainlinkApp(router: router))));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            final boundary = capture.currentContext?.findRenderObject();
            expect(boundary, isA<RenderRepaintBoundary>());
            final image = await (boundary as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
            try {
              final data =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              expect(data, isNotNull);
              await output.create(recursive: true);
              await File(
                      '${output.path}/${route.substring(1)}-${size.width.toInt()}-${theme.name}-fixture.png')
                  .writeAsBytes(data!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          router.dispose();
        }
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
