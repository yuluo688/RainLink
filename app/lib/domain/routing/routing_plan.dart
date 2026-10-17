import '../nodes/proxy_node.dart';
import '../chains/proxy_chain.dart';
import 'route_binding.dart';
import 'route_rules.dart';

class RoutingOutbound {
  const RoutingOutbound(
      {required this.key, required this.name, this.node, this.chain});
  final String key;
  final String name;
  final ProxyNode? node;
  final ChainSnapshot? chain;
  Map<String, Object> toHost() => {
        'key': key,
        'name': name,
        if (node case final node?) 'node': node.toHost(),
        if (chain case final chain?) 'chain': chain.toHost()
      };

  void addBindings(Map<String, RouteBinding> result) {
    if (chain case final chain?) {
      if (key != 'proxy') {
        result[key] = RouteBinding(chain.chain.id, chain.chain.revision);
      }
      for (var i = 0; i < chain.hops.length; i++) {
        final node = chain.hops[i];
        result['$key/hop/$i'] = RouteBinding(node.id, node.revision);
      }
    } else if (node case final node?) {
      result[key] = RouteBinding(node.id, node.revision);
    }
  }
}

/// Rules and referenced group selections are frozen in the same DB transaction.
class RoutingPlan {
  RoutingPlan(
      {required this.ruleSet,
      required List<RoutingOutbound> outbounds,
      this.primaryChain})
      : outbounds = List.unmodifiable(outbounds);
  final RouteRuleSet ruleSet;
  final List<RoutingOutbound> outbounds;
  final ChainSnapshot? primaryChain;
  Map<String, RouteBinding> get expectedBindings {
    final result = <String, RouteBinding>{};
    if (primaryChain != null) {
      RoutingOutbound(key: 'proxy', name: '', chain: primaryChain)
          .addBindings(result);
    }
    for (final outbound in outbounds) {
      outbound.addBindings(result);
    }
    return result;
  }

  bool matchesBindings(Map<String, RouteBinding> applied) {
    final expected = expectedBindings;
    return applied.length == expected.length &&
        expected.entries.every((entry) =>
            applied[entry.key]?.id == entry.value.id &&
            applied[entry.key]?.revision == entry.value.revision);
  }

  Map<String, Object> toHost() => {
        ...ruleSet.toJson(),
        'outbounds': outbounds.map((outbound) => outbound.toHost()).toList(),
      };
}

abstract interface class RoutingResolver {
  Future<RoutingPlan> resolve(ProxyNode? selected, {ProxyChain? chain});
}
