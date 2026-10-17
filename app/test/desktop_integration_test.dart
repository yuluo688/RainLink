import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/chains/chain_providers.dart';
import 'package:rainlink/application/connection/connect_selected.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/application/preferences/desktop_integration_controller.dart';
import 'package:rainlink/application/preferences/device_settings_controller.dart';
import 'package:rainlink/application/preferences/theme_controller.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/preferences/drift_preferences_repository.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/core/core_status.dart';
import 'package:rainlink/domain/core/session_gateway.dart';
import 'package:rainlink/domain/core/runtime_settings.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/platform/desktop_integration.dart';
import 'package:rainlink/domain/preferences/device_settings.dart';
import 'package:rainlink/domain/preferences/general_preferences.dart';
import 'package:rainlink/platform/window/desktop_session_guard.dart';
import 'package:rainlink/platform/window/windows_desktop_integration.dart';
import 'package:rainlink/application/updates/app_update_controller.dart';
import 'package:rainlink/domain/updates/app_update.dart';

import 'support/fake_desktop_integration.dart';
import 'support/memory_preferences.dart';

const _node = ProxyNode(
    id: 'startup',
    name: '本地测试',
    protocol: NodeProtocol.http,
    server: '127.0.0.1',
    port: 9);

class _SlowPreferences extends MemoryPreferences {
  final writeGate = Completer<void>();
  @override
  Future<void> saveGeneral(GeneralPreferences value) async {
    await writeGate.future;
    await super.saveGeneral(value);
  }
}

class _Core implements SessionGateway {
  final requests = <ConnectRequest>[];
  ActiveConnectionSnapshot? active;
  bool rejectDisconnect = false;
  int disconnects = 0;
  bool closed = false;
  @override
  Stream<Exception> get failures => const Stream.empty();
  @override
  Future<CoreStatus> inspect() async => const CoreStatus(
      hostAvailable: true,
      message: 'ready',
      capabilities: CoreCapabilities(connect: true));
  @override
  Future<ActiveConnectionSnapshot> connect(ConnectRequest request) async {
    requests.add(request);
    return active = ActiveConnectionSnapshot(
        sessionId: 'startup',
        target: request.target,
        mode: request.mode,
        configRevision: 'fixture');
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    if (rejectDisconnect) throw const SettingsException('恢复失败');
    active = null;
  }

  @override
  Future<SessionObservation> observe() async => SessionObservation(
      phase: active == null ? ConnectionPhase.idle : ConnectionPhase.connected,
      active: active);
  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<void> setMode(ProxyMode mode) async {}
  @override
  Future<void> setSystemProxy(bool enabled) async {}
  @override
  Future<void> probe() async {}
  @override
  void dispose() {}
}

class _PreparedUpdate implements PreparedUpdate {
  int commits = 0;
  int aborts = 0;
  Future<void> Function()? onCommit;
  @override
  Future<void> commit() async {
    commits++;
    await onCommit?.call();
  }

