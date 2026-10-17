import '../../domain/groups/node_group.dart';
import '../../domain/nodes/proxy_node.dart';
import '../../domain/routing/route_rules.dart';
import '../../domain/chains/proxy_chain.dart';

String routeTargetLabel(
        RouteTarget target, List<NodeGroup> groups, List<ProxyNode> nodes,
        [List<ProxyChain> chains = const []]) =>
    switch (target.kind) {
      RouteTargetKind.proxy => '当前所选目标',
      RouteTargetKind.direct => '直连',
      RouteTargetKind.reject => '拦截',
      RouteTargetKind.group =>
        groups.where((group) => group.id == target.id).firstOrNull?.name ??
            '分组已删除',
      RouteTargetKind.node =>
        nodes.where((node) => node.id == target.id).firstOrNull?.name ??
            '节点已删除',
      RouteTargetKind.chain =>
        chains.where((chain) => chain.id == target.id).firstOrNull?.name ??
            '代理链已删除',
    };

bool routeTargetMissing(
        RouteTarget target, List<NodeGroup> groups, List<ProxyNode> nodes,
        [List<ProxyChain> chains = const []]) =>
    switch (target.kind) {
      RouteTargetKind.group => !groups.any((group) => group.id == target.id),
      RouteTargetKind.node => !nodes.any((node) => node.id == target.id),
      RouteTargetKind.chain => !chains.any((chain) => chain.id == target.id),
      _ => false,
    };
