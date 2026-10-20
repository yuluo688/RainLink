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
import 'package:rainlink/domain/connection/traffic_history.dart';
import 'package:rainlink/domain/connection/traffic_repository.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/platform/window/desktop_window.dart';
import '../test/support/ui_fixture.dart';

TrafficArchive _archive() {
  final now = DateTime.now();
  final day = trafficDayKey(now);
  const up = 587202560, down = 8439610736;
  TrafficUsage usage(String id, String name, String kind, int weight) =>
      TrafficUsage(
        day: day,
        target: TrafficAttribution(id: id, name: name, kind: kind),
        upload: up * weight ~/ 100,
        download: down * weight ~/ 100,
      );
  final applications = [
    usage('browser', 'chrome.exe', 'application', 50),
    usage('editor', 'Code.exe', 'application', 30),
    usage('terminal', 'pwsh.exe', 'application', 15),
  ];
  final targets = [
    usage('node', '东京 · 樱花', 'node', 60),
    usage('direct', '直连', 'direct', 20),
  ];
  final buckets = <TrafficBucket>[];
  final count = (now.hour * 60 + now.minute) ~/ trafficBucketMinutes + 1;
  final weights = [for (var i = 0; i < count; i++) 4 + i % 7];
  final totalWeight = weights.fold(0, (sum, n) => sum + n);
  var usedUp = 0, usedDown = 0;
  for (var i = 0; i < count; i++) {
    final partUp =
        i == count - 1 ? up - usedUp : up * weights[i] ~/ totalWeight;
    final partDown =
        i == count - 1 ? down - usedDown : down * weights[i] ~/ totalWeight;
    buckets.add(
      TrafficBucket(day: day, slot: i, upload: partUp, download: partDown),
    );
    usedUp += partUp;
    usedDown += partDown;
  }
  return TrafficArchive(
    days: [
      TrafficDay(
        day: DateTime(now.year, now.month, now.day),
        upload: up,
        download: down,
      ),
    ],
    buckets: buckets,
    usage: [
      ...targets,
      TrafficUsage(
        day: day,
        target: const TrafficAttribution(
          id: 'chain',
          name: '工作代理链',
          kind: 'chain',
        ),
        upload: up - targets.fold(0, (sum, row) => sum + row.upload),
        download: down - targets.fold(0, (sum, row) => sum + row.download),
      ),
      ...applications,
      TrafficUsage(
        day: day,
        target: TrafficAttribution.unknownApplication,
        upload: up - applications.fold(0, (sum, row) => sum + row.upload),
        download: down - applications.fold(0, (sum, row) => sum + row.download),
      ),
    ],
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'accounting partitions fit both themes, small desktop and large-text mobile',
    (tester) async {
      WidgetController.hitTestWarningShouldBeFatal = true;
      await initializeDesktopWindow();
      final output = Directory(
        const String.fromEnvironment(
          'RAINLINK_VISUAL_OUTPUT',
          defaultValue: '../docs/verification/traffic-accounting/visual',
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
          debugDefaultTargetPlatformOverride =
              size.width < 600
                  ? TargetPlatform.android
                  : Platform.isLinux
                  ? TargetPlatform.linux
                  : TargetPlatform.windows;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          for (final theme in [AppTheme.dark, AppTheme.light]) {
            final router = createRouter(initialLocation: '/traffic');
            final capture = GlobalKey();
            await tester.pumpWidget(
              RepaintBoundary(
                key: capture,
                child: ProviderScope(
                  overrides: visualOverrides(
                    theme: theme,
                    trafficArchive: _archive(),
                  ),
                  child: RainlinkApp(router: router),
                ),
              ),
            );
            await tester.pumpAndSettle();
            Future<void> screenshot(String state) async {
              expect(tester.takeException(), isNull);
              await tester.runAsync(() async {
                final boundary =
                    capture.currentContext?.findRenderObject()
                        as RenderRepaintBoundary;
                final rendered = await boundary.toImage(pixelRatio: 1);
                try {
                  final data = await rendered.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  if (data == null) {
                    throw StateError('Screenshot encoding failed');
                  }
                  await File(
                    '${output.path}/traffic-${size.width.toInt()}-${theme.name}-$state-fixture.png',
                  ).writeAsBytes(data.buffer.asUint8List());
                } finally {
                  rendered.dispose();
                }
              });
            }

            await screenshot('initial');
            if (size.width == 960) {
              expect(
                find.textContaining('未识别应用').hitTestable(),
                findsOneWidget,
                reason:
                    'Compact desktop must show the complete fixture ranking',
              );
            }
            final selector = find.byKey(
              const ValueKey('traffic-ranking-dimension'),
            );
            await tester.ensureVisible(selector);
            for (final (name, label) in [
              ('target', '出站'),
              ('application', '应用'),
            ]) {
              await tester.tap(
                find.descendant(of: selector, matching: find.text(label)),
              );
              await tester.pumpAndSettle();
              expect(
                find.textContaining(
                  name == 'target' ? '东京 · 樱花' : 'chrome.exe',
                ),
                findsWidgets,
              );
              await screenshot(name);
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
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        WidgetController.hitTestWarningShouldBeFatal = false;
      }
    },
  );
}
