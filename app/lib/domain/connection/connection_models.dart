import '../nodes/proxy_node.dart';
import '../routing/routing_plan.dart';
import '../chains/proxy_chain.dart';
import '../routing/route_binding.dart';
import '../core/runtime_settings.dart';
export '../routing/route_binding.dart';

enum ProxyMode { rule, global, direct }

enum ConnectionPhase { idle, starting, connected, stopping, failed }

/// A reference to a target revision, separate from the active connection.
class ProxyTarget {
  const ProxyTarget({
    required this.id,
    required this.name,
    required this.revision,
    this.kind = 'node',
  });

  final String id;
  final String name;
  final int revision;
  final String kind;
}

class ConnectRequest {
  const ConnectRequest(
      {required this.target,
      required this.mode,
      this.node,
      this.chain,
      this.routing,
      this.runtimeSettings = const CoreRuntimeSettings(),
      this.tun = false,
      this.systemProxy = false});

  final ProxyTarget target;
  final ProxyMode mode;
  final ProxyNode? node;
  final ChainSnapshot? chain;
  final RoutingPlan? routing;
  final CoreRuntimeSettings runtimeSettings;
  final bool systemProxy;
  final bool tun;
}

/// The host must return the exact target/configuration applied to this session.
class ActiveConnectionSnapshot {
  const ActiveConnectionSnapshot({
    required this.sessionId,
    required this.target,
    required this.mode,
    required this.configRevision,
    this.proxyPort = 0,
    this.ruleRevision = 0,
    this.routeBindings = const {},
  });

  final String sessionId;
  final ProxyTarget target;
  final ProxyMode mode;
  final String configRevision;
  final int proxyPort;
  final int ruleRevision;
  final Map<String, RouteBinding> routeBindings;
}

class ConnectionSessionState {
  const ConnectionSessionState({
    this.phase = ConnectionPhase.idle,
    this.selectedTarget,
    this.activeSnapshot,
    this.mode = ProxyMode.rule,
  });

  final ConnectionPhase phase;
  final ProxyTarget? selectedTarget;
  final ActiveConnectionSnapshot? activeSnapshot;
  final ProxyMode mode;

  bool get pendingApply {
    final active = activeSnapshot;
    if (active == null) return false;
    return selectedTarget?.id != active.target.id ||
        selectedTarget?.kind != active.target.kind ||
        selectedTarget?.revision != active.target.revision;
  }

  ConnectionSessionState select(ProxyTarget? target) => ConnectionSessionState(
        phase: phase,
        selectedTarget: target,
        activeSnapshot: activeSnapshot,
        mode: mode,
      );
}
