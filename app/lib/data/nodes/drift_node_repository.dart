import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/nodes/proxy_node.dart';
import '../../domain/chains/proxy_chain.dart';
import '../../domain/nodes/node_validation.dart';
import '../database/app_database.dart';
import 'node_records.dart';

class DriftNodeRepository implements NodeRepository {
  DriftNodeRepository(this.database, this.protector);
  final AppDatabase database;
  final CredentialProtector protector;

  @override
  Stream<List<ProxyNode>> watchNodes() =>
      nodeQuery(database).watch().map((rows) => rows
          .map((row) => nodeFromJoined(database, row))
          .toList(growable: false));

  @override
  Stream<String?> watchSelectedId() => (database.select(database.preferences)
        ..where((row) => row.key.equals(selectedNodeKey)))
      .watchSingleOrNull()
      .map((row) => row?.value);

  @override
  Future<ProxyNode> save(NodeDraft draft) async {
    final server = draft.server.trim();
    final id = draft.original?.id ?? newRecordId();
    final needsSecret =
        ![NodeProtocol.http, NodeProtocol.socks5].contains(draft.protocol);
    final authenticate = needsSecret || draft.authenticate;
    if (draft.protocol == NodeProtocol.shadowsocks &&
        draft.original?.protocol == draft.protocol &&
        draft.original?.options.method != draft.options.method &&
        draft.password.isEmpty) {
      throw const NodeException('更改 Shadowsocks 加密方式后，请重新填写密码');
    }
    if (draft.protocol == NodeProtocol.hysteria2 &&
        draft.options.obfs.isNotEmpty &&
        draft.original?.options.obfs != draft.options.obfs &&
        draft.obfsPassword.isEmpty) {
      throw const NodeException('启用混淆后，请填写认证密码和混淆密码');
    }
    final preserve = authenticate &&
        draft.original != null &&
        draft.original?.protocol == draft.protocol &&
        (draft.original?.credential.isNotEmpty ?? false) &&
        draft.username.isEmpty &&
        draft.password.isEmpty &&
        draft.obfsPassword.isEmpty;
    validateNode(draft, preservingSecret: preserve);
    if (draft.original?.subscriptionManaged ?? false) {
      throw const NodeException('订阅节点由订阅管理，请更新订阅');
    }
    final credential = !authenticate
        ? ''
        : preserve
            ? draft.original?.credential ?? ''
            : await protector.protect(id, draft.username, draft.password,
                obfsPassword: draft.obfsPassword);
    return database.transaction(() async {
      final existing = await (database.select(database.nodes)
            ..where((row) => row.id.equals(id)))
          .getSingleOrNull();
      if (draft.original != null &&
          existing?.revision != draft.original?.revision) {
        throw const NodeException('节点已被修改或删除，请重新打开编辑');
      }
      if (existing?.sourceKey.isNotEmpty ?? false) {
        throw const NodeException('订阅节点不可手动编辑');
      }
      final revision = (existing?.revision ?? 0) + 1;
      final node = ProxyNode(
          id: id,
          name: draft.name.trim(),
          protocol: draft.protocol,
          server: server,
          port: draft.port,
          tls: draft.tls,
          options: draft.options,
          groupId: existing?.groupId,
          credential: credential,
          revision: revision);
      await database.into(database.nodes).insertOnConflictUpdate(
          NodesCompanion.insert(
              id: id,
              name: node.name,
              protocol: node.protocol.wireName,
              server: server,
              port: node.port,
              tls: Value(node.tls),
              options: Value(jsonEncode(node.options.toJson())),
              groupId: Value(node.groupId),
              credential: Value(credential),
              revision: Value(revision)));
      return node;
    });
  }

  @override
  Future<void> select(String id) => database.transaction(() async {
        final node = await loadNode(database, id);
        if (node == null) throw const NodeException('该节点已被删除');
        if (node.hidden) throw const NodeException('请先恢复此节点的显示，再选择连接');
        await (database.delete(database.preferences)
              ..where((row) => row.key.equals(selectedChainKey)))
            .go();
        await database.into(database.preferences).insertOnConflictUpdate(
            PreferencesCompanion.insert(key: selectedNodeKey, value: id));
        if (node.groupId case final groupId?) {
          await (database.update(database.nodeGroups)
                ..where((g) => g.id.equals(groupId)))
              .write(NodeGroupsCompanion(lastSelectedNodeId: Value(id)));
        }
      });

  @override
  Future<void> delete(String id) => database.transaction(() async {
        final node = await (database.select(database.nodes)
              ..where((n) => n.id.equals(id)))
            .getSingleOrNull();
        if (node?.sourceKey.isNotEmpty ?? false) {
          throw const NodeException('订阅节点由订阅统一管理');
        }
        await (database.delete(database.nodes)
              ..where((row) => row.id.equals(id)))
            .go();
        await (database.delete(database.preferences)
              ..where((row) =>
                  row.key.equals(selectedNodeKey) & row.value.equals(id)))
            .go();
        await (database.update(database.nodeGroups)
              ..where((g) => g.lastSelectedNodeId.equals(id)))
            .write(const NodeGroupsCompanion(lastSelectedNodeId: Value(null)));
      });
}
