import 'dart:convert';
import '../../domain/chains/proxy_chain.dart';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../domain/groups/node_group.dart';
import '../../domain/groups/subscription_issue.dart';
import '../../domain/groups/subscription_review.dart';
import '../../domain/nodes/proxy_node.dart';
import '../../domain/nodes/node_validation.dart';
import '../database/app_database.dart';
import '../nodes/node_records.dart';
import '../subscriptions/subscription_parser.dart';

class DriftGroupRepository
    implements GroupRepository, SubscriptionReviewRepository {
  DriftGroupRepository(this.database, this.secrets, this.fetcher,
      {DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final AppDatabase database;
  final SecretStore secrets;
  final SubscriptionFetcher fetcher;
  final DateTime Function() _now;
  // Weak keys keep discarded/background previews and their secrets collectible.
  final _reviews = Expando<_ReviewState>();

  @override
  Stream<List<NodeGroup>> watchGroups() => (database.select(database.nodeGroups)
        ..orderBy([(g) => OrderingTerm.asc(g.name)]))
      .watch()
      .map((rows) => rows
          .map((g) => NodeGroup(
              id: g.id,
              name: g.name,
              kind: GroupKind.values.byName(g.kind),
              uploaded: g.uploaded,
              downloaded: g.downloaded,
              total: g.total,
              expiresAt: g.expiresAt?.toUtc(),
              updatedAt: g.updatedAt?.toUtc(),
              attemptedAt: g.attemptedAt?.toUtc(),
              updateError: g.updateError,
              skippedNodes: g.skippedNodes,
              issues: _readIssues(g.compatibilityIssues),
              autoUpdate: g.autoUpdate,
              intervalHours: g.intervalHours,
              revision: g.revision))
          .toList());

  List<SubscriptionIssue> _readIssues(String encoded) {
    try {
      final value = jsonDecode(encoded);
      if (value is! List || value.length > maxSubscriptionNodes + 32) {
        throw const FormatException();
      }
      final issues = value.map(SubscriptionIssue.fromJson).toList();
      if (issues.any((issue) => issue == null)) {
        throw const FormatException();
      }
      return List.unmodifiable(issues.whereType<SubscriptionIssue>());
    } on FormatException {
      throw const NodeException('订阅兼容信息损坏，请重新更新订阅');
    }
  }

  String _writeIssues(SubscriptionDocument document) =>
      jsonEncode(document.issues.map((issue) => issue.toJson()).toList());

  Never _requireReview(Uri url, SubscriptionDocument document,
      {NodeGroupRecord? group}) {
    final review = SubscriptionReview(
        source: url,
        document: document,
        createdAt: _now(),
        groupId: group?.id,
        groupRevision: group?.revision);
    _reviews[review] = _ReviewState.pending;
    throw SubscriptionReviewRequired(review);
  }

  Future<NodeGroupRecord> _group(String id) async =>
      await (database.select(database.nodeGroups)
            ..where((g) => g.id.equals(id)))
          .getSingleOrNull() ??
      (throw const NodeException('分组已被删除'));

  String _name(String name) {
    final result = name.trim();
    if (result.isEmpty ||
        result.length > 128 ||
        result.contains(RegExp(r'[\x00-\x1F]'))) {
      throw const NodeException('分组名称应为 1–128 个字符');
    }
    return result;
  }

  @override
  Future<String> createManual(String name) async {
    final id = newRecordId();
    await database.into(database.nodeGroups).insert(NodeGroupsCompanion.insert(
        id: id, name: _name(name), kind: GroupKind.manual.name));
    return id;
  }

  @override
  Future<String> importUrl(String input, SubscriptionCancellation cancellation,
      {bool autoUpdate = true}) async {
    cancellation.check();
    final url = validateSubscriptionUrl(input);
    final hash = sha256.convert(utf8.encode(url.toString())).toString();
    await _checkDuplicate(hash);
    final document = await fetcher.fetch(url, cancellation);
    cancellation.check();
    if (document.requiresReview) _requireReview(url, document);
    return _importDocument(url, document, cancellation, autoUpdate: autoUpdate);
  }

  @override
  Future<String> acceptReview(
      SubscriptionReview review, SubscriptionCancellation cancellation,
      {bool autoUpdate = true}) async {
    cancellation.check();
    final age = _now().difference(review.createdAt);
    if (_reviews[review] != _ReviewState.pending ||
        age.isNegative ||
        age >= subscriptionReviewLifetime) {
      throw const NodeException('兼容预览已失效，请重新获取订阅');
    }
    _reviews[review] = _ReviewState.applying;
    try {
      final id = review.groupId;
      if (id == null) {
        final created = await _importDocument(
            review.source, review.document, cancellation,
            autoUpdate: autoUpdate);
        _reviews[review] = _ReviewState.consumed;
        return created;
      }
      final group = await _group(id);
      if (group.revision != review.groupRevision ||
          group.kind != GroupKind.subscription.name) {
        throw const NodeException('分组已修改，请重新获取订阅');
      }
      await _replaceDocument(group, review.document, cancellation);
      _reviews[review] = _ReviewState.consumed;
      return id;
    } on Exception {
      _reviews[review] = _ReviewState.pending;
      rethrow;
    }
  }

  Future<String> _importDocument(Uri url, SubscriptionDocument document,
      SubscriptionCancellation cancellation,
      {required bool autoUpdate}) async {
    cancellation.check();
    final hash = sha256.convert(utf8.encode(url.toString())).toString();
    await _checkDuplicate(hash);
    final id = newRecordId();
    final cipher = await secrets.protect(id, '', url.toString());
    final prepared = await _prepare(id, document, const [], cancellation);
    await database.transaction(() async {
      cancellation.check();
      await _checkDuplicate(hash);
      await database.into(database.nodeGroups).insert(
          NodeGroupsCompanion.insert(
              id: id,
              name: _name(document.name),
              kind: GroupKind.subscription.name,
              urlCipher: Value(cipher),
              urlHash: Value(hash),
              uploaded: Value(document.uploaded),
              downloaded: Value(document.downloaded),
              total: Value(document.total),
              expiresAt: Value(document.expiresAt),
              updatedAt: Value(_now()),
              attemptedAt: Value(_now()),
              skippedNodes: Value(document.skippedNodes),
              compatibilityIssues: Value(_writeIssues(document)),
              autoUpdate: Value(autoUpdate),
              intervalHours: Value(document.intervalHours)));
      for (final node in prepared) {
        await database.into(database.nodes).insert(node);
      }
      cancellation.check();
    });
    return id;
  }

  Future<void> _checkDuplicate(String hash) async {
    if (await (database.select(database.nodeGroups)
              ..where((g) => g.urlHash.equals(hash)))
            .getSingleOrNull() !=
        null) {
      throw const NodeException('该订阅已添加，请在分组中更新');
    }
  }

  String _publicKey(NodeDraft draft, {bool includeName = true}) => jsonEncode({
        if (includeName) 'name': draft.name.trim(),
        'protocol': draft.protocol.wireName,
        'server': draft.server.trim(),
        'port': draft.port,
        'tls': draft.tls,
        'options': draft.options.toJson()
      });
  NodeDraft _draft(Node row) => NodeDraft(
      name: row.name,
      protocol: nodeFromRecord(row).protocol,
      server: row.server,
      port: row.port,
      tls: row.tls,
      options: nodeFromRecord(row).options);

  Future<List<NodesCompanion>> _prepare(
      String groupId,
      SubscriptionDocument document,
      List<Node> old,
      SubscriptionCancellation cancel) async {
    if (document.nodes.isEmpty ||
        document.nodes.length > maxSubscriptionNodes) {
      throw const NodeException('订阅节点数量无效');
    }
    final result = <NodesCompanion>[];
    final byPublic = <String, List<Node>>{};
    final endpoints = <String, List<Node>>{};
    for (final row in old) {
      byPublic.putIfAbsent(_publicKey(_draft(row)), () => []).add(row);
      endpoints
          .putIfAbsent(_publicKey(_draft(row), includeName: false), () => [])
          .add(row);
    }
    final newEndpointCounts = <String, int>{};
    for (final draft in document.nodes) {
      final k = _publicKey(draft, includeName: false);
      newEndpointCounts[k] = (newEndpointCounts[k] ?? 0) + 1;
    }
    final occurrences = <String, int>{};
    final matched = <String>{};
    final credentials = <String, NodeCredentials>{};
    Future<NodeCredentials> reveal(Node row) async =>
        credentials[row.id] ??= row.credential.isEmpty
            ? const NodeCredentials()
            : await secrets.reveal(row.id, row.credential);
    final publicKeys = document.nodes.map(_publicKey).toList();
    final planned = <int, Node>{};
    // Match credentials before ordinal positions: providers may reorder accounts
    // sharing the same name and endpoint. A selected account must not swap secrets.
    for (var index = 0; index < document.nodes.length; index++) {
      cancel.check();
      final draft = document.nodes[index];
      validateNode(draft);
      for (final candidate in byPublic[publicKeys[index]] ?? <Node>[]) {
        if (matched.contains(candidate.id)) continue;
        final auth = await reveal(candidate);
        if (auth.username == draft.username &&
            auth.password == draft.password &&
            auth.obfsPassword == draft.obfsPassword) {
          planned[index] = candidate;
          matched.add(candidate.id);
          break;
        }
      }
    }
    // A unique unmatched public identity is a password rotation.
    for (var index = 0; index < document.nodes.length; index++) {
      if (planned.containsKey(index)) continue;
      final candidates = (byPublic[publicKeys[index]] ?? <Node>[])
          .where((n) => !matched.contains(n.id))
          .toList();
      if (candidates.length != 1) continue;
      final remaining = [
        for (var i = 0; i < publicKeys.length; i++)
          if (!planned.containsKey(i) && publicKeys[i] == publicKeys[index]) i
      ];
      if (remaining.length == 1) {
        planned[index] = candidates.single;
        matched.add(candidates.single.id);
      }
    }
    for (var index = 0; index < document.nodes.length; index++) {
      final draft = document.nodes[index];
      cancel.check();
      final key = sha256.convert(utf8.encode(_publicKey(draft))).toString();
      final ordinal = occurrences.update(key, (v) => v + 1, ifAbsent: () => 0);
      final sourceKey = '$key:$ordinal';
      Node? existing = planned[index];
      if (existing == null) {
        final endpoint = _publicKey(draft, includeName: false);
        final candidates = endpoints[endpoint] ?? [];
        if (candidates.length == 1 &&
            newEndpointCounts[endpoint] == 1 &&
            !matched.contains(candidates.single.id)) {
          final auth = await reveal(candidates.single);
          if (auth.username == draft.username &&
              auth.password == draft.password &&
              auth.obfsPassword == draft.obfsPassword) {
            existing = candidates.single;
          }
        }
      }
      final id = existing?.id ?? newRecordId();
      var sameSecret = false;
      if (existing != null) {
        matched.add(id);
        final auth = await reveal(existing);
        sameSecret = auth.username == draft.username &&
            auth.password == draft.password &&
            auth.obfsPassword == draft.obfsPassword;
      }
      final needsSecret = draft.authenticate ||
          ![NodeProtocol.http, NodeProtocol.socks5].contains(draft.protocol);
      final cipher = sameSecret
          ? existing?.credential ?? ''
          : needsSecret
              ? await secrets.protect(id, draft.username, draft.password,
                  obfsPassword: draft.obfsPassword)
              : '';
      final samePublic =
          existing != null && _publicKey(_draft(existing)) == _publicKey(draft);
      result.add(NodesCompanion.insert(
          id: id,
          name: draft.name.trim(),
          protocol: draft.protocol.wireName,
          server: draft.server.trim(),
          port: draft.port,
          tls: Value(draft.tls),
          options: Value(jsonEncode(draft.options.toJson())),
          groupId: Value(groupId),
          sourceKey: Value(sourceKey),
          credential: Value(cipher),
          revision: Value(existing == null
              ? 1
              : existing.revision + (sameSecret && samePublic ? 0 : 1))));
    }
    cancel.check();
    return result;
  }

  @override
  Future<void> refresh(String id, SubscriptionCancellation cancellation) async {
    cancellation.check();
    final group = await _group(id);
    if (group.kind != GroupKind.subscription.name) {
      throw const NodeException('此分组不是订阅');
    }
    try {
      final url = validateSubscriptionUrl(
          (await secrets.reveal(id, group.urlCipher)).password);
      final document = await fetcher.fetch(url, cancellation);
      cancellation.check();
      if (document.requiresReview) _requireReview(url, document, group: group);
      await _replaceDocument(group, document, cancellation);
    } on SubscriptionCancelled {
      rethrow;
    } on Exception catch (error) {
      final message = error is NodeException ? error.message : '订阅更新失败，请重试';
      await (database.update(database.nodeGroups)
            ..where((g) => g.id.equals(id) & g.revision.equals(group.revision)))
          .write(NodeGroupsCompanion(
              attemptedAt: Value(_now()), updateError: Value(message)));
      if (error is SubscriptionReviewRequired ||
          error is SubscriptionContentException) {
        rethrow;
      }
      throw NodeException(message);
    }
  }

  Future<void> _replaceDocument(
      NodeGroupRecord group,
      SubscriptionDocument document,
      SubscriptionCancellation cancellation) async {
    final id = group.id;
    final old = await (database.select(database.nodes)
          ..where((n) => n.groupId.equals(id) & n.sourceKey.equals('').not()))
        .get();
    final prepared = await _prepare(id, document, old, cancellation);
    await database.transaction(() async {
      cancellation.check();
      final current = await _group(id);
      if (current.revision != group.revision) {
        throw const NodeException('分组已修改，请重新更新');
      }
      final remaining = prepared.map((n) => n.id.value).toSet();
      // Only subscription-owned nodes are replaced. Manually moved nodes survive.
      await (database.delete(database.nodes)
            ..where((n) =>
                n.groupId.equals(id) &
                n.sourceKey.equals('').not() &
                n.id.isNotIn(remaining)))
          .go();
      for (final node in prepared) {
        await database.into(database.nodes).insertOnConflictUpdate(node);
      }
      final all = (await (nodeQuery(database, includeHidden: false)
                ..where(database.nodes.groupId.equals(id)))
              .get())
          .map((row) => nodeFromJoined(database, row))
          .toList();
      final ids = all.map((n) => n.id).toSet();
      final remembered = ids.contains(current.lastSelectedNodeId)
          ? current.lastSelectedNodeId
          : all.firstOrNull?.id;
      final selected = await (database.select(database.preferences)
            ..where((p) => p.key.equals(selectedNodeKey)))
          .getSingleOrNull();
      if (old.any((n) => n.id == selected?.value) &&
          !ids.contains(selected?.value)) {
        if (remembered != null) {
          await database.into(database.preferences).insertOnConflictUpdate(
              PreferencesCompanion.insert(
                  key: selectedNodeKey, value: remembered));
        } else {
          await (database.delete(database.preferences)
                ..where((p) => p.key.equals(selectedNodeKey)))
              .go();
        }
      }
      await (database.update(database.nodeGroups)
            ..where((g) => g.id.equals(id)))
          .write(NodeGroupsCompanion(
              name:
                  Value(group.customName ? current.name : _name(document.name)),
              uploaded: Value(document.uploaded),
              downloaded: Value(document.downloaded),
              total: Value(document.total),
              expiresAt: Value(document.expiresAt),
              updatedAt: Value(_now()),
              attemptedAt: Value(_now()),
              updateError: const Value(''),
              skippedNodes: Value(document.skippedNodes),
              compatibilityIssues: Value(_writeIssues(document)),
              intervalHours: Value(document.intervalHours),
              lastSelectedNodeId: Value(remembered),
              revision: Value(group.revision + 1)));
      cancellation.check();
    });
  }

  @override
  Future<void> rename(NodeGroup group, String name) async {
    final count = await (database.update(database.nodeGroups)
          ..where(
              (g) => g.id.equals(group.id) & g.revision.equals(group.revision)))
        .write(NodeGroupsCompanion(
            name: Value(_name(name)),
            customName: const Value(true),
            revision: Value(group.revision + 1)));
    if (count == 0) throw const NodeException('分组已更新，请重试');
  }

  @override
  Future<void> setAutoUpdate(NodeGroup group, bool enabled) async {
    final count = await (database.update(database.nodeGroups)
          ..where(
              (g) => g.id.equals(group.id) & g.revision.equals(group.revision)))
        .write(NodeGroupsCompanion(
            autoUpdate: Value(enabled), revision: Value(group.revision + 1)));
    if (count == 0) throw const NodeException('分组已更新，请重试');
  }

  @override
  Future<void> select(String? groupId) => database.transaction(() async {
        final group = groupId == null ? null : await _group(groupId);
        final nodes = (await (nodeQuery(database, includeHidden: false)
                  ..where(groupId == null
                      ? database.nodes.groupId.isNull()
                      : database.nodes.groupId.equals(groupId)))
                .get())
            .map((row) => nodeFromJoined(database, row))
            .toList();
        if (nodes.isEmpty) throw const NodeException('此分组没有可选节点，请添加或恢复已隐藏节点');
        await (database.delete(database.preferences)
              ..where((row) => row.key.equals(selectedChainKey)))
            .go();
        final id = nodes.any((n) => n.id == group?.lastSelectedNodeId)
            ? group!.lastSelectedNodeId ?? nodes.first.id
            : nodes.first.id;
        await database.into(database.preferences).insertOnConflictUpdate(
            PreferencesCompanion.insert(key: selectedNodeKey, value: id));
        if (groupId != null) {
          await (database.update(database.nodeGroups)
                ..where((g) => g.id.equals(groupId)))
              .write(NodeGroupsCompanion(lastSelectedNodeId: Value(id)));
        }
      });

  @override
  Future<void> moveUngrouped(String nodeId, String groupId) =>
      database.transaction(() async {
        await _group(groupId);
        final changed = await (database.update(database.nodes)
              ..where((n) =>
                  n.id.equals(nodeId) &
                  n.groupId.isNull() &
                  n.sourceKey.equals('')))
            .write(NodesCompanion(groupId: Value(groupId)));
        if (changed != 1) throw const NodeException('只有未分组的手动节点可以移动');
      });

  @override
  Future<void> delete(String id) => database.transaction(() async {
        await _group(id);
        final managed = await (database.select(database.nodes)
              ..where(
                  (n) => n.groupId.equals(id) & n.sourceKey.equals('').not()))
            .get();
        final ids = managed.map((n) => n.id).toList();
        await (database.delete(database.nodes)..where((n) => n.id.isIn(ids)))
            .go();
        await (database.update(database.nodes)
              ..where((n) => n.groupId.equals(id)))
            .write(const NodesCompanion(groupId: Value(null)));
        await (database.delete(database.preferences)
              ..where((p) => p.key.equals(selectedNodeKey) & p.value.isIn(ids)))
            .go();
        await (database.delete(database.nodeGroups)
              ..where((g) => g.id.equals(id)))
            .go();
      });
}

enum _ReviewState { pending, applying, consumed }
