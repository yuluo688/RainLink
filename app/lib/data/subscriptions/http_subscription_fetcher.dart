import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../../domain/groups/node_group.dart';
import '../../domain/nodes/proxy_node.dart';
import 'subscription_parser.dart';

class HttpSubscriptionFetcher implements SubscriptionFetcher {
  const HttpSubscriptionFetcher(
      {this.timeout = const Duration(seconds: 20),
      this.maxBytes = 8 * 1024 * 1024,
      this.localProxyPort});
  final Duration timeout;
  final int maxBytes;

  /// Resolved once per download so redirects retain the selected local endpoint.
  /// null means direct; a supplied endpoint is always a local RainLink listener.
  final int? Function()? localProxyPort;

  @override
  Future<SubscriptionDocument> fetch(
      Uri url, SubscriptionCancellation cancellation) async {
    cancellation.check();
    final port = localProxyPort?.call();
    if (port != null && (port < 1 || port > 65535)) {
      throw const NodeException('当前连接的本地代理端口无效，请重新连接');
    }
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..findProxy = (_) => port == null ? 'DIRECT' : 'PROXY 127.0.0.1:$port';
    cancellation.bind(() => client.close(force: true));
    try {
      return await _fetch(client, url, cancellation).timeout(timeout,
          onTimeout: () {
        client.close(force: true);
        throw const NodeException('订阅请求超时，请检查网络后重试');
      });
    } on NodeException {
      rethrow;
    } on Exception {
      cancellation.check();
      // Network exceptions may contain a token-bearing URL; never expose them.
      throw NodeException(
          port == null ? '无法获取订阅，请检查地址、证书与网络' : '无法通过当前连接获取订阅，请检查节点或重连后重试');
    } finally {
      cancellation.bind(null);
      client.close(force: true);
    }
  }

  Future<SubscriptionDocument> _fetch(
      HttpClient client, Uri initial, SubscriptionCancellation cancel) async {
    var url = initial;
    for (var redirects = 0; redirects <= 5; redirects++) {
      cancel.check();
      final request = await client.getUrl(url);
      request.followRedirects = false;
      // Providers negotiate newer YAML formats using the clash.meta token.
      // Keep RainLink's identity rather than claiming another app's version.
      request.headers
          .set(HttpHeaders.userAgentHeader, 'clash.meta RainLink/0.1');
      request.headers.set(HttpHeaders.acceptHeader,
          'application/yaml, application/json, text/plain, */*');
      final response = await request.close();
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null || redirects == 5) {
          throw const NodeException('订阅重定向无效或次数过多');
        }
        final next = validateSubscriptionUrl(url.resolve(location).toString());
        if (url.scheme == 'https' && next.scheme != 'https') {
          throw const NodeException('订阅重定向降低了连接安全性');
        }
        // Do not drain arbitrary redirect bodies; close this response socket.
        final socket = await response.detachSocket();
        socket.destroy();
        url = next;
        continue;
      }
      if (response.statusCode != 200) {
        throw NodeException('订阅服务器返回 HTTP ${response.statusCode}');
      }
      if (response.contentLength > maxBytes) {
        throw const NodeException('订阅内容超过大小限制（8 MB）');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        cancel.check();
        if (bytes.length + chunk.length > maxBytes) {
          throw const NodeException('订阅内容超过大小限制（8 MB）');
        }
        bytes.addAll(chunk);
      }
      final headers = <String, String>{};
      for (final key in [
        'profile-title',
        'content-disposition',
        'subscription-userinfo',
        'profile-update-interval'
      ]) {
        final value = response.headers.value(key);
        if (value != null) headers[key] = value;
      }
      final document =
          await Isolate.run(_ParseJob(bytes, headers, initial).parse);
      cancel.check();
      return document;
    }
    throw const NodeException('订阅重定向次数过多');
  }
}

// A bound method sends only this payload; never capture the HTTP client's scope.
class _ParseJob {
  const _ParseJob(this.bytes, this.headers, this.source);
  final List<int> bytes;
  final Map<String, String> headers;
  final Uri source;
  SubscriptionDocument parse() =>
      parseSubscription(utf8.decode(bytes), headers, source);
}
