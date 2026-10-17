import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/chains/chain_providers.dart';
import 'package:rainlink/application/connection/connection_providers.dart';
import 'package:rainlink/application/connection/mobile_startup_controller.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/application/preferences/device_settings_controller.dart';
import 'package:rainlink/application/preferences/mobile_integration_controller.dart';
import 'package:rainlink/application/preferences/theme_controller.dart';
import 'package:rainlink/application/updates/app_update_controller.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/core/core_status.dart';
import 'package:rainlink/domain/core/runtime_settings.dart';
import 'package:rainlink/domain/core/session_gateway.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/preferences/device_settings.dart';
import 'package:rainlink/domain/preferences/general_preferences.dart';
import 'package:rainlink/platform/notifications/android_mobile_integration.dart';
import 'support/fake_mobile_integration.dart';
import 'support/memory_preferences.dart';

const _node = ProxyNode(
    id: 'mobile-startup',
    name: '本地测试',
    protocol: NodeProtocol.http,
    server: '127.0.0.1',
    port: 9);

class _Core implements SessionGateway, SessionRecoveryGateway {
  final requests = <ConnectRequest>[];
  Completer<RecoveredSession>? recovery;
  ActiveConnectionSnapshot? active;
  @override
  Stream<Exception> get failures => const Stream.empty();
  @override
  Future<CoreStatus> inspect() async => const CoreStatus(
      hostAvailable: true,
      message: 'ready',
      capabilities:
          CoreCapabilities(connect: true, tun: true, requiresTun: true));
  @override
  Future<RecoveredSession> recoverSession() async => recovery == null
      ? RecoveredSession(await observe(), null)
      : recovery!.future;
  @override
  Future<SessionObservation> observe() async => SessionObservation(
      phase: active == null ? ConnectionPhase.idle : ConnectionPhase.connected,
      active: active,
      tun: true);
  @override
  Future<ActiveConnectionSnapshot> connect(ConnectRequest request) async {
    requests.add(request);
    return active = ActiveConnectionSnapshot(
        sessionId: 'mobile-session',
        target: request.target,
        mode: request.mode,
        configRevision: 'fixture');
  }

  @override
  Future<void> disconnect() async {
    active = null;
  }

  @override
  Future<void> setMode(ProxyMode mode) async {}
  @override
  Future<void> setSystemProxy(bool enabled) async {}
  @override
  Future<void> probe() async {}
  @override
  Future<void> cancel() async {}
  @override
  Future<void> close() async {}
  @override
  void dispose() {}
}

