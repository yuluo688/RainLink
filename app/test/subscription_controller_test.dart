import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/groups/group_providers.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/groups/drift_group_repository.dart';
import 'package:rainlink/domain/groups/node_group.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'support/subscription_fixtures.dart';

void main() {
  test(
      'per-subscription operations reject overlap and cancellation stops commit',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fetcher = TestSubscriptionFetcher();
    final repo = DriftGroupRepository(db, TestSecretStore(), fetcher);
    final id = await repo.importUrl(
        'https://example.test/sub', SubscriptionCancellation());
    final controller = SubscriptionController(repo);
    addTearDown(controller.dispose);
    final started = Completer<void>();
    final fetched = Completer<SubscriptionDocument>();
    fetcher.handler = (_, __) {
      started.complete();
      return fetched.future;
    };
    final expectation = expectLater(
        controller.refresh(id), throwsA(isA<SubscriptionCancelled>()));
    await started.future;
    expect(controller.isBusy(id), isTrue);
    await expectLater(controller.refresh(id), throwsA(isA<NodeException>()));
    controller.cancel(id);
    fetched.complete(subscriptionDocument());
    await expectation;
    expect(controller.isBusy(id), isFalse);
    expect((await repo.watchGroups().first).single.updateError, isEmpty);
  });

  test(
      'auto update checks due groups once, respects disabled subscriptions and resumes overdue work',
      () async {
    var now = DateTime.utc(2026, 10, 16);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fetcher = TestSubscriptionFetcher();
    final repo =
        DriftGroupRepository(db, TestSecretStore(), fetcher, now: () => now);
    await repo.importUrl('https://example.test/a', SubscriptionCancellation());
    await repo.importUrl('https://example.test/b', SubscriptionCancellation());
    var groups = await repo.watchGroups().first;
    await repo.setAutoUpdate(groups.last, false);
    final controller = SubscriptionController(repo);
    addTearDown(controller.dispose);
    final maintenance =
        SubscriptionMaintenance(repo, controller, now: () => now);
    addTearDown(maintenance.pause);
    final before = fetcher.calls;
    maintenance.resume();
    // Let the startup check finish before explicitly advancing the clock.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await maintenance.checkDue();
    expect(fetcher.calls, before);
    now = now.add(const Duration(hours: 25));
    await maintenance.checkDue();
    expect(fetcher.calls, before + 1);
    await maintenance.checkDue();
    expect(fetcher.calls, before + 1);
    maintenance.pause();
    now = now.add(const Duration(hours: 25));
    await maintenance.checkDue();
    expect(fetcher.calls, before + 1);
    maintenance.resume();
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (fetcher.calls < before + 2 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(fetcher.calls, before + 2);
    maintenance.pause();
    // Finish any in-flight DB work before disposal.
    while (controller.isBusy(groups.first.id)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    groups = await repo.watchGroups().first;
    expect(groups.last.autoUpdate, isFalse);
  });
}
