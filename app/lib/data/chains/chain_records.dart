import 'dart:convert';
import '../../domain/chains/proxy_chain.dart';
import '../database/app_database.dart';
import '../nodes/node_records.dart';

const chainsKey = 'routing.chains';
const maxSavedChains = 32;

List<ProxyChain> decodeChains(String? value) {
  if (value == null) return [];
  try {
    final Object? json = jsonDecode(value);
    if (json is List<Object?> && json.length <= maxSavedChains) {
      final result = json.map((row) {
        if (row is Map<String, Object?>) return ProxyChain.fromJson(row);
        throw const ChainException('已保存的代理链格式无效');
      }).toList();
      if (result.map((chain) => chain.id).toSet().length == result.length) {
        return result;
      }
    }
  } on FormatException {
    throw const ChainException('已保存的代理链损坏，请检查本地数据');
  }
  throw const ChainException('已保存的代理链格式无效');
}

Future<List<ProxyChain>> loadChains(AppDatabase database) async =>
    decodeChains((await (database.select(database.preferences)
              ..where((row) => row.key.equals(chainsKey)))
            .getSingleOrNull())
        ?.value);

Future<ChainSnapshot> resolveChain(
    AppDatabase database, ProxyChain chain) async {
  final rows = await (nodeQuery(database)
        ..where(database.nodes.id.isIn(chain.hopIds)))
      .get();
  final byId = {
    for (final row in rows)
      row.readTable(database.nodes).id: nodeFromJoined(database, row)
  };
  if (chain.hopIds.any((id) => !byId.containsKey(id))) {
    throw ChainException('代理链「${chain.name}」的部分节点已删除，请更换跳点');
  }
  final snapshot = ChainSnapshot(chain, [
    for (final id in chain.hopIds)
      if (byId[id] case final node?) node
  ]);
  snapshot.validate();
  return snapshot;
}
