import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/preferences/device_settings_controller.dart';
import 'package:rainlink/application/preferences/theme_controller.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/preferences/drift_preferences_repository.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/core/advanced_config.dart';
import 'package:rainlink/domain/core/core_gateway.dart';
import 'package:rainlink/domain/core/runtime_settings.dart';
import 'package:rainlink/domain/core/session_gateway.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';

import 'support/memory_preferences.dart';

class _Validator extends Fake implements RuntimeSettingsGateway {
  Exception? failure;
  Completer<void>? pending;
  @override
  Future<void> validateRuntime(CoreRuntimeSettings settings) async {
    await pending?.future;
    if (failure case final error?) throw error;
  }
}

class _Gateway extends Fake implements SessionGateway {
  final requests = <ConnectRequest>[];
  Completer<void>? connectGate;
  bool rejectPatch = false;
  int disconnects = 0;
  @override
  Stream<Exception> get failures => const Stream.empty();
  @override
  Future<ActiveConnectionSnapshot> connect(ConnectRequest request) async {
    requests.add(request);
    await connectGate?.future;
    if (rejectPatch && !request.runtimeSettings.advanced.isEmpty) {
      throw const CoreGatewayException('fixture_rejection', '测试核心拒绝新配置');
    }
    return ActiveConnectionSnapshot(
        sessionId: 'test-${requests.length}',
        target: request.target,
        mode: request.mode,
        configRevision: 'test',
        proxyPort: 17890);
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<SessionObservation> observe() async => SessionObservation(
      phase: ConnectionPhase.connected,
      active: ActiveConnectionSnapshot(
          sessionId: 'test-${requests.length}',
          target: requests.last.target,
          mode: requests.last.mode,
          configRevision: 'test'),
      telemetry: const SessionTelemetry());
}

class _Preferences extends MemoryPreferences {
  Completer<void>? writeGate;

