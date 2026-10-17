import 'dart:convert';
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
import 'package:rainlink/application/preferences/mobile_integration_controller.dart';
import '../test/support/fake_mobile_integration.dart';

import '../test/support/ui_fixture.dart';
import '../test/support/telemetry_fixture.dart';
import 'android_telemetry_test.dart' as telemetry;
import 'android_startup_test.dart' as startup;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android renders the primary pages with isolated visual fixtures',
      (tester) async {
    expect(Platform.isAndroid, isTrue);
    final captures = <Map<String, Object?>>[];
    for (final theme in [AppTheme.dark, AppTheme.light]) {
      for (final route in [
        '/overview',
        '/nodes',
        '/groups',
        '/traffic',
        '/settings',
        '/settings-general',
        '/connections',
        '/logs',
      ]) {
        final router = createRouter(
            initialLocation:
                route == '/settings-general' ? '/settings' : route);
        final mobile = FakeMobileIntegration();
        final capture = GlobalKey();
        try {
          await tester.pumpWidget(RepaintBoundary(
              key: capture,
              child: ProviderScope(overrides: [
                ...visualOverrides(theme: theme, mobileTunnel: true),
                mobileIntegrationProvider.overrideWithValue(mobile),
                connectionsControllerProvider.overrideWith((ref) =>
                    ConnectionsController(FixtureTelemetryGateway())
                      ..setSession('visual')),
                coreLogsProvider.overrideWith(
                    (ref) => Stream.value(telemetryFixtureLogs())),
              ], child: RainlinkApp(router: router))));
          await tester.pumpAndSettle();
          if (route == '/settings-general') {
            await tester.tap(find.byKey(const ValueKey('settings-general')));
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('auto-connect')), findsOneWidget);
            expect(find.byKey(const ValueKey('connection-notifications')),
                findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          if (route == '/overview') {
            final summary = tester
                .getRect(find.byKey(const ValueKey('mobile-traffic-summary')));
            expect(summary.bottom,
                lessThan(tester.getRect(find.byType(NavigationBar)).top));
            expect(
                tester
                    .getSize(find.byKey(const ValueKey('connect-button')))
                    .shortestSide,
                greaterThanOrEqualTo(72));
          }
          final file = '${route.substring(1)}-${theme.name}-fixture.png';
          await tester.runAsync(() async {
            final boundary = capture.currentContext?.findRenderObject();
            if (boundary is! RenderRepaintBoundary) {
              throw StateError('Missing capture boundary');
            }
            final rendered = await boundary.toImage(pixelRatio: 1);
            try {
              final png =
                  await rendered.toByteData(format: ui.ImageByteFormat.png);
              if (png == null) throw StateError('Screenshot encoding failed');
              captures.add({
                'route': route,
                'theme': theme.name,
                'file': file,
                'width': rendered.width,
                'height': rendered.height,
                'png': base64Encode(png.buffer.asUint8List()),
              });
            } finally {
              rendered.dispose();
            }
          });
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          router.dispose();
          mobile.dispose();
        }
      }
    }
    binding.reportData = {
      'scope':
          'Android renderer with isolated UI fixtures; no real network values',
      'captures': captures,
    };
  });
  telemetry.main();
  startup.main();
}
