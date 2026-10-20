import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/app/router.dart';
import 'package:rainlink/application/telemetry/connections_controller.dart';
import 'package:rainlink/domain/core/core_gateway.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';

import 'support/telemetry_fixture.dart';
import 'support/ui_fixture.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const windowChannel = MethodChannel('window_manager');
  setUp(
    () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      (call) async => switch (call.method) {
        'isMaximized' => false,
        'isFocused' => true,
        _ => null,
      },
    ),
  );
  tearDown(
    () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      null,
    ),
  );

  for (final size in [const Size(960, 640), const Size(1440, 900)]) {
    for (final theme in [AppTheme.dark, AppTheme.light]) {
      testWidgets(
        'recent connection fits $size ${theme.name} and opens full list',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final router = createRouter();
          final gateway = FixtureTelemetryGateway();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                ...visualOverrides(theme: theme),
                connectionsControllerProvider.overrideWith(
                  (ref) => ConnectionsController(gateway)..setSession('visual'),
                ),
              ],
              child: RainlinkApp(router: router),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.textContaining('api.github.com:443 · 代理'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.tap(
            find.byKey(const ValueKey('overview-all-connections')),
          );
          await tester.pumpAndSettle();
          expect(find.text('api.github.com:443'), findsOneWidget);
          expect(find.text('关闭全部'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          router.dispose();
        },
        variant: TargetPlatformVariant.only(TargetPlatform.linux),
      );
    }
  }

  testWidgets(
    'overview polling pauses in background and stops when leaving page',
    (tester) async {
      final router = createRouter();
      final gateway = FixtureTelemetryGateway();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...visualOverrides(),
            connectionsControllerProvider.overrideWith(
              (ref) => ConnectionsController(gateway)..setSession('visual'),
            ),
          ],
          child: RainlinkApp(router: router),
        ),
      );
      await tester.pumpAndSettle();
      final initial = gateway.reads;
      await tester.pump(const Duration(seconds: 1));
      expect(gateway.reads, greaterThan(initial));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      final hidden = gateway.reads;
      await tester.pump(const Duration(seconds: 3));
      expect(gateway.reads, hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(gateway.reads, greaterThan(hidden));
      router.go('/nodes');
      await tester.pumpAndSettle();
      final inactive = gateway.reads;
      await tester.pump(const Duration(seconds: 3));
      expect(gateway.reads, inactive);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      router.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'overview reports empty and failed reads without stale success',
    (tester) async {
      final router = createRouter();
      final gateway = FixtureTelemetryGateway()..entries.clear();
      final controller = ConnectionsController(gateway)..setSession('visual');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...visualOverrides(),
            connectionsControllerProvider.overrideWith((ref) => controller),
          ],
          child: RainlinkApp(router: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('等待网络请求'), findsOneWidget);
      gateway.onConnections =
          (_) => Future.error(
            const CoreGatewayException('unavailable', '核心连接读取失败'),
          );
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(find.text('读取失败，打开连接页重试'), findsOneWidget);
      expect(find.textContaining('api.github.com'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      router.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
