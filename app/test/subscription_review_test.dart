import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/groups/group_providers.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/groups/drift_group_repository.dart';
import 'package:rainlink/data/nodes/drift_node_repository.dart';
import 'package:rainlink/domain/groups/node_group.dart';
import 'package:rainlink/domain/groups/subscription_issue.dart';
import 'package:rainlink/domain/groups/subscription_review.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';

import 'support/subscription_fixtures.dart';

const _issue = SubscriptionIssue(
  kind: SubscriptionIssueKind.unsupported,
  item: 2,
  reason: '暂不支持此协议',
);

SubscriptionDocument _partial({List<NodeDraft>? nodes}) => SubscriptionDocument(
  name: '兼容订阅',
  nodes: nodes ?? [subscriptionNode()],
  skippedNodes: 1,
  issues: const [_issue],
);

Future<SubscriptionReview> _preview(Future<Object?> Function() run) async {
  try {
    await run();
  } on SubscriptionReviewRequired catch (error) {
    return error.review;
  }
  throw StateError('Expected explicit review before writing');
}

void main() {
  late AppDatabase db;
  late TestSecretStore secrets;
  late TestSubscriptionFetcher fetcher;
  late DriftGroupRepository groups;
  late DriftNodeRepository nodes;
  late DateTime now;
  var protected = 0;
  setUp(() {
    now = DateTime.utc(2026, 10, 17);
    protected = 0;
    db = AppDatabase(NativeDatabase.memory());
    secrets = TestSecretStore()..onProtect = () => protected++;
    fetcher = TestSubscriptionFetcher();
    groups = DriftGroupRepository(db, secrets, fetcher, now: () => now);
    nodes = DriftNodeRepository(db, secrets);
  });
  tearDown(() => db.close());
  Future<String> import() => groups.importUrl(
    'https://provider.example.test/sub?token=private-fixture',
    SubscriptionCancellation(),
  );
  Future<void> refresh(String id) =>
      groups.refresh(id, SubscriptionCancellation());

  test(
    'partial import writes nothing until explicit acceptance and never refetches',
    () async {
      fetcher.document = _partial();
      final review = await _preview(import);
      expect(protected, 0);
      expect(await db.select(db.nodes).get(), isEmpty);
      expect(await db.select(db.nodeGroups).get(), isEmpty);
      expect(await db.select(db.preferences).get(), isEmpty);
      fetcher.document = subscriptionDocument(
        nodes: [subscriptionNode(name: 'later response')],
      );
      final id = await groups.acceptReview(
        review,
        SubscriptionCancellation(),
        autoUpdate: false,
      );
      expect(fetcher.calls, 1);
      expect((await nodes.watchNodes().first).single.name, '日本 01');
      final group = (await groups.watchGroups().first).single;
      expect(group.id, id);
      expect(group.autoUpdate, isFalse);
      expect(group.issues.single.reason, _issue.reason);
      final raw =
          (await db.select(db.nodeGroups).getSingle()).compatibilityIssues;
      expect(raw, isNot(contains('private-fixture')));
      expect(raw, isNot(contains('fixture-password')));
      await expectLater(
        groups.acceptReview(review, SubscriptionCancellation()),
        throwsA(isA<NodeException>()),
      );
    },
  );

  test(
    'a preview freezes the exact nodes, transport lists and diagnostics',
    () async {
      final drafts = [subscriptionNode()];
      final issues = [_issue];
      fetcher.document = SubscriptionDocument(
        name: '快照',
        nodes: drafts,
        issues: issues,
        skippedNodes: 1,
      );
      final review = await _preview(import);
      drafts.clear();
      issues.clear();
      expect(() => review.document.nodes.clear(), throwsUnsupportedError);
      expect(
        () => review.document.nodes.single.options.alpn.add('h2'),
        throwsUnsupportedError,
      );
      await groups.acceptReview(review, SubscriptionCancellation());
      expect((await nodes.watchNodes().first).single.name, '日本 01');
      expect((await groups.watchGroups().first).single.issues, hasLength(1));
    },
  );

  test(
    'cancelled, expired, future-dated or foreign previews cannot write secrets or rows',
    () async {
      fetcher.document = _partial();
      final review = await _preview(import);
      await expectLater(
        groups.acceptReview(review, SubscriptionCancellation()..cancel()),
        throwsA(isA<SubscriptionCancelled>()),
      );
      now = review.createdAt.subtract(const Duration(seconds: 1));
      await expectLater(
        groups.acceptReview(review, SubscriptionCancellation()),
        throwsA(isA<NodeException>()),
      );
      now = review.createdAt.add(subscriptionReviewLifetime);
      await expectLater(
        groups.acceptReview(review, SubscriptionCancellation()),
        throwsA(isA<NodeException>()),
      );
      final foreign = SubscriptionReview(
        source: review.source,
        document: review.document,
        createdAt: now,
      );
      await expectLater(
        groups.acceptReview(foreign, SubscriptionCancellation()),
        throwsA(isA<NodeException>()),
      );
      expect(protected, 0);
      expect(await db.select(db.nodeGroups).get(), isEmpty);
    },
  );

  test(
    'duplicate imported after preview is rejected before any new secret is protected',
    () async {
      fetcher.document = _partial();
      final review = await _preview(import);
      fetcher.document = subscriptionDocument();
      await import();
      final count = protected;
      await expectLater(
        groups.acceptReview(review, SubscriptionCancellation()),
        throwsA(isA<NodeException>()),
      );
      expect(protected, count);
      expect(await db.select(db.nodeGroups).get(), hasLength(1));
    },
  );

  test(
    'partial refresh keeps nodes, credentials, overrides, selection and successful metadata until acceptance',
    () async {
      final id = await import();
      final before = (await nodes.watchNodes().first).single;
      await nodes.select(before.id);
      await db.customStatement(
        'INSERT INTO node_overrides (node_id, alias, favorite, hidden) VALUES (?, ?, 1, 0)',
        [before.id, '我的别名'],
      );
      final original = (await groups.watchGroups().first).single;
      now = now.add(const Duration(hours: 1));
      fetcher.document = _partial();
      final count = protected;
      final review = await _preview(() => refresh(id));
      final retained = (await groups.watchGroups().first).single;
      expect(retained.updateError, contains('兼容'));
      expect(retained.used, original.used);
      expect(retained.updatedAt, original.updatedAt);
      expect(retained.attemptedAt, now);
      expect(
        (await nodes.watchNodes().first).single.credential,
        before.credential,
      );
      expect(await nodes.watchSelectedId().first, before.id);
      expect(protected, count);
      await groups.acceptReview(review, SubscriptionCancellation());
      expect(fetcher.calls, 2);
      final after = (await nodes.watchNodes().first).single;
      expect(after.id, before.id);
      expect(after.credential, before.credential);
      expect(after.name, '我的别名');
      expect(after.favorite, isTrue);
      final committed = (await groups.watchGroups().first).single;
      expect(committed.updateError, isEmpty);
      expect(committed.used, isNull);
      expect(committed.updatedAt, now);
      expect(committed.issues.single.item, 2);
    },
  );

  test(
    'renamed, successfully updated and deleted groups reject stale previews',
    () async {
      final id = await import();
      fetcher.document = _partial();
      var review = await _preview(() => refresh(id));
      await groups.rename((await groups.watchGroups().first).single, '新名称');
      await expectLater(
        groups.acceptReview(review, SubscriptionCancellation()),
        throwsA(isA<NodeException>()),
      );
      review = await _preview(() => refresh(id));
      fetcher.document = subscriptionDocument();
      await refresh(id);
      await expectLater(
        groups.acceptReview(review, SubscriptionCancellation()),
        throwsA(isA<NodeException>()),
      );
      fetcher.document = _partial();
      review = await _preview(() => refresh(id));
      await groups.delete(id);
      await expectLater(
        groups.acceptReview(review, SubscriptionCancellation()),
        throwsA(isA<NodeException>()),
      );
      expect(await db.select(db.nodeGroups).get(), isEmpty);
      expect(await db.select(db.nodes).get(), isEmpty);
    },
  );

  test(
    'cancellation while protecting accepted nodes rolls back the complete import',
    () async {
      fetcher.document = _partial();
      final review = await _preview(import);
      final cancellation = SubscriptionCancellation();
      secrets.onProtect = cancellation.cancel;
      await expectLater(
        groups.acceptReview(review, cancellation),
        throwsA(isA<SubscriptionCancelled>()),
      );
      expect(await db.select(db.nodeGroups).get(), isEmpty);
      expect(await db.select(db.nodes).get(), isEmpty);
      secrets.onProtect = null;
      await groups.acceptReview(review, SubscriptionCancellation());
      expect(await db.select(db.nodeGroups).get(), hasLength(1));
    },
  );

  test('only one concurrent acceptance can apply a preview', () async {
    fetcher.document = _partial();
    final review = await _preview(import);
    final first = groups.acceptReview(review, SubscriptionCancellation());
    await expectLater(
      groups.acceptReview(review, SubscriptionCancellation()),
      throwsA(isA<NodeException>()),
    );
    await first;
    expect(await db.select(db.nodeGroups).get(), hasLength(1));
  });

  test(
    'provider notices do not require confirmation; legacy skip counts still do',
    () async {
      fetcher.document = SubscriptionDocument(
        name: '提示',
        nodes: [subscriptionNode()],
        skippedNodes: 1,
        issues: const [
          SubscriptionIssue(
            kind: SubscriptionIssueKind.notice,
            item: 1,
            reason: '服务商提示信息，不是可连接节点',
          ),
        ],
      );
      final id = await import();
      expect(
        (await groups.watchGroups().first).single.issues.single.kind,
        SubscriptionIssueKind.notice,
      );
      fetcher.document = SubscriptionDocument(
        name: '旧格式',
        nodes: [subscriptionNode()],
        skippedNodes: 2,
      );
      final review = await _preview(() => refresh(id));
      expect(review.document.requiresReview, isTrue);
    },
  );

  test(
    'automatic maintenance keeps old data without repeatedly fetching partial results',
    () async {
      await import();
      final original = (await nodes.watchNodes().first).single;
      now = now.add(const Duration(days: 2));
      fetcher.document = _partial(
        nodes: [subscriptionNode(name: '新节点', server: 'new.example.test')],
      );
      final controller = SubscriptionController(groups);
      addTearDown(controller.dispose);
      final maintenance = SubscriptionMaintenance(
        groups,
        controller,
        now: () => now,
      );
      maintenance.resume();
      addTearDown(maintenance.suspend);
      await maintenance.checkDue();
      expect(maintenance.lastError, contains('兼容'));
      expect((await nodes.watchNodes().first).single.id, original.id);
      await maintenance.checkDue();
      expect(fetcher.calls, 2);
    },
  );

  test(
    'controller suspend cancels acceptance and waits for its work',
    () async {
      fetcher.document = _partial();
      final review = await _preview(import);
      final controller = SubscriptionController(groups);
      addTearDown(controller.dispose);
      final blocked = Completer<SubscriptionDocument>();
      fetcher.handler = (_, __) => blocked.future;
      final refreshing = controller.importUrl(
        'https://other.example.test/sub',
        SubscriptionCancellation(),
      );
      final expectation = expectLater(
        refreshing,
        throwsA(isA<SubscriptionCancelled>()),
      );
      await Future<void>.delayed(Duration.zero);
      final suspension = controller.suspend();
      blocked.complete(_partial());
      await expectation;
      await suspension;
      await expectLater(
        controller.acceptReview(review),
        throwsA(isA<SubscriptionCancelled>()),
      );
      expect(await db.select(db.nodeGroups).get(), isEmpty);
      controller.resume();
      await controller.acceptReview(review);
      expect(await db.select(db.nodeGroups).get(), hasLength(1));
    },
  );

  test(
    'schema 6 migrates safely to 7 preserving groups, credentials, overrides and preferences on disk',
    () async {
      await db.close();
      final directory = await Directory.systemTemp.createTemp(
        'rainlink-compatibility-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/migration.sqlite');
      var persisted = AppDatabase(NativeDatabase(file));
      var repository = DriftGroupRepository(persisted, secrets, fetcher);
      final id = await repository.importUrl(
        'https://example.test/sub',
        SubscriptionCancellation(),
      );
      await repository.select(id);
      final oldNodes = await persisted.select(persisted.nodes).get();
      final oldGroups = await persisted.select(persisted.nodeGroups).get();
      final oldPreferences =
          await persisted.select(persisted.preferences).get();
      await persisted.customStatement(
        'INSERT INTO node_overrides (node_id, alias, favorite) VALUES (?, ?, 1)',
        [oldNodes.single.id, '保留别名'],
      );
      await persisted.customStatement(
        'ALTER TABLE node_groups DROP COLUMN compatibility_issues',
      );
      await persisted.customStatement('PRAGMA user_version = 6');
      await persisted.customStatement('DROP TABLE traffic_source_checkpoints');
      await persisted.customStatement(
        'ALTER TABLE traffic_checkpoints DROP COLUMN epoch',
      );
      await persisted.customStatement(
        'ALTER TABLE traffic_checkpoints DROP COLUMN sampled_at',
      );
      await persisted.close();
      persisted = AppDatabase(NativeDatabase(file));
      addTearDown(persisted.close);
      repository = DriftGroupRepository(persisted, secrets, fetcher);
      final migrated = (await repository.watchGroups().first).single;
      expect(migrated.issues, isEmpty);
      expect(
        (await persisted.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        8,
      );
      expect(
        (await persisted.select(persisted.nodes).get()).map((n) => n.toJson()),
        oldNodes.map((n) => n.toJson()),
      );
      expect(
        (await persisted.select(persisted.preferences).get()).map(
          (p) => p.toJson(),
        ),
        oldPreferences.map((p) => p.toJson()),
      );
      expect(
        (await persisted.select(persisted.nodeGroups).getSingle()).urlCipher,
        oldGroups.single.urlCipher,
      );
      final node =
          (await DriftNodeRepository(persisted, secrets).watchNodes().first)
              .single;
      expect(node.name, '保留别名');
      expect(node.favorite, isTrue);
      fetcher.document = _partial();
      final review = await _preview(
        () => repository.refresh(id, SubscriptionCancellation()),
      );
      await repository.acceptReview(review, SubscriptionCancellation());
      final raw = await persisted.select(persisted.nodeGroups).getSingle();
      expect(jsonDecode(raw.compatibilityIssues), hasLength(1));
    },
  );
}
