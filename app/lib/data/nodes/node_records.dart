import 'dart:convert';
import 'package:drift/drift.dart';
export '../../domain/identity/record_id.dart';
import '../../domain/nodes/proxy_node.dart';
import '../database/app_database.dart';

const selectedNodeKey = 'connection.selected_node';

ProxyNode nodeFromRecord(Node row, {NodeOverrideRecord? local}) => ProxyNode(
    id: row.id,
    name: local == null || local.alias.isEmpty ? row.name : local.alias,
    originalName: row.name,
    favorite: local?.favorite ?? false,
    hidden: local?.hidden ?? false,
    protocol: NodeProtocol.values
        .firstWhere((value) => value.wireName == row.protocol),
    server: row.server,
    port: row.port,
    tls: row.tls,
    options:
        NodeOptions.fromJson((jsonDecode(row.options) as Map<String, Object?>)),
    groupId: row.groupId,
    sourceKey: row.sourceKey,
    credential: row.credential,
    revision: row.revision);

JoinedSelectStatement<HasResultSet, Object?> nodeQuery(AppDatabase database,
    {bool includeHidden = true}) {
  final query = database.select(database.nodes).join([
    leftOuterJoin(database.nodeOverrides,
        database.nodeOverrides.nodeId.equalsExp(database.nodes.id))
  ])
    ..orderBy([
      OrderingTerm.asc(database.nodes.name),
      OrderingTerm.asc(database.nodes.id)
    ]);
  if (!includeHidden) {
    query.where(database.nodeOverrides.hidden.isNull() |
        database.nodeOverrides.hidden.equals(false));
  }
  return query;
}

ProxyNode nodeFromJoined(AppDatabase database, TypedResult result) =>
    nodeFromRecord(result.readTable(database.nodes),
        local: result.readTableOrNull(database.nodeOverrides));

Future<ProxyNode?> loadNode(AppDatabase database, String id) async {
  final result = await (nodeQuery(database)
        ..where(database.nodes.id.equals(id)))
      .getSingleOrNull();
  return result == null ? null : nodeFromJoined(database, result);
}