  @override
  Future<void> abort() async => aborts++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'general and connection preferences persist independently with validation',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftPreferencesRepository(db);
    await repo.saveGeneral(const GeneralPreferences(
        autoConnect: true,
        closeBehavior: WindowCloseBehavior.tray,
        connectionNotifications: true));
    await repo.saveConnection(const ConnectionPreferences(
        mode: ProxyMode.global, systemProxy: true, tun: true));
    final settings = await repo.loadDeviceSettings();
    expect(settings.general.autoConnect, isTrue);
    expect(settings.general.closeBehavior, WindowCloseBehavior.tray);
    expect(settings.connection.mode, ProxyMode.global);
    expect(settings.connection.systemProxy, isTrue);
    expect(settings.connection.tun, isTrue);
    expect(
        ConnectionPreferences.fromJson({'mode': 'rule', 'systemProxy': false})
            .tun,
        isFalse);
    expect(
        () => ConnectionPreferences.fromJson(
            {'mode': 'rule', 'systemProxy': false, 'tun': 'true'}),
        throwsA(isA<SettingsException>()));
    expect(settings.runtime.proxyPort, 0);
    expect(
        () => const GeneralPreferences(
                showTray: false, closeBehavior: WindowCloseBehavior.tray)
            .validated(),
        throwsA(isA<SettingsException>()));
    expect(
        () => const GeneralPreferences(
                showTray: false, connectionNotifications: true)
            .validatedForDesktop(),
        throwsA(isA<SettingsException>()));
    expect(
        () => ConnectionPreferences.fromJson(
            {'mode': 'invalid', 'systemProxy': true}),
        throwsA(isA<SettingsException>()));
  });

  test(
      'tray failure preserves preferences and disk failure rolls the tray back',
      () async {
    final repo = MemoryPreferences();
    final desktop = FakeDesktopIntegration()..tray = true;
    addTearDown(desktop.dispose);
    final container = ProviderContainer(overrides: [
      preferencesRepositoryProvider.overrideWithValue(repo),
      desktopIntegrationProvider.overrideWithValue(desktop)
    ]);
    addTearDown(container.dispose);
    final controller =
        container.read(deviceSettingsControllerProvider.notifier);
    desktop.rejectTray = true;
    await expectLater(
        controller.saveGeneral(const GeneralPreferences(showTray: false)),
        throwsA(isA<SettingsException>()));
    expect(repo.settings.general.showTray, isTrue);
    desktop.rejectTray = false;
    repo.writeFailure = const SettingsException('磁盘拒绝');
    await expectLater(
        controller.saveGeneral(const GeneralPreferences(showTray: false)),
        throwsA(isA<SettingsException>()));
    expect(desktop.trayChanges, [false, true]);
    expect(desktop.tray, isTrue);
    expect(container.read(deviceSettingsControllerProvider).general.showTray,
        isTrue);
  });

  test('startup write must pass actual readback before controller confirms',
      () async {
    final desktop = FakeDesktopIntegration()..rejectLaunch = true;
    addTearDown(desktop.dispose);
    final container = ProviderContainer(
        overrides: [desktopIntegrationProvider.overrideWithValue(desktop)]);
    addTearDown(container.dispose);
    await container.read(desktopIntegrationStatusProvider.future);
    await expectLater(
        container
            .read(desktopIntegrationStatusProvider.notifier)
            .setLaunchAtLogin(true),
        throwsA(isA<SettingsException>()));
    expect(
        container
            .read(desktopIntegrationStatusProvider)
            .valueOrNull
            ?.launchAtLogin,
        isFalse);
    desktop.rejectLaunch = false;
    await container
        .read(desktopIntegrationStatusProvider.notifier)
        .setLaunchAtLogin(true);
    expect(
        container
            .read(desktopIntegrationStatusProvider)
            .valueOrNull
            ?.launchAtLogin,
        isTrue);
  });

  for (final cancel in [false, true]) {
    test('startup waits for selection and honors cancellation: $cancel',
        () async {
      final ready = StreamController<List<ProxyNode>>();
      addTearDown(ready.close);
      final core = _Core();
      final container = ProviderContainer(overrides: [
        coreGatewayProvider.overrideWithValue(core),
        initialDeviceSettingsProvider.overrideWithValue(const DeviceSettings(
            connection: ConnectionPreferences(
                mode: ProxyMode.global, systemProxy: true))),
        nodesProvider.overrideWith((ref) => ready.stream),
        selectedNodeIdProvider.overrideWith((ref) => Stream.value(_node.id)),
        chainsProvider.overrideWith((ref) => Stream.value(const [])),
        selectedChainIdProvider.overrideWith((ref) => Stream.value(null)),
      ]);
      addTearDown(container.dispose);
      final connecting = container.read(connectSelectedProvider)();
      await Future<void>.delayed(Duration.zero);
      expect(core.requests, isEmpty);
      if (cancel) {
        await container.read(sessionControllerProvider.notifier).disconnect();
      }
      ready.add([_node]);
      await connecting;
      expect(core.requests.length, cancel ? 0 : 1);
      if (!cancel) {
        expect(core.requests.single.mode, ProxyMode.global);
        expect(core.requests.single.systemProxy, isTrue);
      }
    });
  }

  testWidgets(
      'close to tray preserves connection and explicit quit restores before destroy',
      (tester) async {
    final desktop = FakeDesktopIntegration();
    addTearDown(desktop.dispose);
    final repo = _SlowPreferences()
      ..settings = const DeviceSettings(
          general: GeneralPreferences(closeBehavior: WindowCloseBehavior.tray));
    final core = _Core();
    final calls = <String>[];
    const channel = MethodChannel('window_manager');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call.method);
      return call.method == 'isMinimized' ? false : null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(ProviderScope(overrides: [
      preferencesRepositoryProvider.overrideWithValue(repo),
      initialDeviceSettingsProvider.overrideWithValue(repo.settings),
      coreGatewayProvider.overrideWithValue(core),
      desktopIntegrationProvider.overrideWithValue(desktop),
    ], child: const MaterialApp(home: DesktopSessionGuard(child: SizedBox()))));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(DesktopSessionGuard)));
    await container
        .read(sessionControllerProvider.notifier)
        .connect(_node, ProxyMode.rule);
    await tester.pumpAndSettle();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'window_manager',
        const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onEvent', {'eventName': 'close'})),
        (_) {});
    await tester.pumpAndSettle();
    expect(desktop.visible, isFalse);
    expect(container.read(sessionControllerProvider).connected, isTrue);
    expect(core.disconnects, 0);
    expect(calls, isNot(contains('destroy')));
    final write = container
        .read(deviceSettingsControllerProvider.notifier)
        .saveGeneral(const GeneralPreferences(
            autoConnect: true, closeBehavior: WindowCloseBehavior.tray));
    desktop.events.add(DesktopAction.quit);
    await tester.pumpAndSettle();
    expect(calls, isNot(contains('destroy')));
    expect(desktop.closeCalled, isFalse);
    repo.writeGate.complete();
    await write;
    for (var tick = 0; tick < 20 && !calls.contains('destroy'); tick++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(core.disconnects, 1);
    expect(core.closed, isTrue);
    expect(desktop.tray, isFalse);
    // The native window owns final destruction. Its Dart event stream stays
    // reusable until destroy succeeds, allowing a refused close to recover.
    expect(desktop.closeCalled, isFalse);
    expect(calls.last, 'destroy');
    expect(repo.settings.general.autoConnect, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed restore keeps the window and tray available for retry',
      (tester) async {
    final desktop = FakeDesktopIntegration();
    addTearDown(desktop.dispose);
    final core = _Core()..rejectDisconnect = true;
    final calls = <String>[];
    const channel = MethodChannel('window_manager');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call.method);
      return call.method == 'isMinimized' ? false : null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(ProviderScope(overrides: [
      preferencesRepositoryProvider.overrideWithValue(MemoryPreferences()),
      coreGatewayProvider.overrideWithValue(core),
      desktopIntegrationProvider.overrideWithValue(desktop),
    ], child: const MaterialApp(home: DesktopSessionGuard(child: SizedBox()))));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(DesktopSessionGuard)));
    await container
        .read(sessionControllerProvider.notifier)
        .connect(_node, ProxyMode.rule);
    desktop.events.add(DesktopAction.quit);
    await tester.pumpAndSettle();
    expect(core.closed, isFalse);
    expect(desktop.closeCalled, isFalse);
    expect(calls, isNot(contains('destroy')));
    expect(calls, contains('show'));
    expect(container.read(desktopIntegrationNoticeProvider), contains('尚未恢复'));
    core.rejectDisconnect = false;
    desktop.events.add(DesktopAction.quit);
    for (var tick = 0; tick < 20 && !calls.contains('destroy'); tick++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(calls.last, 'destroy');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'update exit restores network before commit and recovers refused handoff',
      (tester) async {
    final desktop = FakeDesktopIntegration();
    addTearDown(desktop.dispose);
    final core = _Core()..rejectDisconnect = true;
    final calls = <String>[];
    const channel = MethodChannel('window_manager');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call.method);
      return call.method == 'isMinimized' ? false : null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(ProviderScope(overrides: [
      preferencesRepositoryProvider.overrideWithValue(MemoryPreferences()),
      coreGatewayProvider.overrideWithValue(core),
      desktopIntegrationProvider.overrideWithValue(desktop),
    ], child: const MaterialApp(home: DesktopSessionGuard(child: SizedBox()))));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(DesktopSessionGuard)));
    await container
        .read(sessionControllerProvider.notifier)
        .connect(_node, ProxyMode.rule);
    final coordinator = container.read(updateShutdownProvider);
    final refused = _PreparedUpdate();
    final rejection =
        expectLater(coordinator.request(refused), throwsException);
    await tester.pumpAndSettle();
    await rejection;
    expect(refused.commits, 0);
    expect(refused.aborts, 1);
    expect(core.closed, isFalse);
    expect(desktop.tray, isTrue);
    expect(calls, isNot(contains('destroy')));

    core.rejectDisconnect = false;
    final handoff = _PreparedUpdate();
    ConnectionPhase? phaseAtCommit;
    bool? idleAtCommit;
    bool? closedAtCommit;
    bool? trayAtCommit;
    handoff.onCommit = () async {
      phaseAtCommit = container.read(sessionControllerProvider).phase;
      idleAtCommit = core.active == null;
      closedAtCommit = core.closed;
      trayAtCommit = desktop.tray;
      throw const UpdateException('fixture handoff refused');
    };
    final failedHandoff = expectLater(
        coordinator.request(handoff), throwsA(isA<UpdateException>()));
    await tester.pumpAndSettle();
    await failedHandoff;
    expect(phaseAtCommit, ConnectionPhase.idle);
    expect(idleAtCommit, isTrue);
    expect(closedAtCommit, isTrue);
    expect(trayAtCommit, isFalse);
    expect(handoff.commits, 1);
    expect(handoff.aborts, 1);
    expect(desktop.tray, isTrue);
    expect(desktop.closeCalled, isFalse);
    expect(calls, isNot(contains('destroy')));
    expect(container.read(appUpdateControllerProvider).working, isFalse);
    // A refused installation must not strand the tray listener or block quit.
    desktop.events.add(DesktopAction.quit);
    await tester.pumpAndSettle();
    expect(calls.last, 'destroy');
    await tester.pumpWidget(const SizedBox());
  });

  test(
      'Windows adapter rejects invalid receipts and hides native error details',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('dev.rainlink/desktop');
    final adapter = WindowsDesktopIntegration();
    addTearDown(adapter.dispose);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    messenger.setMockMethodCallHandler(
        channel, (call) async => {'launchAtLogin': 'yes'});
    await expectLater(adapter.inspect(), throwsA(isA<SettingsException>()));
    messenger.setMockMethodCallHandler(
        channel,
        (call) async =>
            throw PlatformException(code: 'native', message: 'private path'));
    await expectLater(
        adapter.setLaunchAtLogin(true),
        throwsA(isA<SettingsException>().having(
            (e) => e.message, 'safe error', isNot(contains('private path')))));
  });

  test('expiry native boundary sends counts only and rejects invalid values',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('dev.rainlink/desktop');
    final adapter = WindowsDesktopIntegration();
    addTearDown(adapter.dispose);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    for (final (soon, expired) in [
      (0, 0),
      (-1, 1),
      (1, -1),
      (0x80000000, 0),
      (0, 0x80000000)
    ]) {
      expect(
          () => adapter.notifySubscriptionExpiry(
              expiringSoon: soon, expired: expired),
          throwsA(isA<SettingsException>()));
    }
    expect(calls, isEmpty);
    await adapter.notifySubscriptionExpiry(expiringSoon: 2, expired: 1);
    expect(calls.single.method, 'notifySubscriptionExpiry');
    expect(calls.single.arguments, {'expiringSoon': 2, 'expired': 1});
    messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(
            code: 'failure', message: 'private-url-token'));
    await expectLater(
        adapter.notifySubscriptionExpiry(expiringSoon: 1, expired: 0),
        throwsA(isA<SettingsException>().having((e) => e.message, 'safe error',
            isNot(contains('private-url-token')))));
  });
}
