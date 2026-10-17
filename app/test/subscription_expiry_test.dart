import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/groups/subscription_expiry_monitor.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/groups/drift_group_repository.dart';
import 'package:rainlink/data/groups/drift_subscription_expiry_store.dart';
import 'package:rainlink/domain/core/runtime_settings.dart';
import 'package:rainlink/domain/groups/node_group.dart';
import 'package:rainlink/domain/groups/subscription_expiry.dart';
import 'package:rainlink/domain/platform/desktop_integration.dart';
import 'package:rainlink/domain/preferences/general_preferences.dart';

import 'support/fake_desktop_integration.dart';
import 'support/subscription_fixtures.dart';

class _Fixture {
  _Fixture() {
    repository = DriftGroupRepository(
        database, TestSecretStore(), TestSubscriptionFetcher());
    store = DriftSubscriptionExpiryStore(database);
    monitor = SubscriptionExpiryMonitor(
        groups: repository,
        store: store,
        notifications: desktop,
        enabled: () => enabled,
        onError: (message) => error = message,
        now: () => now);
  }
  final database = AppDatabase(NativeDatabase.memory());
  final desktop = FakeDesktopIntegration()..tray = true;
  late final DriftGroupRepository repository;
  late final DriftSubscriptionExpiryStore store;
  late final SubscriptionExpiryMonitor monitor;
  DateTime now = DateTime.utc(2026, 10, 17);
  bool enabled = true;
  String? error;

  Future<void> group(String id, Duration? remaining,
          {GroupKind kind = GroupKind.subscription}) =>
      database.into(database.nodeGroups).insertOnConflictUpdate(
          NodeGroupsCompanion.insert(
              id: id,
              name: 'private-$id-https://example.test/token',
              kind: kind.name,
              autoUpdate: const Value(false),
              expiresAt: Value(remaining == null ? null : now.add(remaining))));

  Future<void> settle() async {
    // Let Drift publish its initial/current snapshot, then await the serialized
    // check itself rather than assuming the notification happened on a timer.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await monitor.checkNow();
  }

  Future<void> close() async {
    await monitor.close();
    await desktop.dispose();
    await database.close();
  }
}

class _DelayedCancellationGroups extends DriftGroupRepository {
  _DelayedCancellationGroups(AppDatabase database)
      : super(database, TestSecretStore(), TestSubscriptionFetcher());
  final streams = <StreamController<List<NodeGroup>>>[];
  final cancellations = <Completer<void>>[];
  @override
  Stream<List<NodeGroup>> watchGroups() {
    final cancellation = Completer<void>();
    late final StreamController<List<NodeGroup>> stream;
    stream = StreamController<List<NodeGroup>>(
        onListen: () => stream.add(const []),
        onCancel: () => cancellation.future);
    streams.add(stream);
    cancellations.add(cancellation);
    return stream.stream;
  }
}

