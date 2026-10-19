import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/core/tun_service_controller.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/design_system/theme/rainlink_theme.dart';
import 'package:rainlink/domain/platform/tun_service.dart';
import 'package:rainlink/features/settings/presentation/widgets/tun_service_panel.dart';
import 'package:rainlink/platform/core/unavailable_core_gateway.dart';

import 'support/fake_tun_service.dart';

void main() {
  testWidgets('other platforms do not expose Linux service controls',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: TunServicePanel()))));
    expect(find.byKey(const ValueKey('tun-service-panel')), findsNothing);
  });

  testWidgets('unknown service state does not claim the service is stopped',
      (tester) async {
    final gateway = FakeTunService()
      ..status = serviceStatus(TunServiceState.incomplete);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          tunServiceGatewayProvider.overrideWithValue(gateway),
          coreGatewayProvider
              .overrideWithValue(const UnavailableCoreGateway('fixture')),
        ],
        child: MaterialApp(
            theme: buildRainlinkTheme(Brightness.dark),
            home: const Scaffold(body: TunServicePanel()))));
    await tester.pumpAndSettle();
    expect(find.text('服务文件不完整或无法验证，可尝试恢复安装'), findsOneWidget);
    expect(find.textContaining('服务未启动'), findsNothing);
    expect(find.textContaining('未设为开机启用'), findsNothing);

    gateway.status = serviceStatus(TunServiceState.current);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(TunServicePanel)));
    await container.read(tunServiceControllerProvider.notifier).refresh();
    await tester.pumpAndSettle();
    expect(find.text('服务已启动 · 开机启用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 640.0]) {
      testWidgets(
          'service card ${brightness.name} at $width handles large text',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final gateway = FakeTunService();
        await tester.pumpWidget(ProviderScope(
            overrides: [
              tunServiceGatewayProvider.overrideWithValue(gateway),
              coreGatewayProvider
                  .overrideWithValue(const UnavailableCoreGateway('fixture')),
            ],
            child: MaterialApp(
                theme: buildRainlinkTheme(brightness),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: const TextScaler.linear(1.5)),
                    child: child!),
                home: const Scaffold(
                    body: SingleChildScrollView(child: TunServicePanel())))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('install-tun-service')));
        await tester.pumpAndSettle();
        expect(find.text('安装服务？'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(gateway.changes, 0);
        expect(tester.takeException(), isNull);
        gateway.status = serviceStatus(TunServiceState.current);
        final container = ProviderScope.containerOf(
            tester.element(find.byType(TunServicePanel)));
        await container.read(tunServiceControllerProvider.notifier).refresh();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('install-tun-service')), findsNothing);
        expect(find.byKey(const ValueKey('uninstall-tun-service')),
            findsOneWidget);
      });
    }
  }
}
