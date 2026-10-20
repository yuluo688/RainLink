import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/data/chains/chain_records.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/groups/drift_group_repository.dart';
import 'package:rainlink/data/nodes/drift_node_overrides_repository.dart';
import 'package:rainlink/data/nodes/drift_node_repository.dart';
import 'package:rainlink/domain/chains/proxy_chain.dart';
import 'package:rainlink/domain/groups/node_group.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'support/subscription_fixtures.dart';

void main() {
  test(
    'v4 migration keeps nodes, selection and encrypted credentials on reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'rainlink-overrides-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/database.sqlite');
      final secrets = TestSecretStore();
      var db = AppDatabase(NativeDatabase(file));
      var nodes = DriftNodeRepository(db, secrets);
      final node = await nodes.save(subscriptionNode());
      await nodes.select(node.id);
      await db.customStatement('DROP TABLE node_overrides');
      await db.customStatement('DROP TABLE traffic_buckets');
      await db.customStatement('DROP TABLE traffic_sources');
      await db.customStatement('DROP TABLE traffic_checkpoints');
      await db.customStatement('DROP TABLE traffic_source_checkpoints');
      await db.customStatement(
        'ALTER TABLE node_groups DROP COLUMN compatibility_issues',
      );
      await db.customStatement('PRAGMA user_version = 4');
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      nodes = DriftNodeRepository(db, secrets);
      var local = DriftNodeOverridesRepository(db);
      final migrated = (await nodes.watchNodes().first).single;
      expect(migrated.credential, node.credential);
      expect(migrated.favorite, isFalse);
      expect(migrated.hidden, isFalse);
      expect(await nodes.watchSelectedId().first, node.id);
      await local.setFavorite(node.id, true);
      await local.setAlias(node.id, '主线路');
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      nodes = DriftNodeRepository(db, secrets);
      local = DriftNodeOverridesRepository(db);
      final reopened = (await nodes.watchNodes().first).single;
      expect(reopened.favorite, isTrue);
      expect(reopened.name, '主线路');
      expect(reopened.sourceName, node.name);
      expect(reopened.revision, node.revision);
      expect(reopened.toHost().containsKey('favorite'), isFalse);
      await local.setAlias(node.id, '');
      expect((await nodes.watchNodes().first).single.name, node.name);
      await nodes.delete(node.id);
      expect(await db.select(db.nodeOverrides).get(), isEmpty);
    },
  );

  test(
    'subscription rename/reorder and concurrent update preserve local choices',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final secrets = TestSecretStore();
      final fetcher =
          TestSubscriptionFetcher()
            ..document = subscriptionDocument(
              nodes: [
                subscriptionNode(name: '日本 01'),
                subscriptionNode(name: '新加坡 01', server: 'sg.example.test'),
              ],
            );
      final groups = DriftGroupRepository(db, secrets, fetcher);
      final nodes = DriftNodeRepository(db, secrets);
      final local = DriftNodeOverridesRepository(db);
      final group = await groups.importUrl(
        'https://example.test/sub',
        SubscriptionCancellation(),
      );
      final first = (await nodes.watchNodes().first).firstWhere(
        (n) => n.name == '日本 01',
      );
      final waiting = Completer<SubscriptionDocument>();
      final started = Completer<void>();
      fetcher.handler = (_, __) {
        started.complete();
        return waiting.future;
      };
      final refreshing = groups.refresh(group, SubscriptionCancellation());
      await started.future;
      await local.setAlias(first.id, '工作线路');
      await local.setFavorite(first.id, true);
      await local.setHidden(first.id, true);
      waiting.complete(
        subscriptionDocument(
          nodes: [
            subscriptionNode(name: '新加坡 01', server: 'sg.example.test'),
            subscriptionNode(name: '日本 改名'),
          ],
        ),
      );
      await refreshing;
      final saved = (await nodes.watchNodes().first).firstWhere(
        (n) => n.id == first.id,
      );
      expect(saved.name, '工作线路');
      expect(saved.sourceName, '日本 改名');
      expect(saved.favorite, isTrue);
      expect(saved.hidden, isTrue);
      expect(saved.revision, first.revision + 1);
      expect(
        (await db.select(db.nodes).get())
            .firstWhere((n) => n.id == first.id)
            .name,
        '日本 改名',
      );
      await groups.select(group);
      expect(await nodes.watchSelectedId().first, isNot(first.id));
      final other = (await nodes.watchNodes().first).firstWhere(
        (n) => n.id != first.id,
      );
      await local.setHidden(other.id, true);
      expect(await nodes.watchSelectedId().first, isNull);
      await expectLater(groups.select(group), throwsA(isA<NodeException>()));
      await local.setHidden(first.id, false);
      await groups.select(group);
      expect(await nodes.watchSelectedId().first, first.id);
      expect(
        (await nodes.watchNodes().first)
            .firstWhere((n) => n.id == first.id)
            .favorite,
        isTrue,
      );
    },
  );

  test(
    'hidden nodes cannot be selected directly but existing chain references survive',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final nodes = DriftNodeRepository(db, TestSecretStore());
      final local = DriftNodeOverridesRepository(db);
      final a = await nodes.save(subscriptionNode());
      final b = await nodes.save(
        subscriptionNode(name: '第二个', server: 'two.example.test'),
      );
      final chain = ProxyChain(
        id: 'saved-chain',
        name: '已保存的链',
        revision: 1,
        hopIds: [a.id, b.id],
      );
      final before = await resolveChain(db, chain);
      await nodes.select(a.id);
      await local.setAlias(a.id, '本地名称');
      await local.setHidden(a.id, true);
      await expectLater(nodes.select(a.id), throwsA(isA<NodeException>()));
      final after = await resolveChain(db, chain);
      expect(after.hops.first.name, '本地名称');
      expect(after.hops.first.hidden, isTrue);
      expect(after.hops.first.credential, before.hops.first.credential);
      expect(after.fingerprint, before.fingerprint);
      expect(await nodes.watchSelectedId().first, isNull);
      await local.setHidden(a.id, false);
      await nodes.select(a.id);
      expect(await nodes.watchSelectedId().first, a.id);
    },
  );

  test(
    'removed subscription identities drop overrides without transferring them to replacements',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final secrets = TestSecretStore();
      final fetcher = TestSubscriptionFetcher();
      final groups = DriftGroupRepository(db, secrets, fetcher);
      final nodes = DriftNodeRepository(db, secrets);
      final local = DriftNodeOverridesRepository(db);
      final group = await groups.importUrl(
        'https://example.test/sub',
        SubscriptionCancellation(),
      );
      final first = (await nodes.watchNodes().first).single;
      await local.setFavorite(first.id, true);
      await local.setAlias(first.id, '旧节点');
      fetcher.document = subscriptionDocument(
        nodes: [subscriptionNode(server: 'new.example.test')],
      );
      await groups.refresh(group, SubscriptionCancellation());
      final replacement = (await nodes.watchNodes().first).single;
      expect(replacement.id, isNot(first.id));
      expect(replacement.favorite, isFalse);
      expect(replacement.hasAlias, isFalse);
      expect(await db.select(db.nodeOverrides).get(), isEmpty);
      await local.setFavorite(replacement.id, true);
      await groups.delete(group);
      expect(await db.select(db.nodeOverrides).get(), isEmpty);
    },
  );

  test('invalid alias and stale identities never create orphan rows', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final nodes = DriftNodeRepository(db, TestSecretStore());
    final local = DriftNodeOverridesRepository(db);
    final node = await nodes.save(subscriptionNode());
    await expectLater(
      local.setAlias(node.id, 'a' * 129),
      throwsA(isA<NodeException>()),
    );
    await expectLater(
      local.setAlias(node.id, 'bad\nname'),
      throwsA(isA<NodeException>()),
    );
    await nodes.delete(node.id);
    await expectLater(
      local.setFavorite(node.id, true),
      throwsA(isA<NodeException>()),
    );
    await expectLater(
      local.setHidden('missing', true),
      throwsA(isA<NodeException>()),
    );
    expect(await db.select(db.nodeOverrides).get(), isEmpty);
  });
}