void main() {
  test(
      'expiry boundaries, unknown metadata, manual groups and monotonic stages',
      () {
    final now = DateTime.utc(2026, 10, 17);
    NodeGroup group(String id, Duration? left,
            {GroupKind kind = GroupKind.subscription}) =>
        NodeGroup(
            id: id,
            name: id,
            kind: kind,
            expiresAt: left == null ? null : now.add(left));
    final groups = [
      group('unknown', null),
      group('far', const Duration(days: 3, seconds: 1)),
      group('boundary', const Duration(days: 3)),
      group('now', Duration.zero),
      group('past', const Duration(seconds: -1)),
      group('manual', const Duration(hours: 1), kind: GroupKind.manual),
    ];
    final pending = pendingSubscriptionExpiryAlerts(groups, {}, now);
    expect(pending.map((alert) => alert.groupId), ['boundary', 'now', 'past']);
    expect(pending.map((alert) => alert.stage), [
      SubscriptionExpiryStage.soon,
      SubscriptionExpiryStage.expired,
      SubscriptionExpiryStage.expired
    ]);
    final receipt = {for (final alert in pending) alert.groupId: alert};
    expect(pendingSubscriptionExpiryAlerts(groups, receipt, now), isEmpty);
    // Clock rollback cannot downgrade an already delivered expired notice.
    expect(
        pendingSubscriptionExpiryAlerts(
            [groups[3]], receipt, now.subtract(const Duration(days: 1))),
        isEmpty);
  });

  test('old general settings opt out and malformed reminder flags are rejected',
      () {
    final old = {
      'autoConnect': false,
      'showTray': true,
      'connectionNotifications': true,
      'closeBehavior': 'exit'
    };
    expect(GeneralPreferences.fromJson(old).subscriptionExpiryNotifications,
        isFalse);
    for (final invalid in [null, 1, 'true']) {
      expect(
          () => GeneralPreferences.fromJson(
              {...old, 'subscriptionExpiryNotifications': invalid}),
          throwsA(isA<SettingsException>()));
    }
    expect(
        () => const GeneralPreferences(
                showTray: false, subscriptionExpiryNotifications: true)
            .validatedForDesktop(),
        throwsA(isA<SettingsException>()));
    expect(
        GeneralPreferences.fromJson(
                const GeneralPreferences(subscriptionExpiryNotifications: true)
                    .toJson())
            .subscriptionExpiryNotifications,
        isTrue);
  });

  test('aggregates private subscriptions once per term and renews after expiry',
      () async {
    final f = _Fixture();
    addTearDown(f.close);
    await f.group('soon', const Duration(days: 2));
    await f.group('expired', const Duration(days: -1));
    await f.group('unknown', null);
    await f.group('manual', const Duration(hours: 1), kind: GroupKind.manual);
    f.monitor.resume();
    await f.settle();
    expect(f.desktop.expiryNotices, [(expiringSoon: 1, expired: 1)]);
    expect((await f.store.load()).length, 2);
    await f.monitor.checkNow();
    f.monitor.pause();
    f.monitor.resume();
    await f.settle();
    expect(f.desktop.expiryNotices.length, 1);
    f.now = f.now.add(const Duration(days: 2));
    await f.monitor.checkNow();
    expect(f.desktop.expiryNotices.last, (expiringSoon: 0, expired: 1));
    await f.group('soon', const Duration(days: 30));
    await f.settle();
    expect(f.desktop.expiryNotices.length, 2);
    f.now = f.now.add(const Duration(days: 28));
    await f.monitor.checkNow();
    expect(f.desktop.expiryNotices.last, (expiringSoon: 1, expired: 0));
    expect(f.desktop.expiryNotices.length, 3);
  });

  test('disabled reminders and missing expiry never notify or create records',
      () async {
    final f = _Fixture()..enabled = false;
    addTearDown(f.close);
    await f.group('soon', const Duration(hours: 1));
    f.monitor.resume();
    await f.settle();
    expect(f.desktop.expiryNotices, isEmpty);
    expect(await f.database.select(f.database.preferences).get(), isEmpty);
    f.enabled = true;
    await f.monitor.checkNow();
    expect(f.desktop.expiryNotices.single, (expiringSoon: 1, expired: 0));
  });

  test('native refusal and unready tray retain eligibility and allow retry',
      () async {
    final f = _Fixture();
    addTearDown(f.close);
    await f.group('soon', const Duration(hours: 1));
    f.desktop.tray = false;
    f.monitor.resume();
    await f.settle();
    expect(f.desktop.expiryNotices, isEmpty);
    expect(await f.store.load(), isEmpty);
    expect(f.error, contains('系统通知尚未就绪'));
    f.desktop.tray = true;
    f.desktop.onExpiry =
        (_, __) async => throw const SettingsException('private-path');
    await f.monitor.checkNow();
    expect(f.error, '系统未接收订阅到期提醒，请稍后重试');
    expect(await f.store.load(), isEmpty);
    f.desktop.onExpiry = null;
    await f.monitor.checkNow();
    expect(f.desktop.expiryNotices.length, 1);
    expect(f.error, isNull);
  });

  for (final change in ['disable', 'renew', 'delete', 'pause']) {
    test('$change during native inspection cancels stale delivery', () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.group('soon', const Duration(hours: 1));
      final inspected = Completer<void>();
      final ready = Completer<DesktopIntegrationStatus>();
      f.desktop.onInspect = () {
        if (!inspected.isCompleted) inspected.complete();
        return ready.future;
      };
      f.monitor.resume();
      await inspected.future;
      if (change == 'disable') f.enabled = false;
      if (change == 'renew') await f.group('soon', const Duration(days: 30));
      if (change == 'delete') {
        await f.database.delete(f.database.nodeGroups).go();
      }
      if (change == 'pause') f.monitor.pause();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      ready.complete(const DesktopIntegrationStatus(
          launchAtLogin: false, trayVisible: true));
      await f.settle();
      expect(f.desktop.expiryNotices, isEmpty);
      expect(await f.store.load(), isEmpty);
    });
  }

  test('accepted notice is not resent when actual SQLite receipt write fails',
      () async {
    final f = _Fixture();
    addTearDown(f.close);
    await f.group('soon', const Duration(hours: 1));
    await f.database.customStatement(
        "CREATE TRIGGER reject_expiry BEFORE INSERT ON preferences WHEN NEW.key = 'notifications.subscription_expiry' BEGIN SELECT RAISE(ABORT, 'private disk path'); END");
    f.monitor.resume();
    await f.settle();
    expect(f.desktop.expiryNotices.length, 1);
    expect(f.error, contains('提醒已提交，但记录未保存'));
    expect(f.error, isNot(contains('private disk path')));
    expect(await f.store.load(), isEmpty);
    await f.monitor.checkNow();
    expect(f.desktop.expiryNotices.length, 1);
    await f.database.customStatement('DROP TRIGGER reject_expiry');
    await f.monitor.checkNow();
    expect(f.desktop.expiryNotices.length, 1);
    expect((await f.store.load()).keys, ['soon']);
    expect(f.error, isNull);
  });

  test('close awaits an accepted native call and persists it before releasing',
      () async {
    final f = _Fixture();
    addTearDown(f.close);
    await f.group('soon', const Duration(hours: 1));
    final sending = Completer<void>();
    final accepted = Completer<void>();
    f.desktop.onExpiry = (_, __) {
      sending.complete();
      return accepted.future;
    };
    f.monitor.resume();
    await sending.future;
    var closed = false;
    final close = f.monitor.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    accepted.complete();
    await close;
    expect(f.desktop.expiryNotices.length, 1);
    expect((await f.store.load()).keys, ['soon']);
  });

  test('close awaits every pending stream cancellation and prevents resume',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    final groups = _DelayedCancellationGroups(database);
    final desktop = FakeDesktopIntegration();
    final monitor = SubscriptionExpiryMonitor(
        groups: groups,
        store: DriftSubscriptionExpiryStore(database),
        notifications: desktop,
        enabled: () => false,
        onError: (_) {});
    try {
      monitor.resume();
      await Future<void>.delayed(Duration.zero);
      monitor.pause();
      monitor.resume();
      await Future<void>.delayed(Duration.zero);
      expect(groups.streams.length, 2);
      var closed = false;
      final closing = monitor.close().then((_) => closed = true);
      monitor.resume();
      expect(groups.streams.length, 2);
      groups.cancellations.last.complete();
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      groups.cancellations.first.complete();
      await closing;
      expect(desktop.expiryNotices, isEmpty);
    } finally {
      for (final cancellation in groups.cancellations) {
        if (!cancellation.isCompleted) cancellation.complete();
      }
      await monitor.close();
      for (final stream in groups.streams) {
        await stream.close();
      }
      await desktop.dispose();
      await database.close();
    }
  });

  test('receipt storage prunes deleted groups and refuses corrupt metadata',
      () async {
    final f = _Fixture();
    addTearDown(f.close);
    final alert = SubscriptionExpiryAlert(
        groupId: 'term',
        expiresAt: f.now,
        stage: SubscriptionExpiryStage.expired);
    await f.store.record([alert], validGroupIds: {'term'});
    await f.store.record([
      SubscriptionExpiryAlert(
          groupId: 'term',
          expiresAt: f.now,
          stage: SubscriptionExpiryStage.soon)
    ], validGroupIds: {
      'term'
    });
    expect(
        (await f.store.load())['term']?.stage, SubscriptionExpiryStage.expired);
    await f.store.record(const [], validGroupIds: {});
    expect(await f.store.load(), isEmpty);
    for (final value in [
      'private-invalid-json',
      '{"version":2,"receipts":{}}',
      '{"version":1,"receipts":{"term":{"expiresAt":0,"stage":"secret"}}}'
    ]) {
      await f.database.into(f.database.preferences).insertOnConflictUpdate(
          PreferencesCompanion.insert(
              key: DriftSubscriptionExpiryStore.preferenceKey, value: value));
      await expectLater(
          f.store.load(),
          throwsA(isA<SettingsException>()
              .having((error) => error.message, 'safe error', '订阅提醒记录格式无效')));
    }
  });
}
