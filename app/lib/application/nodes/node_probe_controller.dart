import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/nodes/proxy_node.dart';
import '../../domain/nodes/node_probe.dart';

final nodeTesterProvider =
    Provider<NodeTester>((ref) => const UnavailableNodeTester());
final nodeProbeProvider =
    StateNotifierProvider<NodeProbeController, NodeProbeState>(
        (ref) => NodeProbeController(ref.watch(nodeTesterProvider)));

class NodeProbeState {
  NodeProbeState(
      {this.running = false,
      this.cancelling = false,
      this.total = 0,
      this.completed = 0,
      this.error = '',
      Map<String, NodeProbeResult> results = const {},
      Set<String> pending = const {}})
      : results = Map.unmodifiable(results),
        pending = Set.unmodifiable(pending);
  final bool running;
  final bool cancelling;
  final int total;
  final int completed;
  final String error;
  final Map<String, NodeProbeResult> results;
  final Set<String> pending;
}

/// A batch owns only temporary probes; it never selects nodes or changes capture.
class NodeProbeController extends StateNotifier<NodeProbeState> {
  NodeProbeController(this.tester) : super(NodeProbeState());
  final NodeTester tester;
  int _generation = 0;

  Future<void> run(List<ProxyNode> input) async {
    if (state.running) return;
    final nodes = {
      for (final node in input)
        if (!node.hidden) node.id: node
    }.values.toList();
    if (nodes.isEmpty || nodes.length > maxNodeProbeBatch) {
      state = NodeProbeState(
          results: state.results,
          error: nodes.isEmpty
              ? '没有可测试的节点'
              : '每次最多测试 $maxNodeProbeBatch 个节点，请缩小筛选范围');
      return;
    }
    final generation = ++_generation;
    state = NodeProbeState(
        running: true, total: nodes.length, results: state.results);
    var next = 0;
    Future<void> worker() async {
      while (mounted && generation == _generation && next < nodes.length) {
        final node = nodes[next++];
        state = NodeProbeState(
            running: true,
            total: state.total,
            completed: state.completed,
            results: state.results,
            pending: {...state.pending, node.id});
        NodeProbeResult result;
        try {
          result = await tester.testNode(node);
          if (!result.matches(node)) throw const NodeException('节点测速结果已过期，请重试');
        } on Exception catch (error) {
          result = NodeProbeResult(
              nodeId: node.id,
              revision: node.revision,
              checkedAt: DateTime.now(),
              passed: false,
              error: error is NodeException ? error.message : '测速未通过，请检查节点与网络');
        }
        if (!mounted || generation != _generation) return;
        state = NodeProbeState(
            running: true,
            total: state.total,
            completed: state.completed + 1,
            results: {...state.results, node.id: result},
            pending: {...state.pending}..remove(node.id));
      }
    }

    await Future.wait([
      for (var i = 0; i < nodeProbeConcurrency && i < nodes.length; i++)
        worker()
    ]);
    if (!mounted || generation != _generation) return;
    state = NodeProbeState(
        total: state.total, completed: state.completed, results: state.results);
  }

  Future<void> cancel() async {
    if (!state.running || state.cancelling) return;
    ++_generation;
    state = NodeProbeState(
        running: true,
        cancelling: true,
        total: state.total,
        completed: state.completed,
        results: state.results,
        pending: state.pending);
    try {
      await tester.cancelNodeTests();
      if (mounted) {
        state = NodeProbeState(
            total: state.total,
            completed: state.completed,
            results: state.results);
      }
    } on Exception {
      if (mounted) {
        state = NodeProbeState(
            running: true,
            total: state.total,
            completed: state.completed,
            results: state.results,
            error: '取消未完成，请重试取消');
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    unawaited(tester.cancelNodeTests());
    super.dispose();
  }
}

class UnavailableNodeTester implements NodeTester {
  const UnavailableNodeTester();
  @override
  Future<NodeProbeResult> testNode(ProxyNode node) async =>
      throw const NodeException('当前平台的节点测速尚未接入');
  @override
  Future<void> cancelNodeTests() async {}
}
