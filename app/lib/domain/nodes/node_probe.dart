import 'proxy_node.dart';

const nodeProbeConcurrency = 3;
const maxNodeProbeBatch = 2000;

class NodeProbeResult {
  const NodeProbeResult(
      {required this.nodeId,
      required this.revision,
      required this.checkedAt,
      required this.passed,
      this.latency = 0,
      this.error = ''});
  final String nodeId;
  final int revision;
  final DateTime checkedAt;
  final bool passed;
  final int latency;
  final String error;
  bool matches(ProxyNode node) =>
      node.id == nodeId && node.revision == revision;

  factory NodeProbeResult.fromJson(Map<String, Object?> json) {
    if (json
        case {
          'nodeId': String id,
          'revision': int revision,
          'checkedAt': int at,
          'passed': bool passed,
          'latency': int latency,
          'error': String error
        }
        when RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id) &&
            revision > 0 &&
            at > 0 &&
            at <= 8640000000000000 &&
            latency >= 0 &&
            latency <= 60000 &&
            error.length <= 256 &&
            (passed ? error.isEmpty : error.isNotEmpty)) {
      return NodeProbeResult(
          nodeId: id,
          revision: revision,
          checkedAt: DateTime.fromMillisecondsSinceEpoch(at),
          passed: passed,
          latency: latency,
          error: error);
    }
    throw const NodeException('节点测速响应无效');
  }
}

abstract interface class NodeTester {
  Future<NodeProbeResult> testNode(ProxyNode node);
  Future<void> cancelNodeTests();
}
