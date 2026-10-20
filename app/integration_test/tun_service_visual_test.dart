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
import 'package:rainlink/application/core/tun_service_controller.dart';
import 'package:rainlink/domain/core/core_gateway.dart';
import 'package:rainlink/domain/platform/tun_service.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/features/settings/presentation/widgets/tun_service_panel.dart';
import 'package:rainlink/platform/window/desktop_window.dart';

import '../test/support/fake_tun_service.dart';
import '../test/support/ui_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Linux service management desktop states and dialogs', (
    tester,
  ) async {
    await initializeDesktopWindow();
    final output = Directory(
      const String.fromEnvironment(
        'RAINLINK_VISUAL_OUTPUT',
        defaultValue: '../docs/verification/linux-service-management',
      ),
    );
    await output.create(recursive: true);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      for (final size in [const Size(1440, 900), const Size(960, 640)]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        for (final theme in [AppTheme.dark, AppTheme.light]) {
          final service = FakeTunService();
          final capture = GlobalKey();
          final router = createRouter(initialLocation: '/settings');
          await tester.pumpWidget(
            RepaintBoundary(
              key: capture,
              child: ProviderScope(
                overrides: [
                  ...visualOverrides(theme: theme, connected: false),
                  tunServiceGatewayProvider.overrideWithValue(service),
                ],
                child: RainlinkApp(router: router),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('settings-core')));
          await tester.pumpAndSettle();
          expect(
            Theme.of(tester.element(find.byType(TunServicePanel))).brightness,
            theme == AppTheme.dark ? Brightness.dark : Brightness.light,
          );

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
                  '${output.path}/service-$state-${size.width.toInt()}-${theme.name}-fixture.png',
                ).writeAsBytes(data.buffer.asUint8List());
              } finally {
                rendered.dispose();
              }
            });
          }

          Future<void> showService() async {
            await tester.ensureVisible(
              find.byKey(const ValueKey('tun-service-panel')),
            );
            await tester.pump(const Duration(milliseconds: 200));
          }

          final container = ProviderScope.containerOf(
            tester.element(find.byType(TunServicePanel)),
          );
          final controller = container.read(
            tunServiceControllerProvider.notifier,
          );
          await screenshot('core-page');
          for (final state in TunServiceState.values) {
            service.status = serviceStatus(state);
            await controller.refresh();
            await tester.pumpAndSettle();
            await showService();
            await screenshot(state.name);
          }
          service.status = serviceStatus(TunServiceState.missing);
          await controller.refresh();
          await tester.pumpAndSettle();
          final install = find.byKey(const ValueKey('install-tun-service'));
          await tester.ensureVisible(install);
          await tester.tap(install);
          await tester.pumpAndSettle();
          await screenshot('confirmation');

          service.operation = Completer<void>();
          service.failure = const CoreGatewayException('cancelled', '已取消系统授权');
          await tester.tap(find.widgetWithText(FilledButton, '安装服务'));
          await tester.pump(const Duration(milliseconds: 300));
          await showService();
          expect(container.read(tunServiceControllerProvider).busy, isTrue);
          await screenshot('authorizing');
          final cancel = find.byKey(const ValueKey('cancel-service-operation'));
          await tester.ensureVisible(cancel);
          await tester.tap(cancel);
          await tester.pump(const Duration(milliseconds: 200));
          expect(
            container.read(tunServiceControllerProvider).cancelling,
            isTrue,
          );
          await screenshot('cancelling');
          service.operation!.complete();
          await tester.pumpAndSettle();
          expect(container.read(tunServiceControllerProvider).busy, isFalse);
          expect(find.text('已取消系统授权'), findsOneWidget);
          await showService();
          await screenshot('cancelled');

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          router.dispose();
        }
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
