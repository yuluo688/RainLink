import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/groups/drift_group_repository.dart';
import 'package:rainlink/data/nodes/drift_node_repository.dart';
import 'package:rainlink/domain/groups/node_group.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'support/subscription_fixtures.dart';

void main() {
  late AppDatabase db;
  late TestSecretStore secrets;
  late TestSubscriptionFetcher fetcher;
  late DriftNodeRepository nodes;
  late DriftGroupRepository groups;
  var now = DateTime.utc(2026, 10, 16);
  setUp(() {
    now = DateTime.utc(2026, 10, 16);
    db = AppDatabase(NativeDatabase.memory());
    secrets = TestSecretStore();
    fetcher = TestSubscriptionFetcher();
    nodes = DriftNodeRepository(db, secrets);
    groups = DriftGroupRepository(db, secrets, fetcher, now: () => now);
  });
  tearDown(() async => db.close());
  Future<String> import() => groups.importUrl(
      'https://example.test/sub?token=fixture', SubscriptionCancellation());
  Future<void> refresh(String id) =>
      groups.refresh(id, SubscriptionCancellation());

  test(
      'subscription automatically forms one group with protected URL, secrets and metadata',
      () async {
    final id = await import();
    final group = (await groups.watchGroups().first).single;
    expect(group.id, id);
    expect(group.name, '测试订阅');
    expect(group.kind, GroupKind.subscription);
    expect(group.used, 5120);
    expect(group.total, 1048576);
    expect(group.expiresAt, DateTime.utc(2030, 1, 1));
    final node = (await nodes.watchNodes().first).single;
    expect(node.groupId, id);
    expect(node.subscriptionManaged, isTrue);
    final rawGroup = await db.select(db.nodeGroups).getSingle();
    expect(rawGroup.urlCipher, startsWith('opaque-'));
    expect(rawGroup.toJson().toString(), isNot(contains('token=fixture')));
    final rawNode = await db.select(db.nodes).getSingle();
    expect(rawNode.toJson().toString(), isNot(contains('fixture-password')));
    await expectLater(import(), throwsA(isA<NodeException>()));
    expect(fetcher.calls, 1);
    await groups.select(id);
    expect(await nodes.watchSelectedId().first, node.id);
  });

  test(
      'no-op update preserves ID and revision, rename preserves selection, secret rotation advances revision',
      () async {
    final id = await import();
    final original = (await nodes.watchNodes().first).single;
    await nodes.select(original.id);
    await refresh(id);
    var node = (await nodes.watchNodes().first).single;
    expect(node.id, original.id);
    expect(node.revision, original.revision);
    expect(node.credential, original.credential);
    fetcher.document =
        subscriptionDocument(nodes: [subscriptionNode(name: '日本 新名称')]);
    await refresh(id);
    node = (await nodes.watchNodes().first).single;
    expect(node.id, original.id);
    expect(node.revision, original.revision + 1);
    expect(await nodes.watchSelectedId().first, original.id);
    fetcher.document = subscriptionDocument(
        nodes: [subscriptionNode(name: '日本 新名称', password: 'rotated-fixture')]);
    await refresh(id);
    node = (await nodes.watchNodes().first).single;
    expect(node.id, original.id);
    expect(node.revision, original.revision + 2);
    expect((await secrets.reveal(node.id, node.credential)).password,
        'rotated-fixture');
  });

  test(
      'refresh preserves manually moved nodes and falls back when selected imported node disappears',
      () async {
    final id = await import();
    final old = (await nodes.watchNodes().first).single;
    final manual = await nodes
        .save(subscriptionNode(name: '手动节点', server: 'manual.example.test'));
    expect(manual.groupId, isNull);
    await groups.moveUngrouped(manual.id, id);
    await expectLater(
        groups.moveUngrouped(manual.id, id), throwsA(isA<NodeException>()));
    await expectLater(
        groups.moveUngrouped(old.id, id), throwsA(isA<NodeException>()));
    await nodes.select(old.id);
    fetcher.document = subscriptionDocument(
        nodes: [subscriptionNode(name: '美国 02', server: 'us.example.test')],
        metadata: false);
    await refresh(id);
    final after = await nodes.watchNodes().first;
    expect(after, hasLength(2));
    expect(after.any((n) => n.id == old.id), isFalse);
    expect(after.singleWhere((n) => n.id == manual.id).groupId, id);
    expect(
        after.map((n) => n.id), contains(await nodes.watchSelectedId().first));
    final group = (await groups.watchGroups().first).single;
    expect(group.total, isNull);
    expect(group.expiresAt, isNull);
    await nodes.select(manual.id);
    final other = await groups.createManual('工作');
    final ungrouped = await nodes
        .save(subscriptionNode(name: '备用', server: 'other.example.test'));
    await groups.moveUngrouped(ungrouped.id, other);
    await groups.select(other);
    await groups.select(id);
    expect(await nodes.watchSelectedId().first, manual.id);
  });

  test(
      'reordered accounts sharing public identity retain the correct selected credential',
      () async {
    fetcher.document = subscriptionDocument(nodes: [
      subscriptionNode(password: 'account-a'),
      subscriptionNode(password: 'account-b')
    ]);
    final id = await import();
    final first = (await nodes.watchNodes().first).first;
    final originalSecret =
        (await secrets.reveal(first.id, first.credential)).password;
    await nodes.select(first.id);
    fetcher.document = subscriptionDocument(nodes: [
      subscriptionNode(password: 'account-b'),
      subscriptionNode(password: 'account-a')
    ]);
    await refresh(id);
    final selected =
        (await nodes.watchNodes().first).singleWhere((n) => n.id == first.id);
    expect((await secrets.reveal(selected.id, selected.credential)).password,
        originalSecret);
    expect(selected.revision, first.revision);
    expect(await nodes.watchSelectedId().first, first.id);
  });

  test('subscription nodes cannot be edited or deleted individually', () async {
    await import();
    final original = (await nodes.watchNodes().first).single;
    await expectLater(nodes.delete(original.id), throwsA(isA<NodeException>()));
    await expectLater(
        nodes.save(NodeDraft(
            name: original.name,
            protocol: original.protocol,
            server: original.server,
            port: original.port,
            authenticate: true,
            original: original)),
        throwsA(isA<NodeException>()));
    expect(await nodes.watchNodes().first, hasLength(1));
  });

  test(
      'failed or cancelled updates retain nodes, selection and previous successful metadata',
      () async {
    final id = await import();
    final before = (await nodes.watchNodes().first).single;
    await nodes.select(before.id);
    now = now.add(const Duration(hours: 1));
    fetcher.handler =
        (_, __) async => throw const NodeException('订阅服务器返回 HTTP 503');
    await expectLater(refresh(id), throwsA(isA<NodeException>()));
    var group = (await groups.watchGroups().first).single;
    expect(group.updateError, contains('503'));
    expect(group.used, 5120);
    expect(group.updatedAt, isNot(now));
    expect(group.attemptedAt, now);
    expect(await nodes.watchSelectedId().first, before.id);
    expect(
        (await nodes.watchNodes().first).single.credential, before.credential);
    fetcher.handler = null;
    final token = SubscriptionCancellation()..cancel();
    await expectLater(
        groups.refresh(id, token), throwsA(isA<SubscriptionCancelled>()));
    group = (await groups.watchGroups().first).single;
    expect(group.updateError, contains('503'));
  });

  test(
      'crypto failure and cancellation during preparation leave no partial group or nodes',
      () async {
    secrets.fail = true;
    await expectLater(import(), throwsA(isA<NodeException>()));
    expect(await groups.watchGroups().first, isEmpty);
    expect(await nodes.watchNodes().first, isEmpty);
    secrets.fail = false;
    final token = SubscriptionCancellation();
    secrets.onProtect = token.cancel;
    await expectLater(groups.importUrl('https://example.test/sub', token),
        throwsA(isA<SubscriptionCancelled>()));
    expect(await groups.watchGroups().first, isEmpty);
    expect(await nodes.watchNodes().first, isEmpty);
  });

  test(
      'deleting during fetch never resurrects the subscription; moved nodes return to ungrouped',
      () async {
    final id = await import();
    final manual = await nodes
        .save(subscriptionNode(name: '本地', server: 'local.example.test'));
    await groups.moveUngrouped(manual.id, id);
    await nodes.select(manual.id);
    final started = Completer<void>();
    final pending = Completer<SubscriptionDocument>();
    fetcher.handler = (_, __) {
      started.complete();
      return pending.future;
    };
    final operation = refresh(id);
    final expectation = expectLater(operation, throwsA(isA<NodeException>()));
    await started.future;
    await groups.delete(id);
    pending.complete(subscriptionDocument());
    await expectation;
    expect(await groups.watchGroups().first, isEmpty);
    final after = (await nodes.watchNodes().first).single;
    expect(after.id, manual.id);
    expect(after.groupId, isNull);
    expect(await nodes.watchSelectedId().first, manual.id);
  });

  test(
      'rename is preserved and a concurrent configuration change prevents stale refresh',
      () async {
    final id = await import();
    await groups.rename((await groups.watchGroups().first).single, '我的订阅');
    await refresh(id);
    expect((await groups.watchGroups().first).single.name, '我的订阅');
    final started = Completer<void>();
    final pending = Completer<SubscriptionDocument>();
    fetcher.handler = (_, __) {
      started.complete();
      return pending.future;
    };
    final expectation = expectLater(refresh(id), throwsA(isA<NodeException>()));
    await started.future;
    await groups.setAutoUpdate(
        (await groups.watchGroups().first).single, false);
    pending.complete(subscriptionDocument(
        name: '服务商改名', nodes: [subscriptionNode(name: '变更')]));
    await expectation;
    expect((await nodes.watchNodes().first).single.name, '日本 01');
    expect((await groups.watchGroups().first).single.autoUpdate, isFalse);
  });

  test(
      'removing subscription clears invalid selection; deleting manual groups keeps their nodes',
      () async {
    final id = await import();
    await groups.select(id);
    await groups.delete(id);
    expect(await nodes.watchSelectedId().first, isNull);
    final manual = await nodes.save(subscriptionNode());
    final manualGroup = await groups.createManual('自建');
    await groups.moveUngrouped(manual.id, manualGroup);
    await groups.select(manualGroup);
    await groups.delete(manualGroup);
    expect((await nodes.watchNodes().first).single.groupId, isNull);
    expect(await nodes.watchSelectedId().first, manual.id);
    await expectLater(
        groups.select(manualGroup), throwsA(isA<NodeException>()));
  });

  test(
      'v2 migration preserves nodes, credentials and selection and adds group columns',
      () async {
    await db.close();
    final old = AppDatabase(NativeDatabase.memory(setup: (sqlite) {
      sqlite.execute(
          'CREATE TABLE preferences (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)');
      sqlite.execute(
          'CREATE TABLE nodes (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, protocol TEXT NOT NULL, server TEXT NOT NULL, port INTEGER NOT NULL, tls INTEGER NOT NULL DEFAULT 0, credential TEXT NOT NULL DEFAULT \'\', revision INTEGER NOT NULL DEFAULT 1)');
      sqlite.execute(
          "INSERT INTO nodes VALUES ('old', '旧节点', 'http', 'localhost', 8080, 0, 'old-cipher', 4)");
      sqlite.execute(
          "INSERT INTO preferences VALUES ('connection.selected_node', 'old')");
      sqlite.execute('PRAGMA user_version = 2');
    }));
    addTearDown(old.close);
    final repository = DriftNodeRepository(old, secrets);
    final node = (await repository.watchNodes().first).single;
    expect(node.id, 'old');
    expect(node.credential, 'old-cipher');
    expect(node.revision, 4);
    expect(node.groupId, isNull);
    expect(node.options.transport, 'tcp');
    expect(await repository.watchSelectedId().first, 'old');
    expect(
        await DriftGroupRepository(old, secrets, fetcher).watchGroups().first,
        isEmpty);
  });

  test('group metadata and node settings survive reopening the database',
      () async {
    await db.close();
    final directory = await Directory.systemTemp.createTemp('rainlink-groups-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/test.sqlite');
    var persisted = AppDatabase(NativeDatabase(file));
    var repo = DriftGroupRepository(persisted, secrets, fetcher);
    final id = await repo.importUrl(
        'https://example.test/sub', SubscriptionCancellation());
    await repo.select(id);
    await persisted.close();
    persisted = AppDatabase(NativeDatabase(file));
    addTearDown(persisted.close);
    repo = DriftGroupRepository(persisted, secrets, fetcher);
    expect((await repo.watchGroups().first).single.used, 5120);
    await repo.refresh(id, SubscriptionCancellation());
    expect(await DriftNodeRepository(persisted, secrets).watchNodes().first,
        hasLength(1));
    expect(
        await DriftNodeRepository(persisted, secrets).watchSelectedId().first,
        isNotNull);
  });
}
