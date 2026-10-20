import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/app/router.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/preferences/theme_controller.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/export/data_export.dart';
import 'package:rainlink/platform/core/unavailable_core_gateway.dart';
import 'package:rainlink/platform/export/file_data_export_service.dart';
import 'support/memory_preferences.dart';
import 'support/ui_fixture.dart';

class _Export implements DataExportService {
  String content = '';
  Completer<String?>? result;
  bool fail = false;
  @override
  Future<String?> save({
    required String suggestedName,
    required String content,
  }) async {
    this.content = content;
    if (fail) throw const FormatException('fixture failure');
    return result?.future ?? 'fixture.csv';
  }
}

class _CountingSession extends SessionController {
  _CountingSession()
    : super(const UnavailableCoreGateway('test'), onMode: (_) {}) {
    state = const SessionView(phase: ConnectionPhase.connected);
  }
  int refreshes = 0;
  @override
  Future<void> refresh() async {
    refreshes++;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => call.method == 'isFocused',
    ),
  );
  tearDown(
    () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      null,
    ),
  );
  for (final (platform, size, scale) in [
    (TargetPlatform.windows, const Size(960, 640), 1.0),
    (TargetPlatform.android, const Size(393, 852), 1.0),
    (TargetPlatform.android, const Size(320, 740), 1.3),
  ]) {
    testWidgets(
      'traffic period, chart and frozen CSV fit $size at $scale',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final exporting = _Export();
        final router = createRouter(initialLocation: '/traffic');
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...visualOverrides(),
              dataExportServiceProvider.overrideWithValue(exporting),
            ],
            child: RainlinkApp(router: router),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('总流量 · 当前周期'),
          platform == TargetPlatform.android ? findsOneWidget : findsNothing,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('traffic-ranking-dimension')),
        );
        await tester.tap(find.text('出站'));
        await tester.pumpAndSettle();
        expect(find.textContaining('东京 · 樱花'), findsWidgets);
        await tester.tap(find.text('应用'));
        await tester.pumpAndSettle();
        expect(find.textContaining('未识别应用'), findsOneWidget);
        expect(tester.takeException(), isNull);
        for (final label in ['本周', '本月', '今日']) {
          await tester.ensureVisible(find.text(label));
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        final plot = find.byKey(const ValueKey('traffic-chart-plot'));
        await tester.ensureVisible(plot);
        await tester.tap(plot);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('traffic-chart-detail')),
          findsOneWidget,
        );
        final export = find.byKey(
          ValueKey(
            platform == TargetPlatform.windows
                ? 'export-traffic'
                : 'export-traffic-mobile',
          ),
        );
        await tester.ensureVisible(export);
        exporting.result = Completer<String?>();
        await tester.tap(export);
        await tester.pumpAndSettle();
        final saved = exporting.content;
        await tester.tap(find.text('本月'));
        await tester.pumpAndSettle();
        expect(exporting.content, saved);
        expect(saved, contains('日汇总'));
        expect(saved, contains('时段明细'));
        expect(saved, contains('周期归属'));
        exporting.result?.complete(null);
        await tester.pumpAndSettle();
        expect(find.text('已导出当前周期流量'), findsNothing);
        exporting.result = null;
        exporting.fail = true;
        await tester.tap(export);
        await tester.pumpAndSettle();
        expect(find.text('导出失败，请检查保存位置和磁盘空间'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
  testWidgets(
    'session sampling continues on nodes/traffic and pauses with app lifecycle',
    (tester) async {
      final session = _CountingSession();
      final router = createRouter(initialLocation: '/overview');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesRepositoryProvider.overrideWithValue(
              MemoryPreferences(),
            ),
            coreGatewayProvider.overrideWithValue(
              const UnavailableCoreGateway('test'),
            ),
            sessionControllerProvider.overrideWith((_) => session),
          ],
          child: RainlinkApp(router: router),
        ),
      );
      await tester.pumpAndSettle();
      for (final path in ['/nodes', '/traffic']) {
        router.go(path);
        await tester.pumpAndSettle();
        final before = session.refreshes;
        await tester.pump(const Duration(seconds: 3));
        expect(session.refreshes, greaterThan(before));
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final paused = session.refreshes;
      await tester.pump(const Duration(seconds: 4));
      expect(session.refreshes, paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(session.refreshes, greaterThan(paused));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      router.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
