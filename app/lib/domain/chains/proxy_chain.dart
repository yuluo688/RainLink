import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../nodes/proxy_node.dart';

const maxChainHops = 5;
const selectedChainKey = 'connection.selected_chain';

class ChainException implements Exception {
  const ChainException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ProxyChain {
  ProxyChain(
      {required this.id,
      required this.name,
      required List<String> hopIds,
      this.revision = 0,
      this.lastTest})
      : hopIds = List.unmodifiable(hopIds);
  final String id;
  final String name;
  final List<String> hopIds;
  final int revision;
  final ChainTestResult? lastTest;

  ProxyChain copyWith(
          {String? name,
          List<String>? hopIds,
          int? revision,
          ChainTestResult? lastTest}) =>
      ProxyChain(
          id: id,
          name: name ?? this.name,
          hopIds: hopIds ?? this.hopIds,
          revision: revision ?? this.revision,
          lastTest: lastTest ?? this.lastTest);

  void validate() {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id) ||
        revision < 0 ||
        name.trim().isEmpty ||
        name.trim().runes.length > 64) {
      throw const ChainException('链名称须为 1–64 个字符');
    }
    if (hopIds.length < 2 || hopIds.length > maxChainHops) {
      throw const ChainException('代理链须包含 2–5 个节点');
    }
    if (hopIds.toSet().length != hopIds.length ||
        hopIds.any((id) => !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id))) {
      throw const ChainException('同一节点不能在链中重复使用');
    }
  }

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'revision': revision,
        'hopIds': hopIds,
        if (lastTest != null) 'lastTest': lastTest!.toJson()
      };

  factory ProxyChain.fromJson(Map<String, Object?> json) {
    if (json
        case {
          'id': String id,
          'name': String name,
          'revision': int revision,
          'hopIds': List<Object?> ids
        } when revision > 0 && ids.every((id) => id is String)) {
      final test = json['lastTest'];
      final result = ProxyChain(
          id: id,
          name: name,
          revision: revision,
          hopIds: ids.cast<String>(),
          lastTest: test is Map<String, Object?>
              ? ChainTestResult.fromJson(test)
              : null);
      result.validate();
      return result;
    }
    throw const ChainException('已保存的代理链格式无效');
  }
}

/// Credentials remain encrypted in these node snapshots and never enter chain storage.
class ChainSnapshot {
  ChainSnapshot(this.chain, List<ProxyNode> hops)
      : hops = List.unmodifiable(hops);
  final ProxyChain chain;
  final List<ProxyNode> hops;
  String get fingerprint => sha256
      .convert(utf8
          .encode(hops.map((node) => '${node.id}:${node.revision}').join('|')))
      .toString();
  String get path => '本机 → ${hops.map((node) => node.name).join(' → ')} → 目标';
  void validate() {
    chain.validate();
    if (hops.length != chain.hopIds.length ||
        List.generate(hops.length, (i) => hops[i].id != chain.hopIds[i])
            .contains(true)) {
      throw const ChainException('部分节点已删除，请更换跳点');
    }
    final issue = chainCompatibilityIssue(hops.map((hop) => hop.protocol));
    if (issue != null) throw ChainException(issue);
  }

  Map<String, Object> toHost() => {
        'id': chain.id,
        'name': chain.name.trim(),
        'revision': chain.revision < 1 ? 1 : chain.revision,
        'hops': hops.map((node) => node.toHost()).toList()
      };
}

/// Missing hops are allowed here so an editor can repair several deleted nodes.
String? chainCompatibilityIssue(Iterable<NodeProtocol?> protocols) {
  var tcpOnly = false;
  var index = 0;
  for (final protocol in protocols) {
    index++;
    if (tcpOnly && (protocol?.usesQuic ?? false)) {
      return '第 $index 跳需要 UDP，前面的 HTTP 节点仅支持 TCP';
    }
    tcpOnly = tcpOnly || protocol == NodeProtocol.http;
  }
  return null;
}

class ChainHopTest {
  const ChainHopTest(
      {required this.hop,
      required this.latency,
      required this.passed,
      this.error = ''});
  final int hop;
  final int latency;
  final bool passed;
  final String error;
  Map<String, Object> toJson() =>
      {'hop': hop, 'latency': latency, 'passed': passed, 'error': error};
}

class ChainTestResult {
  ChainTestResult(
      {required this.fingerprint,
      required this.checkedAt,
      required this.passed,
      required List<ChainHopTest> hops})
      : hops = List.unmodifiable(hops);
  final String fingerprint;
  final DateTime checkedAt;
  final bool passed;
  final List<ChainHopTest> hops;
  Map<String, Object> toJson() => {
        'fingerprint': fingerprint,
        'checkedAt': checkedAt.millisecondsSinceEpoch,
        'passed': passed,
        'hops': hops.map((hop) => hop.toJson()).toList()
      };

  factory ChainTestResult.fromJson(Map<String, Object?> json) {
    if (json
        case {
          'fingerprint': String fingerprint,
          'checkedAt': int at,
          'passed': bool passed,
          'hops': List<Object?> rows
        }
        when RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint) &&
            at > 0 &&
            at <= 8640000000000000 &&
            rows.length <= maxChainHops) {
      final hops = <ChainHopTest>[];
      for (final row in rows) {
        if (row
            case {
              'hop': int hop,
              'latency': int latency,
              'passed': bool ok,
              'error': String error
            }
            when hop == hops.length + 1 &&
                latency >= 0 &&
                error.length <= 512) {
          hops.add(ChainHopTest(
              hop: hop, latency: latency, passed: ok, error: error));
        } else {
          throw const ChainException('链路测试响应无效');
        }
      }
      if (passed && (hops.length < 2 || hops.any((hop) => !hop.passed))) {
        throw const ChainException('链路测试响应不完整');
      }
      if (!passed &&
          (hops.isEmpty ||
              hops.last.passed ||
              hops.take(hops.length - 1).any((hop) => !hop.passed))) {
        throw const ChainException('链路测试失败段无效');
      }
      return ChainTestResult(
          fingerprint: fingerprint,
          checkedAt: DateTime.fromMillisecondsSinceEpoch(at),
          passed: passed,
          hops: hops);
    }
    throw const ChainException('链路测试响应无效');
  }
}

abstract interface class ChainRepository {
  Stream<List<ProxyChain>> watch();
  Stream<String?> watchSelectedId();
  Future<ProxyChain> save(ChainSnapshot draft, {ChainTestResult? test});
  Future<void> select(ProxyChain chain);
  Future<void> delete(ProxyChain chain);
}

abstract interface class ChainTester {
  Future<void> validateChain(ChainSnapshot chain);
  Future<ChainTestResult> testChain(ChainSnapshot chain);
  Future<void> cancelChainTest();
}
