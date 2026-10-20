import '../../domain/import/qr_import.dart';
import '../../domain/nodes/proxy_node.dart';
import '../subscriptions/subscription_parser.dart';

/// Shares the validated subscription/node grammar without fetching any URL.
class StandardQrImportParser implements QrImportParser {
  const StandardQrImportParser();
  static const maxCharacters = 65536;
  static const _nodeSchemes = {
    'http',
    'https',
    'socks',
    'socks5',
    'ss',
    'vless',
    'vmess',
    'trojan',
    'hysteria2',
    'hy2',
    'tuic',
  };
  static const _httpNodeOptions = {
    'security',
    'sni',
    'peer',
    'allowInsecure',
    'insecure',
    'fp',
    'alpn',
  };

  @override
  QrImport parse(String value) {
    if (value.length > maxCharacters) {
      throw const QrImportException('链接过长，请使用订阅地址或单个节点分享链接');
    }
    final text = value.trim();
    if (text.isEmpty || RegExp(r'[\x00-\x20\x7f]').hasMatch(text)) {
      throw const QrImportException('请提供一个完整的订阅地址或节点分享链接');
    }
    final separator = text.indexOf('://');
    if (separator <= 0) {
      throw const QrImportException('未识别到支持的订阅地址或节点分享链接');
    }
    final scheme = text.substring(0, separator).toLowerCase();
    if (!_nodeSchemes.contains(scheme)) {
      throw const QrImportException('未识别到支持的订阅地址或节点分享链接');
    }
    final normalized = '$scheme${text.substring(separator)}';
    try {
      if (scheme != 'http' && scheme != 'https') {
        return QrNode(parseNodeUri(normalized));
      }
      final uri = Uri.parse(normalized);
      if (uri.port < 1 || uri.port > 65535) {
        throw const QrImportException('链接端口应为 1–65535');
      }
      if (uri.userInfo.isNotEmpty ||
          uri.hasFragment ||
          uri.queryParameters.keys.any(_httpNodeOptions.contains)) {
        return QrNode(parseNodeUri(normalized));
      }
      final subscription = QrSubscription(validateSubscriptionUrl(normalized));
      final explicitPort = RegExp(
        r'^https?://(?:\[[^\]]+\]|[^/?#:]+):[0-9]+(?:[/?#]|$)',
      ).hasMatch(normalized);
      if (explicitPort &&
          (uri.path.isEmpty || uri.path == '/') &&
          !uri.hasQuery) {
        return QrHttpChoice(
          subscription: subscription,
          node: QrNode(parseNodeUri(normalized)),
        );
      }
      return subscription;
    } on NodeException {
      throw const QrImportException('链接参数无效或暂不支持，请检查分享内容');
    } on FormatException {
      throw const QrImportException('链接格式无效，请检查分享内容');
    } on ArgumentError {
      // URI port/base64 validation can throw ArgumentError at this boundary.
      throw const QrImportException('链接格式无效，请检查分享内容');
    }
  }
}
