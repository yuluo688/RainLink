enum NodeProtocol {
  http('HTTP', 'http'),
  socks5('SOCKS5', 'socks'),
  shadowsocks('Shadowsocks', 'shadowsocks'),
  vless('VLESS', 'vless'),
  vmess('VMess', 'vmess'),
  trojan('Trojan', 'trojan'),
  hysteria2('Hysteria2', 'hysteria2'),
  tuic('TUIC', 'tuic');

  const NodeProtocol(this.label, this.wireName);
  final String label;
  final String wireName;
  bool get usesQuic => this == hysteria2 || this == tuic;
}

/// Public transport settings; passwords and UUIDs belong in protected credentials.
class NodeOptions {
  const NodeOptions({
    this.method = 'aes-128-gcm',
    this.serverName = '',
    this.insecure = false,
    this.transport = 'tcp',
    this.path = '/',
    this.host = '',
    this.serviceName = '',
    this.flow = '',
    this.fingerprint = '',
    this.certificateSha256 = '',
    this.realityPublicKey = '',
    this.realityShortId = '',
    this.alpn = const [],
    this.obfs = '',
    this.upMbps = 0,
    this.downMbps = 0,
    this.serverPorts = const [],
    this.hopIntervalSeconds = 0,
    this.vmessSecurity = 'auto',
    this.alterId = 0,
    this.globalPadding = false,
    this.authenticatedLength = false,
    this.packetEncoding = '',
    this.congestionControl = 'cubic',
    this.udpRelayMode = 'native',
    this.udpOverStream = false,
    this.zeroRttHandshake = false,
    this.heartbeatMillis = 10000,
    this.disableSni = false,
  });
  final String method;
  final String serverName;
  final bool insecure;
  final String transport;
  final String path;
  final String host;
  final String serviceName;
  final String flow;
  final String fingerprint;
  final String certificateSha256;
  final String realityPublicKey;
  final String realityShortId;
  final List<String> alpn;
  final String obfs;
  final int upMbps;
  final int downMbps;
  final List<String> serverPorts;
  final int hopIntervalSeconds;
  final String vmessSecurity;
  final int alterId;
  final bool globalPadding;
  final bool authenticatedLength;
  final String packetEncoding;
  final String congestionControl;
  final String udpRelayMode;
  final bool udpOverStream;
  final bool zeroRttHandshake;
  final int heartbeatMillis;
  final bool disableSni;

  Map<String, Object> toJson() => {
        'method': method,
        'serverName': serverName,
        'insecure': insecure,
        'transport': transport,
        'path': path,
        'host': host,
        'serviceName': serviceName,
        'flow': flow,
        'fingerprint': fingerprint,
        'certificateSha256': certificateSha256,
        'realityPublicKey': realityPublicKey,
        'realityShortId': realityShortId,
        'alpn': alpn,
        'obfs': obfs,
        'upMbps': upMbps,
        'downMbps': downMbps,
        'serverPorts': serverPorts,
        'hopIntervalSeconds': hopIntervalSeconds,
        'vmessSecurity': vmessSecurity,
        'alterId': alterId,
        'globalPadding': globalPadding,
        'authenticatedLength': authenticatedLength,
        'packetEncoding': packetEncoding,
        'congestionControl': congestionControl,
        'udpRelayMode': udpRelayMode,
        'udpOverStream': udpOverStream,
        'zeroRttHandshake': zeroRttHandshake,
        'heartbeatMillis': heartbeatMillis,
        'disableSni': disableSni,
      };

