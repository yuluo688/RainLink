import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/nodes/proxy_node.dart';
import '../../domain/nodes/node_overrides.dart';

enum NodeListFilter { all, favorites, hidden }

final nodeListFilterProvider =
    StateProvider.autoDispose<NodeListFilter>((ref) => NodeListFilter.all);
final nodeOverridesRepositoryProvider =
    Provider<NodeOverridesRepository>((ref) => const _UnavailableOverrides());

final nodeRepositoryProvider =
    Provider<NodeRepository>((ref) => const _UnavailableNodes());
final nodesProvider = StreamProvider<List<ProxyNode>>(
    (ref) => ref.watch(nodeRepositoryProvider).watchNodes());
final availableNodesProvider = Provider<AsyncValue<List<ProxyNode>>>((ref) =>
    ref.watch(nodesProvider).whenData((nodes) =>
        nodes.where((node) => !node.hidden).toList(growable: false)));
final selectedNodeIdProvider = StreamProvider<String?>(
    (ref) => ref.watch(nodeRepositoryProvider).watchSelectedId());
final selectedNodeProvider = Provider<ProxyNode?>((ref) {
  final id = ref.watch(selectedNodeIdProvider).valueOrNull;
  for (final node in ref.watch(nodesProvider).valueOrNull ?? <ProxyNode>[]) {
    if (node.id == id && !node.hidden) return node;
  }
  return null;
});

class _UnavailableNodes implements NodeRepository {
  const _UnavailableNodes();
  @override
  Stream<List<ProxyNode>> watchNodes() => Stream.value(const []);
  @override
  Stream<String?> watchSelectedId() => Stream.value(null);
  @override
  Future<ProxyNode> save(NodeDraft draft) async =>
      throw const NodeException('节点存储尚未初始化');
  @override
  Future<void> select(String id) async =>
      throw const NodeException('节点存储尚未初始化');
  @override
  Future<void> delete(String id) async =>
      throw const NodeException('节点存储尚未初始化');
}

class _UnavailableOverrides implements NodeOverridesRepository {
  const _UnavailableOverrides();
  @override
  Future<void> setFavorite(String nodeId, bool favorite) async =>
      throw const NodeException('节点存储尚未初始化');
  @override
  Future<void> setAlias(String nodeId, String alias) async =>
      throw const NodeException('节点存储尚未初始化');
  @override
  Future<void> setHidden(String nodeId, bool hidden) async =>
      throw const NodeException('节点存储尚未初始化');
}
