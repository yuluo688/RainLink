import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/app/router.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/preferences/device_settings_controller.dart';
import 'package:rainlink/application/routing/routing_providers.dart';
import 'package:rainlink/application/telemetry/connections_controller.dart';
import 'package:rainlink/application/telemetry/core_log_collector.dart';
import 'package:rainlink/design_system/widgets/rainlink_icon.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/domain/preferences/device_settings.dart';

import 'support/routing_fixture.dart';
import 'support/telemetry_fixture.dart';
import 'support/ui_fixture.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  setUpAll(() async {
    // Pixel density assertions need the shipped fonts. Ahem assigns a full
    // square to every Latin digit and does not represent the product's layout.
    for (final (family, asset) in [
      ('Inter', 'Inter.ttf'),
      ('Noto Sans SC', 'NotoSansSC.ttf'),
      ('Roboto Mono', 'RobotoMono.ttf'),
    ]) {
      final loader = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/$asset'));
      await loader.load();
    }
  });
  setUp(() => binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => switch (call.method) {
            'isMaximized' => false,
            'isFocused' => true,
            _ => null,
          }));
  tearDown(() =>
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  for (final (size, platform, textSize) in [
    (const Size(1440, 900), TargetPlatform.windows, AppTextSize.standard),
    (const Size(960, 640), TargetPlatform.windows, AppTextSize.standard),
    (const Size(393, 852), TargetPlatform.iOS, AppTextSize.standard),
    (const Size(320, 640), TargetPlatform.android, AppTextSize.extraLarge),
  ]) {
    for (final density in AppDensity.values) {
      for (final theme in [AppTheme.dark, AppTheme.light]) {
        testWidgets('$density $theme at $size fits pages and dialogs',
            (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.reset);
          final router = createRouter(initialLocation: '/nodes');
          final errorHandler = FlutterError.onError;
          FlutterError.onError = (details) {
            debugPrint(details.toString());
            errorHandler?.call(details);
          };
          addTearDown(() => FlutterError.onError = errorHandler);
          final gateway = FixtureTelemetryGateway();
          await tester.pumpWidget(ProviderScope(overrides: [
            ...visualOverrides(theme: theme),
            initialDeviceSettingsProvider.overrideWithValue(DeviceSettings(
                appearance: AppearancePreferences(
                    density: density, textSize: textSize))),
            connectionsControllerProvider.overrideWith(
                (ref) => ConnectionsController(gateway)..setSession('fixture')),
            coreLogsProvider
                .overrideWith((ref) => Stream.value(telemetryFixtureLogs())),
            routeRulesProvider
                .overrideWith((ref) => Stream.value(routingFixtureRules())),
          ], child: RainlinkApp(router: router)));
          await tester.pumpAndSettle();
          final container = ProviderScope.containerOf(
              tester.element(find.byType(RainlinkApp)));
          final original = container.read(sessionControllerProvider).active;
          final row = find.byKey(const ValueKey('node-visual-jp'));
          final expectedHeight = density == AppDensity.compact ? 56.0 : 64.0;
          if (textSize == AppTextSize.standard) {
            expect(tester.getSize(row).height, expectedHeight);
          } else {
            expect(tester.getSize(row).height,
                greaterThanOrEqualTo(expectedHeight));
          }
          final favorite =
              find.byKey(const ValueKey('node-favorite-visual-jp'));
          if (platform == TargetPlatform.iOS ||
              platform == TargetPlatform.android) {
            expect(tester.getSize(favorite).width, greaterThanOrEqualTo(44));
            expect(tester.getSize(favorite).height, greaterThanOrEqualTo(44));
            expect(find.byType(NavigationBar), findsOneWidget);
          }
          final icon = find.descendant(
              of: favorite, matching: find.byType(RainlinkIcon));
          expect(tester.widget<RainlinkIcon>(icon).glyph, RainlinkGlyph.star);
          await tester.tap(find.byKey(const ValueKey('add-node')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'node dialog');
          await tester.ensureVisible(find.text('取消').last);
          await tester.tap(find.text('取消').last);
          await tester.pumpAndSettle();
          for (final route in [
            '/overview',
            '/groups',
            '/rules',
            '/connections',
            '/logs',
            '/traffic',
            '/chain',
            '/settings',
          ]) {
            router.go(route);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: route);
            if (route == '/groups' && platform != TargetPlatform.windows) {
              final groupRect = tester
                  .getRect(find.byKey(const ValueKey('group-visual-main')));
              for (final field in ['usage', 'expiry']) {
                final text = find.byKey(ValueKey('group-$field-visual-main'));
                final paragraph = tester.renderObject<RenderParagraph>(text);
                expect(paragraph.didExceedMaxLines, isFalse,
                    reason: 'Subscription $field must remain readable');
                final textRect = tester.getRect(text);
                expect(textRect.right, lessThanOrEqualTo(groupRect.right));
                expect(textRect.bottom, lessThanOrEqualTo(groupRect.bottom));
              }
              if (textSize == AppTextSize.standard &&
                  density == AppDensity.compact) {
                expect(groupRect.height, lessThanOrEqualTo(80),
                    reason: 'Billing details must retain compact group rows');
              }
            }
          }
          await tester
              .ensureVisible(find.byKey(const ValueKey('settings-appearance')));
          await tester.tap(find.byKey(const ValueKey('settings-appearance')));
          await tester.pumpAndSettle();
          final selector = find.byKey(const ValueKey('interface-density'));
          await tester.ensureVisible(selector);
          final selectorHeight = tester.getSize(selector).height;
          if (platform == TargetPlatform.windows) {
            expect(selectorHeight, density == AppDensity.compact ? 36 : 40);
          } else {
            expect(selectorHeight, greaterThanOrEqualTo(44));
          }
          await tester.tap(selector);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'density menu');
          await tester.tap(find.text(density.label).last);
          await tester.pumpAndSettle();
          expect(
              container.read(sessionControllerProvider).active, same(original));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          router.dispose();
        }, variant: TargetPlatformVariant.only(platform));
      }
    }
  }
}
