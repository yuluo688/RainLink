import '../../domain/chains/proxy_chain.dart';
import '../../domain/connection/connection_models.dart';
import '../../domain/core/core_gateway.dart';
import '../../domain/core/runtime_settings.dart';
import '../../domain/nodes/proxy_node.dart';
import '../../domain/routing/route_rules.dart';
import '../../domain/routing/routing_plan.dart';

/// Decodes the original, ciphertext-only request retained by a native service.
/// This is separate from persistence and never resolves today's UI selection.
abstract final class SessionRequestProtocol {
  static Never _invalid() =>
      throw const CoreGatewayException('invalid_response', '后台连接快照无效');

  static Map<String, Object?> _map(Object? value) =>
      value is Map<String, Object?> ? value : _invalid();

  static ProxyNode _node(Object? raw) {
    final value = _map(raw);
    if (value
        case {
          'id': String id,
          'name': String name,
          'protocol': String protocol,
          'server': String server,
          'port': int port,
          'tls': bool tls,
          'credential': String cipher,
          'revision': int revision,
          'options': final options,
        }
        when RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id) &&
            name.isNotEmpty &&
            name.runes.length <= 64 &&
            server.isNotEmpty &&
            server.length <= 253 &&
            port > 0 &&
            port <= 65535 &&
            revision > 0 &&
            (cipher.isEmpty ||
                cipher.startsWith('rlk1.') && cipher.length <= 98304)) {
      final kind = NodeProtocol.values
          .where((kind) => kind.wireName == protocol)
          .firstOrNull;
      if (kind == null) _invalid();
      return ProxyNode(
          id: id,
          name: name,
          protocol: kind,
          server: server,
          port: port,
          tls: tls,
          credential: cipher,
          revision: revision,
          options: NodeOptions.fromJson(_map(options)));
    }
    return _invalid();
  }

  static ChainSnapshot _chain(Object? raw) {
    final value = _map(raw);
    if (value
        case {
          'id': String id,
          'name': String name,
          'revision': int revision,
          'hops': List<Object?> hops
        }
        when revision > 0 && hops.length >= 2 && hops.length <= maxChainHops) {
      final nodes = hops.map(_node).toList();
      return ChainSnapshot(
          ProxyChain(
              id: id,
              name: name,
              revision: revision,
              hopIds: nodes.map((node) => node.id).toList()),
          nodes)
        ..validate();
    }
    return _invalid();
  }

  static ConnectRequest decode(Object? raw) {
    try {
      final value = _map(raw);
      if (value.containsKey('secrets')) _invalid();
      final node = value['node'] == null ? null : _node(value['node']);
      final chain = value['chain'] == null ? null : _chain(value['chain']);
      final mode = ProxyMode.values
          .where((mode) => mode.name == value['mode'])
          .firstOrNull;
      if ((node == null) == (chain == null) ||
          mode == null ||
          value['tun'] != true ||
          value['systemProxy'] != false) {
        _invalid();
      }
      RoutingPlan? plan;
      if (value['routing'] case final raw?) {
        final routing = _map(raw);
        final entries = routing['outbounds'];
        if (entries is! List<Object?> ||
            entries.length > RouteRuleSet.maxTargets) {
          _invalid();
        }
        final outbounds = entries.map((raw) {
          final entry = _map(raw);
          if (entry case {'key': String key, 'name': String name}) {
            final node = entry['node'] == null ? null : _node(entry['node']);
            final chain =
                entry['chain'] == null ? null : _chain(entry['chain']);
            if ((node == null) == (chain == null)) _invalid();
            return RoutingOutbound(
                key: key, name: name, node: node, chain: chain);
          }
          return _invalid();
        }).toList();
        plan = RoutingPlan(
            ruleSet: RouteRuleSet.fromJson(routing),
            outbounds: outbounds,
            primaryChain: chain);
      }
      return ConnectRequest(
          target: ProxyTarget(
              id: node?.id ?? chain!.chain.id,
              name: node?.name ?? chain!.chain.name,
              revision: node?.revision ?? chain!.chain.revision,
              kind: node == null ? 'chain' : 'node'),
          node: node,
          chain: chain,
          mode: mode,
          routing: plan,
          runtimeSettings:
              CoreRuntimeSettings.fromJson(_map(value['runtimeSettings'])),
          tun: true);
    } on Object {
      return _invalid();
    }
  }
}
