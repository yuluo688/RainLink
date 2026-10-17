import 'package:rainlink/domain/groups/node_group.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';

/// Opaque in-memory test adapter. Real DPAPI is covered by native integration.
class TestSecretStore implements SecretStore {
  final Map<String, (String, NodeCredentials)> _entries = {};
  bool fail = false;
  void Function()? onProtect;
  @override
  Future<String> protect(String id, String username, String password,
      {String obfsPassword = ''}) async {
    if (fail) throw const NodeException('无法安全保存凭据');
    final cipher = 'opaque-${_entries.length}';
    _entries[cipher] = (
      id,
      NodeCredentials(
          username: username, password: password, obfsPassword: obfsPassword)
    );
    onProtect?.call();
    return cipher;
  }

  @override
  Future<NodeCredentials> reveal(String id, String cipher) async {
    final entry = _entries[cipher];
    if (entry == null || entry.$1 != id) throw const NodeException('凭据身份不匹配');
    return entry.$2;
  }
}

NodeDraft subscriptionNode(
        {String name = '日本 01',
        String server = 'jp.example.test',
        String password = 'fixture-password'}) =>
    NodeDraft(
        name: name,
        protocol: NodeProtocol.shadowsocks,
        server: server,
        port: 443,
        authenticate: true,
        password: password);

SubscriptionDocument subscriptionDocument(
        {List<NodeDraft>? nodes, String name = '测试订阅', bool metadata = true}) =>
    SubscriptionDocument(
        name: name,
        nodes: nodes ?? [subscriptionNode()],
        uploaded: metadata ? 1024 : null,
        downloaded: metadata ? 4096 : null,
        total: metadata ? 1024 * 1024 : null,
        expiresAt: metadata ? DateTime.utc(2030, 1, 1) : null);

class TestSubscriptionFetcher implements SubscriptionFetcher {
  SubscriptionDocument document = subscriptionDocument();
  Future<SubscriptionDocument> Function(Uri, SubscriptionCancellation)? handler;
  int calls = 0;
  @override
  Future<SubscriptionDocument> fetch(
      Uri url, SubscriptionCancellation cancellation) async {
    calls++;
    cancellation.check();
    if (handler case final callback?) return callback(url, cancellation);
    return document;
  }
}
