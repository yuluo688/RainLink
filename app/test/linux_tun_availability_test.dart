import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/app/router.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/core/tun_service_controller.dart';
import 'package:rainlink/application/preferences/theme_controller.dart';
import 'package:rainlink/design_system/theme/rainlink_theme.dart';
import 'package:rainlink/design_system/widgets/rainlink_switch.dart';
import 'package:rainlink/domain/core/core_gateway.dart';
import 'package:rainlink/domain/core/core_status.dart';
import 'package:rainlink/domain/platform/tun_service.dart';
import 'package:rainlink/features/overview/presentation/widgets/overview_cards.dart';
import 'package:rainlink/platform/core/unavailable_core_gateway.dart';

import 'support/fake_tun_service.dart';
import 'support/memory_preferences.dart';

class _ObservedCore extends UnavailableCoreGateway {
  _ObservedCore(this.service) : super('isolated');
  final FakeTunService service;
  int inspections = 0;
  Completer<CoreStatus>? pending;

  @override
  Future<CoreStatus> inspect() async {
    inspections++;
    if (pending case final result?) return result.future;
    final status = service.status;
    return CoreStatus(
      hostAvailable: true,
      message: '隔离测试',
      capabilities: CoreCapabilities(
        connect: true,
        tun:
            service.inspectionFailure == null &&
            status.state == TunServiceState.current &&
            status.active &&
            status.enabled,
      ),
    );
  }
}

class _StoppedService extends FakeTunService {
  @override
  Future<void> change(TunServiceAction action) async {
    await super.change(action);
    status = const TunServiceStatus(
      state: TunServiceState.current,
      canManage: true,
      enabled: true,
      active: false,
      message: '服务未启动',
    );
  }
}

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

  test(
    'install, remove and failed read-back discard cached core readiness',
    () async {
      final service = FakeTunService();
      final core = _ObservedCore(service);
      final container = ProviderContainer(
        overrides: [
          coreGatewayProvider.overrideWithValue(core),
          tunServiceGatewayProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(tunServiceControllerProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      expect(
        (await container.read(coreStatusProvider.future)).capabilities.tun,
        isFalse,
      );
      await controller.perform(TunServiceAction.install);
      expect(
        (await container.read(coreStatusProvider.future)).capabilities.tun,
        isTrue,
      );
      await controller.perform(TunServiceAction.uninstall);
      expect(
        (await container.read(coreStatusProvider.future)).capabilities.tun,
        isFalse,
      );
      await controller.perform(TunServiceAction.install);
      expect(
        (await container.read(coreStatusProvider.future)).capabilities.tun,
        isTrue,
      );
      service.inspectionFailure = const CoreGatewayException(
        'unavailable',
        '检查失败',
      );
      await controller.refresh();
      expect(
        (await container.read(coreStatusProvider.future)).capabilities.tun,
        isFalse,
      );
      expect(container.read(tunServiceControllerProvider).status, isNull);
      expect(core.inspections, 5);
    },
  );

  test(
    'matching files with stopped socket do not confirm installation',
    () async {
      final controller = TunServiceController(
        _StoppedService(),
        canChange: () => true,
        onBusy: (_) {},
      );
      addTearDown(controller.dispose);
      await Future<void>.delayed(Duration.zero);
      await controller.perform(TunServiceAction.install);
      expect(controller.state.message, isEmpty);
      expect(controller.state.error, contains('回读确认'));
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('overview ${brightness.name} updates without restart', (
      tester,
    ) async {
      final service = FakeTunService();
      final core = _ObservedCore(service);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coreGatewayProvider.overrideWithValue(core),
            tunServiceGatewayProvider.overrideWithValue(service),
          ],
          child: MaterialApp(
            theme: buildRainlinkTheme(brightness),
            home: const Scaffold(
              body: OverviewNetworkControlsCard(desktop: true, dense: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OverviewNetworkControlsCard)),
      );
      final controller = container.read(tunServiceControllerProvider.notifier);
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('capture-TUN 模式'));
      expect(tester.widget<RainlinkSwitch>(toggle).onChanged, isNull);
      expect(
        find.byKey(const ValueKey('configure-tun-service')),
        findsOneWidget,
      );
      await controller.perform(TunServiceAction.install);
      await tester.pumpAndSettle();
      expect(tester.widget<RainlinkSwitch>(toggle).onChanged, isNotNull);
      expect(find.byKey(const ValueKey('configure-tun-service')), findsNothing);

      // Old AsyncData can be retained during a refresh. It must not enable a
      // capture switch until the new inspection has actually completed.
      core.pending = Completer<CoreStatus>();
      container.invalidate(coreStatusProvider);
      await tester.pump();
      expect(container.read(coreStatusProvider).isLoading, isTrue);
      await tester.pump();
      expect(tester.widget<RainlinkSwitch>(toggle).onChanged, isNull);
      core.pending!.complete(await _ObservedCore(service).inspect());
      await tester.pumpAndSettle();
      core.pending = null;
      await controller.perform(TunServiceAction.uninstall);
      await tester.pumpAndSettle();
      expect(tester.widget<RainlinkSwitch>(toggle).onChanged, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'service link opens the core category in the existing settings page',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(960, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final service = FakeTunService();
      final router = createRouter(initialLocation: '/settings?section=core');
      final preferences = MemoryPreferences();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coreGatewayProvider.overrideWithValue(_ObservedCore(service)),
            tunServiceGatewayProvider.overrideWithValue(service),
            preferencesRepositoryProvider.overrideWithValue(preferences),
          ],
          child: RainlinkApp(router: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('高级配置'), findsOneWidget);
      expect(find.byKey(const ValueKey('tun-service-panel')), findsOneWidget);
      expect(find.textContaining('尚未开放 Linux'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      router.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