  factory NodeOptions.fromJson(Map<String, Object?> json) => NodeOptions(
        method: json['method'] as String? ?? 'aes-128-gcm',
        serverName: json['serverName'] as String? ?? '',
        insecure: json['insecure'] as bool? ?? false,
        transport: json['transport'] as String? ?? 'tcp',
        path: json['path'] as String? ?? '/',
        host: json['host'] as String? ?? '',
        serviceName: json['serviceName'] as String? ?? '',
        flow: json['flow'] as String? ?? '',
        fingerprint: json['fingerprint'] as String? ?? '',
        certificateSha256: json['certificateSha256'] as String? ?? '',
        realityPublicKey: json['realityPublicKey'] as String? ?? '',
        realityShortId: json['realityShortId'] as String? ?? '',
        alpn: (json['alpn'] as List<Object?>? ?? const []).cast<String>(),
        obfs: json['obfs'] as String? ?? '',
        upMbps: json['upMbps'] as int? ?? 0,
        downMbps: json['downMbps'] as int? ?? 0,
        serverPorts:
            (json['serverPorts'] as List<Object?>? ?? const []).cast<String>(),
        hopIntervalSeconds: json['hopIntervalSeconds'] as int? ?? 0,
        vmessSecurity: json['vmessSecurity'] as String? ?? 'auto',
        alterId: json['alterId'] as int? ?? 0,
        globalPadding: json['globalPadding'] as bool? ?? false,
        authenticatedLength: json['authenticatedLength'] as bool? ?? false,
        packetEncoding: json['packetEncoding'] as String? ?? '',
        congestionControl: json['congestionControl'] as String? ?? 'cubic',
        udpRelayMode: json['udpRelayMode'] as String? ?? 'native',
        udpOverStream: json['udpOverStream'] as bool? ?? false,
        zeroRttHandshake: json['zeroRttHandshake'] as bool? ?? false,
        heartbeatMillis: json['heartbeatMillis'] as int? ?? 10000,
        disableSni: json['disableSni'] as bool? ?? false,
      );
}

class ProxyNode {
  const ProxyNode(
      {required this.id,
      required this.name,
      required this.protocol,
      required this.server,
      required this.port,
      this.tls = false,
      this.options = const NodeOptions(),
      this.groupId,
      this.sourceKey = '',
      this.credential = '',
      this.revision = 1,
      this.originalName,
      this.favorite = false,
      this.hidden = false});

  final String id;
  final String name;
  final String? originalName;
  String get sourceName => originalName ?? name;
  bool get hasAlias => originalName != null && originalName != name;
  final bool favorite;
  final bool hidden;
  final NodeProtocol protocol;
  final String server;
  final int port;
  final bool tls;
  final NodeOptions options;
  final String? groupId;

  /// Nonempty only for nodes managed by a subscription.
  final String sourceKey;
  bool get subscriptionManaged => sourceKey.isNotEmpty;

  /// User-bound encrypted credentials. Plaintext is never stored in SQLite.
  final String credential;
  final int revision;

  Map<String, Object> toHost() => {
        'id': id,
        'name': name,
        'protocol': protocol.wireName,
        'server': server,
        'port': port,
        'tls': tls,
        'options': options.toJson(),
        'credential': credential,
        'revision': revision
      };
}

class NodeDraft {
  const NodeDraft(
      {required this.name,
      required this.protocol,
      required this.server,
      required this.port,
      this.tls = false,
      this.authenticate = false,
      this.username = '',
      this.password = '',
      this.obfsPassword = '',
      this.options = const NodeOptions(),
      this.original});
  final String name;
  final NodeProtocol protocol;
  final String server;
  final int port;
  final bool tls;
  final bool authenticate;
  final String username;
  final String password;
  final String obfsPassword;
  final NodeOptions options;
  final ProxyNode? original;
}

class NodeCredentials {
  const NodeCredentials(
      {this.username = '', this.password = '', this.obfsPassword = ''});
  final String username;
  final String password;
  final String obfsPassword;
}

/// Reading secrets is reserved for subscription updates and credential reuse.
abstract interface class SecretStore implements CredentialProtector {
  Future<NodeCredentials> reveal(String id, String cipher);
}

abstract interface class CredentialProtector {
  Future<String> protect(String nodeId, String username, String password,
      {String obfsPassword = ''});
}

abstract interface class NodeRepository {
  Stream<List<ProxyNode>> watchNodes();
  Stream<String?> watchSelectedId();
  Future<ProxyNode> save(NodeDraft draft);
  Future<void> select(String id);
  Future<void> delete(String id);
}

class NodeException implements Exception {
  const NodeException(this.message);
  final String message;
  @override
  String toString() => message;
}
