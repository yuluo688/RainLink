import '../../domain/nodes/proxy_node.dart';
import '../../domain/chains/proxy_chain.dart';
import '../chains/chain_records.dart';
import '../../domain/routing/route_rules.dart';
import '../../domain/routing/routing_plan.dart';
import '../database/app_database.dart';
import '../nodes/node_records.dart';

class DriftRoutingResolver implements RoutingResolver {
  DriftRoutingResolver(this.database, this.rules);
  final AppDatabase database;
  final RouteRuleRepository rules;

  @override
  Future<RoutingPlan> resolve(ProxyNode? selected, {ProxyChain? chain}) =>
      database.transaction(() async {
        final chains = await loadChains(database);
        ChainSnapshot? primaryChain;
        if (chain != null) {
          if (selected != null) throw const RoutingException('只能选择一个连接目标');
          final current =
              chains.where((item) => item.id == chain.id).firstOrNull;
          if (current == null || current.revision != chain.revision) {
            throw const ChainException('代理链已更新或删除，请重新选择');
          }
          primaryChain = await resolveChain(database, current);
        } else if (selected != null) {
          final current = await loadNode(database, selected.id);
          if (current == null || current.revision != selected.revision) {
            throw const RoutingException('所选节点已更新或删除，请重新选择');
          }
          if (current.hidden) throw const RoutingException('所选节点已隐藏，请重新选择');
        } else {
          throw const RoutingException('请先选择节点或代理链');
        }
        final ruleSet = (await rules.load()).validated();
        final outbounds = <RoutingOutbound>[];
        final seen = <String>{};
        for (final rule in ruleSet.rules.where((rule) => rule.enabled)) {
          final target = rule.target;
          if (!seen.add(target.key)) continue;
          if (target.kind == RouteTargetKind.node) {
            final node = await loadNode(database, target.id);
            if (node == null) throw const RoutingException('规则引用的节点已被删除，请修改规则');
            outbounds.add(
                RoutingOutbound(key: target.key, name: node.name, node: node));
          } else if (target.kind == RouteTargetKind.chain) {
            final chain =
                chains.where((chain) => chain.id == target.id).firstOrNull;
            if (chain == null) throw const ChainException('规则引用的代理链已删除，请修改规则');
            outbounds.add(RoutingOutbound(
                key: target.key,
                name: chain.name,
                chain: await resolveChain(database, chain)));
          } else if (target.kind == RouteTargetKind.group) {
            final group = await (database.select(database.nodeGroups)
                  ..where((row) => row.id.equals(target.id)))
                .getSingleOrNull();
            if (group == null) {
              throw const RoutingException('规则引用的分组已被删除，请修改规则');
            }
            final candidates = (await (nodeQuery(database, includeHidden: false)
                      ..where(database.nodes.groupId.equals(target.id)))
                    .get())
                .map((row) => nodeFromJoined(database, row))
                .toList();
            if (candidates.isEmpty) {
              throw RoutingException('分组「${group.name}」没有节点，请先添加节点或修改规则');
            }
            final node = candidates
                    .where((node) => node.id == group.lastSelectedNodeId)
                    .firstOrNull ??
                candidates.first;
            outbounds.add(
                RoutingOutbound(key: target.key, name: group.name, node: node));
          }
        }
        return RoutingPlan(
            ruleSet: ruleSet, outbounds: outbounds, primaryChain: primaryChain);
      });
}
