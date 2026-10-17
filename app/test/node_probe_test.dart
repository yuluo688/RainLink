import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/nodes/node_probe_controller.dart';
import 'package:rainlink/domain/nodes/node_probe.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';

ProxyNode node(String id, {int revision = 1, bool hidden = false}) => ProxyNode(
    id: id,
    name: id,
    protocol: NodeProtocol.http,
    server: 'example.test',
    port: 80,
    revision: revision,
    hidden: hidden);
NodeProbeResult result(ProxyNode node, {int latency = 24}) => NodeProbeResult(
    nodeId: node.id,
    revision: node.revision,
    checkedAt: DateTime.now(),
    passed: true,
    latency: latency);

class _Tester implements NodeTester {
  final calls = <(ProxyNode, Completer<NodeProbeResult>)>[];
  int active = 0;
  int maxActive = 0;
  int cancellations = 0;
  bool failCancel = false;
  @override
  Future<NodeProbeResult> testNode(ProxyNode node) {
    active++;
    if (active > maxActive) maxActive = active;
    final completion = Completer<NodeProbeResult>();
    calls.add((node, completion));
    return completion.future.whenComplete(() => active--);
  }

  @override
  Future<void> cancelNodeTests() async {
    cancellations++;
    if (failCancel) throw const NodeException('fixture cleanup failure');
  }
}

void main() {
  test('batch limits concurrency, deduplicates and omits hidden nodes',
      () async {
    final tester = _Tester();
    final controller = NodeProbeController(tester);
    addTearDown(controller.dispose);
    final nodes = [for (var i = 0; i < 6; i++) node('node-$i')];
    final running =
        controller.run([...nodes, nodes.first, node('hidden', hidden: true)]);
    expect(tester.calls, hasLength(3));
    expect(controller.state.total, 6);
    expect(controller.state.pending, hasLength(3));
    for (var index = 0; index < 6; index++) {
      final call = tester.calls[index];
      call.$2.complete(result(call.$1));
      await Future<void>.delayed(Duration.zero);
    }
    await running;
    expect(tester.maxActive, nodeProbeConcurrency);
    expect(controller.state.completed, 6);
    expect(controller.state.running, isFalse);
    expect(controller.state.results.values.every((result) => result.passed),
        isTrue);
    expect(controller.state.results, hasLength(6));
  });

  test(
      'cancel keeps completed results and ignores late success before the next batch',
      () async {
    final tester = _Tester();
    final controller = NodeProbeController(tester);
    addTearDown(controller.dispose);
    final a = node('a'), b = node('b');
    final running = controller.run([a, b, node('c'), node('queued')]);
    tester.calls.first.$2.complete(result(a));
    await Future<void>.delayed(Duration.zero);
    await controller.cancel();
    for (final call in tester.calls.skip(1)) {
      call.$2.complete(result(call.$1));
    }
    await running;
    expect(controller.state.results.keys, ['a']);
    expect(controller.state.pending, isEmpty);
    expect(tester.cancellations, 1);
    final fresh = node('b', revision: 2);
    final next = controller.run([fresh]);
    tester.calls.last.$2.complete(result(fresh, latency: 31));
    await next;
    expect(controller.state.results['b']?.latency, 31);
    expect(controller.state.results['b']?.matches(b), isFalse);
    expect(controller.state.results['b']?.matches(fresh), isTrue);
  });

  test('cleanup failure keeps cancellation available and prevents a new batch',
      () async {
    final tester = _Tester();
    final controller = NodeProbeController(tester);
    addTearDown(controller.dispose);
    final running = controller.run([node('a')]);
    tester.failCancel = true;
    await controller.cancel();
    expect(controller.state.running, isTrue);
    expect(controller.state.cancelling, isFalse);
    expect(controller.state.error, contains('取消未完成'));
    await controller.run([node('other')]);
    expect(tester.calls, hasLength(1));
    tester.failCancel = false;
    await controller.cancel();
    tester.calls.single.$2.complete(result(node('a')));
    await running;
    expect(controller.state.running, isFalse);
    expect(controller.state.results, isEmpty);
  });

  test(
      'wrong revision and exceptions become failures rather than stale latency',
      () async {
    final tester = _Tester();
    final controller = NodeProbeController(tester);
    addTearDown(controller.dispose);
    final a = node('a', revision: 2), b = node('b');
    final running = controller.run([a, b]);
    tester.calls.first.$2.complete(result(node('a')));
    tester.calls.last.$2
        .completeError(const FormatException('untrusted upstream detail'));
    await running;
    expect(controller.state.results['a']?.passed, isFalse);
    expect(controller.state.results['a']?.error, contains('过期'));
    expect(controller.state.results['b']?.error, isNot(contains('untrusted')));
    expect(controller.state.results['b']?.passed, isFalse);
  });

  test('malformed results and invalid batches are rejected', () async {
    final json = <String, Object?>{
      'nodeId': 'a',
      'revision': 1,
      'checkedAt': DateTime.now().millisecondsSinceEpoch,
      'latency': 24,
      'passed': true,
      'error': ''
    };
    expect(NodeProbeResult.fromJson(json).latency, 24);
    for (final mutation in [
      {'nodeId': '../a'},
      {'revision': 0},
      {'checkedAt': 8640000000000001},
      {'latency': -1},
      {'passed': false},
      {'error': 'unexpected'},
    ]) {
      expect(() => NodeProbeResult.fromJson({...json, ...mutation}),
          throwsA(isA<NodeException>()));
    }
    final tester = _Tester();
    final controller = NodeProbeController(tester);
    addTearDown(controller.dispose);
    await controller.run([]);
    expect(controller.state.error, isNotEmpty);
    await controller
        .run([for (var i = 0; i <= maxNodeProbeBatch; i++) node('node-$i')]);
    expect(tester.calls, isEmpty);
    expect(controller.state.error, contains('$maxNodeProbeBatch'));
  });
}