  @override
  Future<void> saveAdvanced(
      CoreRuntimeSettings value, AdvancedConfig previous) async {
    await writeGate?.future;
    await super.saveAdvanced(value, previous);
  }
}

void main() {
  final patch = AdvancedConfig.parse('log: {level: debug}', ConfigFormat.yaml);
  const node = ProxyNode(
      id: 'active',
      name: '活动节点 A',
      protocol: NodeProtocol.http,
      server: '127.0.0.1',
      port: 9);
  late _Preferences repo;
  late _Validator validator;
  late _Gateway gateway;
  late SessionController session;
  late ProviderContainer container;
  setUp(() {
    repo = _Preferences();
    validator = _Validator();
    gateway = _Gateway();
    session = SessionController(gateway, onMode: (_) {});
    container = ProviderContainer(overrides: [
      preferencesRepositoryProvider.overrideWithValue(repo),
      runtimeSettingsGatewayProvider.overrideWithValue(validator),
      sessionControllerProvider.overrideWith((ref) => session),
    ]);
    container.read(sessionControllerProvider);
  });
  tearDown(() => container.dispose());

  Future<void> apply(AdvancedConfig config) => container
      .read(deviceSettingsControllerProvider.notifier)
      .applyAdvanced(config,
          expectedRuntime:
              container.read(deviceSettingsControllerProvider).runtime,
          expectedSessionRevision: session.operationRevision);

  test(
      'offline apply saves without connecting and can restore the previous version',
      () async {
    await apply(patch);
    expect(gateway.requests, isEmpty);
    expect(repo.settings.runtime.advanced, patch);
    expect(repo.settings.previousAdvanced, const AdvancedConfig.empty());
    await apply(repo.settings.previousAdvanced!);
    expect(repo.settings.runtime.advanced.isEmpty, isTrue);
    expect(repo.settings.previousAdvanced, patch);
  });

  test('rejected validation preserves the active session and stored history',
      () async {
    await session.connect(node, ProxyMode.global);
    validator.failure = const SettingsException('核心拒绝配置');
    await expectLater(apply(patch), throwsA(isA<SettingsException>()));
    expect(session.state.connected, isTrue);
    expect(gateway.disconnects, 0);
    expect(repo.settings.runtime.advanced.isEmpty, isTrue);
    expect(repo.settings.previousAdvanced, isNull);
  });

  test('reconnect failure restores actual target, capture and previous runtime',
      () async {
    await session.setTun(true);
    await session.connect(node, ProxyMode.global);
    gateway.rejectPatch = true;
    await expectLater(
        apply(patch),
        throwsA(isA<SettingsException>()
            .having((e) => e.message, 'rollback', contains('已恢复原连接'))));
    expect(session.state.connected, isTrue);
    expect(session.state.tun, isTrue);
    expect(gateway.requests.length, 3);
    expect(gateway.requests.last.node, same(node));
    expect(gateway.requests.last.mode, ProxyMode.global);
    expect(gateway.requests.last.runtimeSettings.advanced.isEmpty, isTrue);
    expect(repo.settings.runtime.advanced.isEmpty, isTrue);
    expect(repo.settings.previousAdvanced, isNull);
  });

  test('failed disk transaction also restores the previously applied session',
      () async {
    await session.connect(node, ProxyMode.rule);
    repo.writeFailure = const FileSystemException('fixture disk full');
    await expectLater(apply(patch), throwsA(isA<SettingsException>()));
    expect(gateway.requests.map((request) => request.runtimeSettings.advanced),
        [const AdvancedConfig.empty(), patch, const AdvancedConfig.empty()]);
    expect(session.state.connected, isTrue);
    expect(repo.settings.runtime.advanced.isEmpty, isTrue);
    expect(repo.settings.previousAdvanced, isNull);
  });

  test('a stale runtime or connection confirmation cannot apply a patch',
      () async {
    final initial = container.read(deviceSettingsControllerProvider).runtime;
    final controller =
        container.read(deviceSettingsControllerProvider.notifier);
    await controller.saveRuntime(initial.copyWith(proxyPort: 17890));
    await expectLater(
        controller.applyAdvanced(patch,
            expectedRuntime: initial,
            expectedSessionRevision: session.operationRevision),
        throwsA(isA<SettingsException>()));
    validator.pending = Completer<void>();
    final operation =
        expectLater(apply(patch), throwsA(isA<SettingsException>()));
    await Future<void>.delayed(Duration.zero);
    await session.connect(node, ProxyMode.rule);
    validator.pending?.complete();
    await operation;
    expect(gateway.requests.length, 1);
    expect(repo.settings.runtime.advanced.isEmpty, isTrue);
  });

  test(
      'ordinary forms cannot overwrite an advanced patch from a stale snapshot',
      () async {
    final old = container.read(deviceSettingsControllerProvider).runtime;
    await apply(patch);
    await container
        .read(deviceSettingsControllerProvider.notifier)
        .saveRuntime(old.copyWith(proxyPort: 17890));
    expect(repo.settings.runtime.advanced, patch);
    expect(repo.settings.runtime.proxyPort, 17890);
  });

  test('disconnect during apply cannot revive a late connection', () async {
    await session.connect(node, ProxyMode.rule);
    final gate = Completer<void>();
    gateway.connectGate = gate;
    final operation =
        expectLater(apply(patch), throwsA(isA<SettingsException>()));
    await Future<void>.delayed(Duration.zero);
    expect(gateway.requests.length, 2);
    await session.disconnect();
    gate.complete();
    await operation;
    expect(session.state.phase, ConnectionPhase.idle);
    expect(session.state.active, isNull);
    expect(gateway.requests.length, 2);
    expect(repo.settings.runtime.advanced.isEmpty, isTrue);
    expect(repo.settings.previousAdvanced, isNull);
  });

  test('failed write after user disconnect does not reconnect for rollback',
      () async {
    await session.connect(node, ProxyMode.rule);
    final gate = Completer<void>();
    repo.writeGate = gate;
    repo.writeFailure = const FileSystemException('fixture disk full');
    final operation =
        expectLater(apply(patch), throwsA(isA<SettingsException>()));
    await Future<void>.delayed(Duration.zero);
    expect(gateway.requests.length, 2);
    expect(session.state.connected, isTrue);
    await session.disconnect();
    gate.complete();
    await operation;
    expect(session.state.phase, ConnectionPhase.idle);
    expect(session.state.active, isNull);
    expect(gateway.requests.length, 2);
    expect(repo.settings.runtime.advanced.isEmpty, isTrue);
    expect(repo.settings.previousAdvanced, isNull);
  });

  test('patch and history are atomic and survive database reopen', () async {
    final directory =
        await Directory.systemTemp.createTemp('rainlink-advanced-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/settings.sqlite');
    final db = AppDatabase(NativeDatabase(file));
    final stored = DriftPreferencesRepository(db);
    await stored.saveAdvanced(
        CoreRuntimeSettings(advanced: patch), const AdvancedConfig.empty());
    // Reject the second write to prove the first write rolls back with it.
    await db.customStatement(
        "CREATE TRIGGER reject_history BEFORE UPDATE ON preferences WHEN NEW.key = 'core.advanced.previous' BEGIN SELECT RAISE(ABORT, 'fixture disk failure'); END;");
    await expectLater(stored.saveAdvanced(const CoreRuntimeSettings(), patch),
        throwsA(isA<Exception>()));
    expect((await stored.loadDeviceSettings()).runtime.advanced, patch);
    await db.close();
    final reopened = AppDatabase(NativeDatabase(file));
    addTearDown(reopened.close);
    final saved =
        await DriftPreferencesRepository(reopened).loadDeviceSettings();
    expect(saved.runtime.advanced, patch);
    expect(saved.previousAdvanced, const AdvancedConfig.empty());
  });
}
