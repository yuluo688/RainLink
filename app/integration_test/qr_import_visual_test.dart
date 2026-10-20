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
import 'package:rainlink/application/import/qr_import_providers.dart';
import 'package:rainlink/data/import/qr_import_parser.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/features/nodes/presentation/node_editor_dialog.dart';
import 'package:rainlink/features/nodes/presentation/qr_import_dialog.dart';
import 'package:rainlink/platform/qr/qr_camera_session.dart';
import 'package:rainlink/platform/window/desktop_window.dart';

import '../test/support/qr_fixtures.dart';
import '../test/support/ui_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('import and camera states fit desktop/mobile in both themes', (
    tester,
  ) async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    await initializeDesktopWindow();
    final output = Directory(
      const String.fromEnvironment(
        'RAINLINK_VISUAL_OUTPUT',
        defaultValue: '../docs/verification/qr-import/visual',
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
        final mobile = size.width < 600;
        debugDefaultTargetPlatformOverride =
            mobile ? TargetPlatform.android : TargetPlatform.windows;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        for (final theme in [AppTheme.dark, AppTheme.light]) {
          final router = createRouter(initialLocation: '/groups');
          final capture = GlobalKey();
          FixtureQrCamera? camera;
          var status = QrCameraStatus.permissionDenied;
          await tester.pumpWidget(
            RepaintBoundary(
              key: capture,
              child: ProviderScope(
                overrides: [
                  ...visualOverrides(theme: theme),
                  qrImportParserProvider.overrideWithValue(
                    const StandardQrImportParser(),
                  ),
                  qrCameraFactoryProvider.overrideWithValue(
                    mobile
                        ? () {
                          return camera = FixtureQrCamera(
                            initialStatus: status,
                          );
                        }
                        : null,
                  ),
                ],
                child: RainlinkApp(router: router),
              ),
            ),
          );
          await tester.pumpAndSettle();
          Future<void> shot(String name) async {
            expect(tester.takeException(), isNull);
            expect(
              Theme.of(
                tester.element(find.byType(NodeEditorDialog)),
              ).brightness,
              theme == AppTheme.dark ? Brightness.dark : Brightness.light,
            );
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
                  '${output.path}/import-${size.width.toInt()}-${theme.name}-$name-fixture.png',
                ).writeAsBytes(data.buffer.asUint8List());
              } finally {
                rendered.dispose();
              }
            });
          }

          await tester.tap(find.text('添加订阅'));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('save-node')).hitTestable(),
            findsOneWidget,
          );
          await shot('subscription');
          if (mobile) {
            final entry = find.byKey(const ValueKey('scan-import'));
            await tester.ensureVisible(entry);
            expect(tester.getSize(entry).height, greaterThanOrEqualTo(44));
            await tester.tap(entry);
            await tester.pumpAndSettle();
            expect(find.textContaining('未获得相机权限'), findsOneWidget);
            final back = find.byKey(const ValueKey('qr-back'));
            expect(tester.getSize(back).height, greaterThanOrEqualTo(44));
            expect(
              tester.getCenter(back).dx,
              lessThan(tester.getCenter(find.text('扫码导入').hitTestable()).dx),
            );
            await shot('camera-denied');
            await tester.tap(find.byKey(const ValueKey('qr-retry')));
            await tester.pumpAndSettle();
            await shot('camera-scanning');
            camera?.capture(['invalid-private-fixture']);
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('qr-error')), findsOneWidget);
            await shot('camera-invalid');
            await tester.tap(back);
            await tester.pumpAndSettle();
            status = QrCameraStatus.scanning;
            await tester.tap(entry);
            await tester.pumpAndSettle();
            camera?.capture([
              'https://provider.example.test/sub?token=fixture',
            ]);
            await tester.pumpAndSettle();
            expect(find.byType(QrImportDialog), findsNothing);
            expect(
              find.byKey(const ValueKey('import-preview-notice')),
              findsOneWidget,
            );
            await shot('subscription-preview');
          } else {
            expect(find.byKey(const ValueKey('scan-import')), findsNothing);
          }
          await tester.tap(find.text('单个节点'));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('paste-node-link')), findsOneWidget);
          await shot('manual-node');
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
  });
}
