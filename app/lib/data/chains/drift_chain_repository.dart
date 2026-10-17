import 'dart:convert';
import 'package:drift/drift.dart';
import '../../domain/chains/proxy_chain.dart';
import '../database/app_database.dart';
import '../nodes/node_records.dart';
import 'chain_records.dart';

class DriftChainRepository implements ChainRepository {
  DriftChainRepository(this.database, this.tester);
  final AppDatabase database;
  final ChainTester tester;

  @override
  Stream<List<ProxyChain>> watch() => (database.select(database.preferences)
        ..where((row) => row.key.equals(chainsKey)))
      .watchSingleOrNull()
      .map((row) => decodeChains(row?.value));
  @override
  Stream<String?> watchSelectedId() => (database.select(database.preferences)
        ..where((row) => row.key.equals(selectedChainKey)))
      .watchSingleOrNull()
      .map((row) => row?.value);

  @override
  Future<ProxyChain> save(ChainSnapshot draft, {ChainTestResult? test}) async {
    draft.validate();
    await tester.validateChain(draft);
    return database.transaction(() async {
      final chains = await loadChains(database);
      final index = chains.indexWhere((chain) => chain.id == draft.chain.id);
      final revision = index < 0 ? 0 : chains[index].revision;
      if (revision != draft.chain.revision) {
        throw const ChainException('代理链已被修改或删除，请重新打开');
      }
      if (index < 0 && chains.length >= maxSavedChains) {
        throw const ChainException('最多保存 32 条代理链');
      }
      final current = await resolveChain(database, draft.chain);
      if (current.fingerprint != draft.fingerprint) {
        throw const ChainException('节点在保存期间已更新，请重新检查链路');
      }
      final saved = ProxyChain(
          id: draft.chain.id,
          name: draft.chain.name.trim(),
          hopIds: draft.chain.hopIds,
          revision: revision + 1,
          lastTest: test?.fingerprint == current.fingerprint ? test : null);
      if (index < 0) {
        chains.add(saved);
      } else {
        chains[index] = saved;
      }
      await _write(chains);
      await _select(saved.id);
      return saved;
    });
  }

  Future<void> _write(List<ProxyChain> chains) => database
      .into(database.preferences)
      .insertOnConflictUpdate(PreferencesCompanion.insert(
          key: chainsKey,
          value: jsonEncode(chains.map((chain) => chain.toJson()).toList())));

  Future<void> _select(String id) async {
    await (database.delete(database.preferences)
          ..where((row) => row.key.equals(selectedNodeKey)))
        .go();
    await database.into(database.preferences).insertOnConflictUpdate(
        PreferencesCompanion.insert(key: selectedChainKey, value: id));
  }

  @override
  Future<void> select(ProxyChain chain) => database.transaction(() async {
        final current = (await loadChains(database))
            .where((item) => item.id == chain.id)
            .firstOrNull;
        if (current == null || current.revision != chain.revision) {
          throw const ChainException('代理链已更新或删除，请重新选择');
        }
        await resolveChain(database, current);
        await _select(current.id);
      });

  @override
  Future<void> delete(ProxyChain chain) => database.transaction(() async {
        final chains = await loadChains(database);
        final index = chains.indexWhere((item) => item.id == chain.id);
        if (index < 0 || chains[index].revision != chain.revision) {
          throw const ChainException('代理链已更新或删除，请刷新后重试');
        }
        chains.removeAt(index);
        await _write(chains);
        await (database.delete(database.preferences)
              ..where((row) =>
                  row.key.equals(selectedChainKey) &
                  row.value.equals(chain.id)))
            .go();
      });
}
