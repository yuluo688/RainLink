import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainlink/application/preferences/device_settings_controller.dart';
import 'package:rainlink/application/preferences/theme_controller.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/preferences/drift_preferences_repository.dart';
import 'package:rainlink/domain/core/runtime_settings.dart';
import 'package:rainlink/domain/preferences/device_settings.dart';
import 'support/memory_preferences.dart';

class _Validator implements RuntimeSettingsGateway {
  Exception? failure;
  Completer<void>? pending;
  final calls = <CoreRuntimeSettings>[];
  @override
  Future<void> validateRuntime(CoreRuntimeSettings settings) async {
    calls.add(settings);
    await pending?.future;
    if (failure case final value?) throw value;
  }

  @override
  Future<DnsTestResult> testDns(CoreRuntimeSettings settings) async =>
      const DnsTestResult(addresses: ['203.0.113.1'], latency: 10);
  @override
  Future<void> cancelDnsTest() async {}
  @override
  Future<void> cancelValidation() async {}
}

void main() {
  test('default settings migrate without changing schema and survive reopen',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('rainlink-settings-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/settings.sqlite');
    final db = AppDatabase(NativeDatabase(file));
    final repo = DriftPreferencesRepository(db);
    final defaults = await repo.loadDeviceSettings();
    expect(defaults.runtime.proxyPort, 0);
    expect(defaults.runtime.dnsMode, DnsMode.system);
    expect(defaults.appearance.textSize, AppTextSize.standard);
    expect(defaults.appearance.density, AppDensity.compact);
    final runtime = defaults.runtime.copyWith(
        proxyPort: 17890,
        dnsMode: DnsMode.encrypted,
        ipv6: true,
        logLevel: CoreLogLevel.warn);
    await repo.saveRuntime(runtime);
    await repo.saveAppearance(const AppearancePreferences(
        textSize: AppTextSize.large,
        reduceMotion: true,
        density: AppDensity.standard));
    await db.close();
    final reopened = AppDatabase(NativeDatabase(file));
    addTearDown(reopened.close);
    final saved =
        await DriftPreferencesRepository(reopened).loadDeviceSettings();
    expect(saved.runtime.toJson(), runtime.toJson());
    expect(saved.appearance.textSize, AppTextSize.large);
    expect(saved.appearance.reduceMotion, isTrue);
    expect(saved.appearance.density, AppDensity.standard);
    expect(
        (await reopened.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        reopened.schemaVersion);
  });

  test(
      'old appearance preferences stay compact and invalid density is rejected',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.preferences).insert(PreferencesCompanion.insert(
        key: 'appearance.preferences',
        value: '{"textSize":"large","reduceMotion":true}'));
    final old = await DriftPreferencesRepository(db).loadDeviceSettings();
    expect(old.appearance.density, AppDensity.compact);
    expect(old.appearance.textSize, AppTextSize.large);
    expect(old.appearance.reduceMotion, isTrue);
    for (final density in [null, 'unknown', 1]) {
      expect(
          () => AppearancePreferences.fromJson({
                'textSize': 'standard',
                'reduceMotion': false,
                'density': density,
              }),
          throwsA(isA<SettingsException>()));
    }
  });

  test('failed density write retains confirmed appearance and queue recovers',
      () async {
    final repo = MemoryPreferences();
    final container = ProviderContainer(overrides: [
      preferencesRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    final controller =
        container.read(deviceSettingsControllerProvider.notifier);
    const next =
        AppearancePreferences(density: AppDensity.standard, reduceMotion: true);
    repo.writeFailure = const FileSystemException('fixture disk full');
    await expectLater(
        controller.saveAppearance(next), throwsA(isA<FileSystemException>()));
    expect(container.read(deviceSettingsControllerProvider).appearance.density,
        AppDensity.compact);
    expect(repo.settings.appearance.density, AppDensity.compact);
    repo.writeFailure = null;
    await controller.saveAppearance(next);
    expect(container.read(deviceSettingsControllerProvider).appearance.density,
        AppDensity.standard);
    expect(repo.settings.appearance.reduceMotion, isTrue);
  });

  test('invalid endpoints and ports fail with a safe domain error', () {
    for (final endpoint in [
      'http://dns.example.test',
      'https://user:secret@dns.example.test',
      'https://dns.example.test/?token=secret',
      'udp://dns.example.test',
      'udp://1.1.1.1/path',
      'https://dns.example.test:65536',
      'https://dns.example.test:abc',
      'https://dns.example.test/#fragment'
    ]) {
      expect(
          () => CoreRuntimeSettings(dnsMode: DnsMode.custom, resolver: endpoint)
              .validated(),
          throwsA(isA<SettingsException>()));
    }
    for (final port in [-1, 65536]) {
      expect(() => CoreRuntimeSettings(proxyPort: port).validated(),
          throwsA(isA<SettingsException>()));
    }
    expect(
        () => const CoreRuntimeSettings(
                dnsMode: DnsMode.encrypted, resolver: 'udp://1.1.1.1')
            .validated(),
        throwsA(isA<SettingsException>()));
    expect(
        () => const CoreRuntimeSettings(
                dnsMode: DnsMode.custom, bootstrapDns: 'localhost')
            .validated(),
        throwsA(isA<SettingsException>()));
    expect(
        CoreRuntimeSettings.fromJson(const CoreRuntimeSettings().toJson())
            .toJson(),
        const CoreRuntimeSettings().toJson());
  });

  test('validation and persistence failures leave confirmed settings unchanged',
      () async {
    final repo = MemoryPreferences();
    final gateway = _Validator();
    final container = ProviderContainer(overrides: [
      preferencesRepositoryProvider.overrideWithValue(repo),
      runtimeSettingsGatewayProvider.overrideWithValue(gateway),
    ]);
    addTearDown(container.dispose);
    final controller =
        container.read(deviceSettingsControllerProvider.notifier);
    final next = const CoreRuntimeSettings(proxyPort: 17890);
    gateway.failure = const SettingsException('核心拒绝');
    await expectLater(
        controller.saveRuntime(next), throwsA(isA<SettingsException>()));
    expect(
        container.read(deviceSettingsControllerProvider).runtime.proxyPort, 0);
    expect(repo.settings.runtime.proxyPort, 0);
    gateway.failure = null;
    repo.writeFailure = const FileSystemException('Disk unavailable');
    await expectLater(
        controller.saveRuntime(next), throwsA(isA<FileSystemException>()));
    expect(
        container.read(deviceSettingsControllerProvider).runtime.proxyPort, 0);
    repo.writeFailure = null;
    await controller.saveRuntime(next);
    expect(container.read(deviceSettingsControllerProvider).runtime.proxyPort,
        17890);
  });

  test(
      'interleaved saves preserve independent settings and disposal cancels queue',
      () async {
    final repo = MemoryPreferences();
    final gateway = _Validator()..pending = Completer<void>();
    final container = ProviderContainer(overrides: [
      preferencesRepositoryProvider.overrideWithValue(repo),
      runtimeSettingsGatewayProvider.overrideWithValue(gateway),
    ]);
    final controller =
        container.read(deviceSettingsControllerProvider.notifier);
    final runtime =
        controller.saveRuntime(const CoreRuntimeSettings(proxyPort: 17890));
    final appearance = controller
        .saveAppearance(const AppearancePreferences(reduceMotion: true));
    await Future<void>.delayed(Duration.zero);
    expect(repo.settings.appearance.reduceMotion, isFalse);
    gateway.pending?.complete();
    await Future.wait([runtime, appearance]);
    expect(container.read(deviceSettingsControllerProvider).runtime.proxyPort,
        17890);
    expect(
        container
            .read(deviceSettingsControllerProvider)
            .appearance
            .reduceMotion,
        isTrue);
    gateway.pending = Completer<void>();
    final cancelled = expectLater(
        controller.saveRuntime(const CoreRuntimeSettings(proxyPort: 17891)),
        throwsA(isA<SettingsException>()));
    await Future<void>.delayed(Duration.zero);
    container.dispose();
    gateway.pending?.complete();
    await cancelled;
    expect(repo.settings.runtime.proxyPort, 17890);
  });
}
