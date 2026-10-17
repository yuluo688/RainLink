import 'package:drift/drift.dart';
import '../../domain/nodes/node_overrides.dart';
import '../../domain/nodes/proxy_node.dart';
import '../database/app_database.dart';
import 'node_records.dart';

class DriftNodeOverridesRepository implements NodeOverridesRepository {
  DriftNodeOverridesRepository(this.database);
  final AppDatabase database;

  Future<void> _write(String id, NodeOverridesCompanion values,
          {bool hidden = false}) =>
      database.transaction(() async {
        final node = await loadNode(database, id);
        if (node == null) throw const NodeException('该节点已被删除，请刷新列表');
        await database.into(database.nodeOverrides).insert(
            NodeOverridesCompanion.insert(nodeId: id),
            mode: InsertMode.insertOrIgnore);
        await (database.update(database.nodeOverrides)
              ..where((row) => row.nodeId.equals(id)))
            .write(values);
        // Keep the live snapshot, but prevent a hidden node being selected again.
        if (hidden) {
          await (database.delete(database.preferences)
                ..where((row) =>
                    row.key.equals(selectedNodeKey) & row.value.equals(id)))
              .go();
          await (database.update(database.nodeGroups)
                ..where((row) => row.lastSelectedNodeId.equals(id)))
              .write(
                  const NodeGroupsCompanion(lastSelectedNodeId: Value(null)));
        }
      });

  @override
  Future<void> setFavorite(String nodeId, bool favorite) =>
      _write(nodeId, NodeOverridesCompanion(favorite: Value(favorite)));

  @override
  Future<void> setAlias(String nodeId, String alias) async {
    final normalized = alias.trim();
    if (normalized.runes.length > 128 ||
        normalized.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const NodeException('别名最多 128 个字符，不能包含控制字符');
    }
    await _write(nodeId, NodeOverridesCompanion(alias: Value(normalized)));
  }

  @override
  Future<void> setHidden(String nodeId, bool hidden) =>
      _write(nodeId, NodeOverridesCompanion(hidden: Value(hidden)),
          hidden: hidden);
}
