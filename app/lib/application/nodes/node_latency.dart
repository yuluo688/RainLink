import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/nodes/proxy_node.dart';
import '../connection/session_controller.dart';
import 'node_probe_controller.dart';

class NodeLatency {
  const NodeLatency(
      {this.pending = false,
      this.failed = false,
      this.latency,
      this.checkedAt,
      this.error = ''});
  final bool pending;
  final bool failed;
  final int? latency;
  final DateTime? checkedAt;
  final String error;
}

/// Ignore old node revisions; a currently running snapshot may have older options.
final nodeLatencyProvider =
    Provider.autoDispose.family<NodeLatency, ProxyNode>((ref, node) {
  final live = ref.watch(sessionControllerProvider.select((state) =>
      state.active?.target.id == node.id &&
              state.active?.target.revision == node.revision
          ? state.telemetry?.latency
          : null));
  final (pending, previous) = ref.watch(nodeProbeProvider.select(
      (state) => (state.pending.contains(node.id), state.results[node.id])));
  final probe = previous != null && previous.matches(node) ? previous : null;
  return NodeLatency(
      pending: pending,
      failed: probe != null && !probe.passed,
      latency: probe == null
          ? live
          : probe.passed
              ? probe.latency
              : null,
      checkedAt: probe?.checkedAt,
      error: probe?.error ?? '');
});
