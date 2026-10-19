import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/core/tun_service_controller.dart';
import 'package:rainlink/application/preferences/desktop_integration_controller.dart';
import 'package:rainlink/application/preferences/device_settings_controller.dart';
import 'package:rainlink/application/preferences/theme_controller.dart';
import 'package:rainlink/domain/core/core_gateway.dart';
import 'package:rainlink/domain/platform/tun_service.dart';
import 'package:rainlink/domain/preferences/device_settings.dart';
import 'package:rainlink/domain/preferences/general_preferences.dart';
import 'package:rainlink/platform/core/unavailable_core_gateway.dart';
import 'package:rainlink/platform/window/desktop_session_guard.dart';

import 'support/fake_tun_service.dart';
import 'support/memory_preferences.dart';

Future<void> _requestClose(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'window_manager',
      const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onEvent', {'eventName': 'close'})),
      (_) {});
  await tester.pumpAndSettle();
}

void main() {
  for (final refused in [false, true]) {
    testWidgets('Linux exit waits for the root operation; refused: $refused',
        (tester) async {
      const channel = MethodChannel('window_manager');
      final calls = <String>[];
      var rejectDestroy = refused;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        calls.add(call.method);
        if (call.method == 'destroy' && rejectDestroy) {
          throw PlatformException(code: 'fixture_destroy_failed');
        }
        return call.method == 'isMinimized' ? false : null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      final service = FakeTunService()
        ..operation = Completer<void>()
        ..failure = const CoreGatewayException('cancelled', '已取消系统授权');
      await tester.pumpWidget(ProviderScope(
          overrides: [
            preferencesRepositoryProvider
                .overrideWithValue(MemoryPreferences()),
            coreGatewayProvider
                .overrideWithValue(const UnavailableCoreGateway('fixture')),
            tunServiceGatewayProvider.overrideWithValue(service),
          ],
          child:
              const MaterialApp(home: DesktopSessionGuard(child: SizedBox()))));
      await tester.pumpAndSettle();
      expect(calls, contains('setPreventClose'));
      final container = ProviderScope.containerOf(
          tester.element(find.byType(DesktopSessionGuard)));
      final controller = container.read(tunServiceControllerProvider.notifier);
      final installing = controller.perform(TunServiceAction.install);
      await _requestClose(tester);
      expect(service.cancellations, 1);
      expect(controller.state.busy, isTrue);
      expect(calls, isNot(contains('destroy')));
      service.operation!.complete();
      await installing;
      await tester.pumpAndSettle();
      expect(calls.where((call) => call == 'destroy'), hasLength(1));
      if (refused) {
        expect(calls, contains('show'));
        expect(container.read(desktopIntegrationNoticeProvider), isNotEmpty);
        service
          ..operation = null
          ..failure = null;
        await controller.perform(TunServiceAction.install);
        expect(service.changes, 2);
        expect(controller.state.status?.state, TunServiceState.current);
        rejectDestroy = false;
        await _requestClose(tester);
        expect(calls.where((call) => call == 'destroy'), hasLength(2));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant({TargetPlatform.linux}));
  }

  for (final platform in [TargetPlatform.linux, TargetPlatform.macOS]) {
    testWidgets('$platform closes safely when a saved tray adapter is absent',
        (tester) async {
      const channel = MethodChannel('window_manager');
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(ProviderScope(
          overrides: [
            preferencesRepositoryProvider
                .overrideWithValue(MemoryPreferences()),
            initialDeviceSettingsProvider.overrideWithValue(
                const DeviceSettings(
                    general: GeneralPreferences(
                        closeBehavior: WindowCloseBehavior.tray))),
            coreGatewayProvider
                .overrideWithValue(const UnavailableCoreGateway('fixture')),
          ],
          child:
              const MaterialApp(home: DesktopSessionGuard(child: SizedBox()))));
      await tester.pumpAndSettle();
      await _requestClose(tester);
      expect(calls, contains('setPreventClose'));
      expect(calls, contains('destroy'));
      expect(calls, isNot(contains('hide')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant({platform}));
  }
}
