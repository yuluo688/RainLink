import 'dart:async';
import '../../domain/chains/proxy_chain.dart';
import '../../domain/nodes/proxy_node.dart';
import '../../domain/nodes/node_probe.dart';
import 'host_session_client.dart';

/// Separate stdio processes keep slow prefix probes away from live telemetry.
class DesktopProbeGateway implements ChainTester, NodeTester {
  DesktopProbeGateway(this.executable);
  final String executable;
  HostSessionClient? _test;
  final _clients = <HostSessionClient>{};
  final _nodeTests = <HostSessionClient>{};
  bool _disposed = false;

  HostSessionClient _open({Duration timeout = const Duration(seconds: 50)}) {
    if (_disposed) throw const NodeException('测试接口已关闭');
    final client = HostSessionClient(executable,
        arguments: const ['serve-test'], requestTimeout: timeout);
    _clients.add(client);
    return client;
  }

  @override
  Future<void> validateChain(ChainSnapshot chain) async {
    chain.validate();
    final client = _open();
    try {
      await client.request('validateChain', chain.toHost());
    } finally {
      await client.close();
      _clients.remove(client);
    }
  }

  @override
  Future<ChainTestResult> testChain(ChainSnapshot chain) async {
    chain.validate();
    if (_test != null) throw const ChainException('链路测试正在进行');
    final client = _test = _open();
    try {
      final result = ChainTestResult.fromJson(
          await client.request('testChain', chain.toHost()));
      if (result.fingerprint != chain.fingerprint ||
          result.hops.isEmpty ||
          result.passed && result.hops.length != chain.hops.length) {
        throw const ChainException('链路测试与当前路径不一致，请重试');
      }
      return result;
    } finally {
      await client.close();
      _clients.remove(client);
      if (identical(_test, client)) _test = null;
    }
  }

  @override
  Future<void> cancelChainTest() async {
    final client = _test;
    if (client != null) await client.close();
  }

  @override
  Future<NodeProbeResult> testNode(ProxyNode node) async {
    if (_nodeTests.length >= nodeProbeConcurrency) {
      throw const NodeException('测速并发已满，请稍后重试');
    }
    final client = _open(timeout: const Duration(seconds: 20));
    _nodeTests.add(client);
    try {
      final result = NodeProbeResult.fromJson(
          await client.request('testNode', node.toHost()));
      if (!result.matches(node)) throw const NodeException('节点测速响应与请求不一致');
      return result;
    } finally {
      await client.close();
      _clients.remove(client);
      _nodeTests.remove(client);
    }
  }

  @override
  Future<void> cancelNodeTests() async {
    await Future.wait(_nodeTests.toList().map((client) => client.close()));
  }

  Future<void> close() async {
    _disposed = true;
    await Future.wait(_clients.toList().map((client) => client.close()));
    _clients.clear();
  }
}