ProviderContainer _container(_Core core, FakeMobileIntegration mobile,
    {bool autoConnect = true,
    Future<void>? ready,
    MemoryPreferences? preferences}) {
  final settings = DeviceSettings(
      general: GeneralPreferences(autoConnect: autoConnect),
      connection: const ConnectionPreferences(mode: ProxyMode.global));
  final container = ProviderContainer(overrides: [
    coreGatewayProvider.overrideWithValue(core),
    mobileIntegrationProvider.overrideWithValue(mobile),
    initialDeviceSettingsProvider.overrideWithValue(settings),
    requiredTunnelProvider.overrideWithValue(true),
    if (ready != null) startupReadyProvider.overrideWithValue(ready),
    preferencesRepositoryProvider
        .overrideWithValue(preferences ?? MemoryPreferences()),
    nodesProvider.overrideWith((ref) => Stream.value([_node])),
    selectedNodeIdProvider.overrideWith((ref) => Stream.value(_node.id)),
    chainsProvider.overrideWith((ref) => Stream.value(const [])),
    selectedChainIdProvider.overrideWith((ref) => Stream.value(null)),
  ]);
  addTearDown(container.dispose);
  addTearDown(mobile.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('startup waits for recovery, uses saved mode and connects only once',
      () async {
    final core = _Core()..recovery = Completer<RecoveredSession>();
    final mobile = FakeMobileIntegration();
    final container = _container(core, mobile);
    final startup = container.read(mobileStartupControllerProvider);
    final starting = startup.start(isForeground: () => true);
    await Future<void>.delayed(Duration.zero);
    expect(core.requests, isEmpty);
    core.recovery!.complete(const RecoveredSession(
        SessionObservation(phase: ConnectionPhase.idle), null));
    await starting;
    expect(core.requests.single.mode, ProxyMode.global);
    expect(core.requests.single.tun, isTrue);
    expect(core.requests.single.systemProxy, isFalse);
    await container.read(sessionControllerProvider.notifier).disconnect();
    await startup.start(isForeground: () => true);
    expect(core.requests, hasLength(1));
    expect(
        container.read(sessionControllerProvider).phase, ConnectionPhase.idle);
  });

  test(
      'existing native session is restored without reconnecting a selected target',
      () async {
    final core = _Core()
      ..active = const ActiveConnectionSnapshot(
          sessionId: 'existing',
          target: ProxyTarget(id: 'other-node', name: '原连接', revision: 1),
          mode: ProxyMode.rule,
          configRevision: 'existing');
    final container = _container(core, FakeMobileIntegration());
    await container
        .read(mobileStartupControllerProvider)
        .start(isForeground: () => true);
    expect(core.requests, isEmpty);
    expect(container.read(sessionControllerProvider).active?.sessionId,
        'existing');
  });

  for (final reason in ['disabled', 'background', 'manual-stop', 'dispose']) {
    test('startup cannot connect after $reason', () async {
      final core = _Core();
      final ready = Completer<void>();
      final container = _container(core, FakeMobileIntegration(),
          autoConnect: reason != 'disabled', ready: ready.future);
      final startup = container.read(mobileStartupControllerProvider);
      final starting =
          startup.start(isForeground: () => reason != 'background');
      if (reason == 'manual-stop') {
        await container.read(sessionControllerProvider.notifier).disconnect();
      }
      if (reason == 'dispose') startup.dispose();
      ready.complete();
      await starting;
      expect(core.requests, isEmpty);
    });
  }

  test(
      'mobile notifications do not require a desktop tray and disk errors compensate native changes',
      () async {
    final mobile = FakeMobileIntegration();
    final repo = MemoryPreferences();
    final container = _container(_Core(), mobile, preferences: repo);
    final settings = container.read(deviceSettingsControllerProvider.notifier);
    await settings
        .saveGeneral(const GeneralPreferences(connectionNotifications: true));
    expect(repo.settings.general.connectionNotifications, isTrue);
    repo.writeFailure = const SettingsException('fixture disk full');
    await expectLater(
        settings.saveGeneral(
            const GeneralPreferences(subscriptionExpiryNotifications: true)),
        throwsA(isA<SettingsException>()));
    expect(mobile.connection, isTrue);
    expect(mobile.expiry, isFalse);
    expect(
        container
            .read(deviceSettingsControllerProvider)
            .general
            .connectionNotifications,
        isTrue);
    expect(
        container
            .read(deviceSettingsControllerProvider)
            .general
            .subscriptionExpiryNotifications,
        isFalse);
  });

  test(
      'unconfirmed native preference writes are compensated before returning failure',
      () async {
    final mobile = FakeMobileIntegration()
      ..onConfigure = (connection, expiry) async {
        if (connection) throw const SettingsException('unconfirmed write');
      };
    final repo = MemoryPreferences();
    final container = _container(_Core(), mobile, preferences: repo);
    await expectLater(
        container.read(deviceSettingsControllerProvider.notifier).saveGeneral(
            const GeneralPreferences(connectionNotifications: true)),
        throwsA(isA<SettingsException>()));
    expect(mobile.configurations, [
      (connection: true, expiry: false),
      (connection: false, expiry: false)
    ]);
    expect(mobile.connection, isFalse);
    expect(repo.settings.general.connectionNotifications, isFalse);
  });

  test('startup notification sync waits for an in-flight user preference write',
      () async {
    final nativeWrite = Completer<void>();
    final mobile = FakeMobileIntegration()
      ..onConfigure = (connection, expiry) => nativeWrite.future;
    final repo = MemoryPreferences();
    final container =
        _container(_Core(), mobile, autoConnect: false, preferences: repo);
    final settings = container.read(deviceSettingsControllerProvider.notifier);
    final saving = settings
        .saveGeneral(const GeneralPreferences(connectionNotifications: true));
    await Future<void>.delayed(Duration.zero);
    expect(mobile.configurations, [(connection: true, expiry: false)]);
    final startup = container
        .read(mobileStartupControllerProvider)
        .start(isForeground: () => true);
    await Future<void>.delayed(Duration.zero);
    expect(mobile.configurations, hasLength(1));
    nativeWrite.complete();
    await saving;
    await startup;
    expect(mobile.configurations, [
      (connection: true, expiry: false),
      (connection: true, expiry: false),
    ]);
    expect(mobile.connection, isTrue);
    expect(repo.settings.general.connectionNotifications, isTrue);
  });

  test(
      'mobile rejects desktop window changes and retains portable notification preferences',
      () async {
    const preferences = GeneralPreferences(
        showTray: false,
        connectionNotifications: true,
        subscriptionExpiryNotifications: true);
    expect(
        GeneralPreferences.fromJson(preferences.toJson())
            .connectionNotifications,
        isTrue);
    expect(() => preferences.validatedForDesktop(),
        throwsA(isA<SettingsException>()));
    final mobile = FakeMobileIntegration();
    final container = _container(_Core(), mobile);
    await expectLater(
        container
            .read(deviceSettingsControllerProvider.notifier)
            .saveGeneral(preferences),
        throwsA(isA<SettingsException>()));
    expect(mobile.configurations, isEmpty);
  });

  test(
      'Android boundary rejects false readback, malformed permission and private native errors',
      () async {
    const channel = MethodChannel('rainlink/mobile');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final mobile = AndroidMobileIntegration(channel: channel);
    addTearDown(mobile.dispose);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    messenger.setMockMethodCallHandler(channel,
        (call) async => {'connection': false, 'subscriptionExpiry': false});
    await expectLater(
        mobile.configureNotifications(
            connection: true, subscriptionExpiry: false),
        throwsA(isA<SettingsException>()));
    await expectLater(
        mobile.inspectNotifications(), throwsA(isA<SettingsException>()));
    messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(
            code: 'failed', message: 'private-url-token'));
    await expectLater(
        mobile.openNotificationSettings(),
        throwsA(isA<SettingsException>().having((error) => error.message,
            'safe error', isNot(contains('private-url-token')))));
  });

  test(
      'Android expiry boundary sends only bounded counts and requires actual acceptance',
      () async {
    const channel = MethodChannel('rainlink/mobile');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final mobile = AndroidMobileIntegration(channel: channel);
    addTearDown(mobile.dispose);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    for (final (soon, expired) in [(0, 0), (-1, 1), (1, -1), (0x80000000, 0)]) {
      await expectLater(
          mobile.notifySubscriptionExpiry(expiringSoon: soon, expired: expired),
          throwsA(isA<SettingsException>()));
    }
    expect(calls, isEmpty);
    await mobile.notifySubscriptionExpiry(expiringSoon: 2, expired: 1);
    expect(calls.single.arguments, {'expiringSoon': 2, 'expired': 1});
    messenger.setMockMethodCallHandler(channel, (call) async => false);
    await expectLater(
        mobile.notifySubscriptionExpiry(expiringSoon: 1, expired: 0),
        throwsA(isA<SettingsException>()));
  });
}
