import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/data/subscriptions/http_subscription_fetcher.dart';
import 'package:rainlink/domain/groups/node_group.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';

void main() {
  late HttpServer server;
  late Uri base;
  late Future<void> Function(HttpRequest) handler;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base =
        Uri.parse('http://127.0.0.1:${server.port}/sub?token=fixture-secret');
    server.listen((request) async {
      await handler(request);
    });
  });
  tearDown(() async => server.close(force: true));
  test('negotiates Meta-compatible node lists instead of provider placeholders',
      () async {
    handler = (request) async {
      final agent = request.headers.value(HttpHeaders.userAgentHeader) ?? '';
      final recognized = agent.toLowerCase().contains('clash.meta');
      request.response.write(recognized
          ? 'proxies: [{name: Tokyo, type: ss, server: edge.example.test, port: 443, cipher: aes-128-gcm, password: fixture}]'
          : 'proxies: [{name: 不支持您的代理软件, type: ss, server: 127.0.0.1, port: 6666, cipher: aes-128-gcm, password: fixture}]');
      await request.response.close();
    };
    final document = await const HttpSubscriptionFetcher()
        .fetch(base, SubscriptionCancellation());
    expect(document.nodes.single.server, 'edge.example.test');
  });
  test('real HTTP fetch handles redirects and subscription response headers',
      () async {
    handler = (request) async {
      if (request.uri.path == '/sub') {
        request.response.statusCode = 302;
        request.response.headers.set('location', '/actual');
      } else {
        request.response.headers.set('profile-title', 'Fixture');
        request.response.headers
            .set('subscription-userinfo', 'upload=1; download=2; total=100');
        request.response.write('socks5://localhost:1080#Test');
      }
      await request.response.close();
    };
    final document = await const HttpSubscriptionFetcher()
        .fetch(base, SubscriptionCancellation());
    expect(document.name, 'Fixture');
    expect(document.nodes.single.name, 'Test');
    expect(document.downloaded, 2);
  });
  test('local proxy endpoint is pinned for the download and its redirects',
      () async {
    var routeReads = 0;
    int? proxyPort = server.port;
    final requested = <Uri>[];
    handler = (request) async {
      requested.add(request.uri);
      if (requested.length == 1) {
        // A main-session change during a redirect must not leak the next request.
        proxyPort = null;
        request.response.statusCode = 302;
        request.response.headers.set('location', '/actual');
      } else {
        request.response.write('socks5://edge.example.test:1080#Proxy');
      }
      await request.response.close();
    };
    final document = await HttpSubscriptionFetcher(localProxyPort: () {
      routeReads++;
      return proxyPort;
    }).fetch(Uri.parse('http://must-use-proxy.invalid/sub'),
        SubscriptionCancellation());
    expect(document.nodes.single.name, 'Proxy');
    expect(routeReads, 1);
    expect(requested.map((uri) => uri.path), ['/sub', '/actual']);
    expect(
        requested.every((uri) => uri.host == 'must-use-proxy.invalid'), isTrue);
  });
  test('a failed local proxy never falls back to the reachable direct origin',
      () async {
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final closedPort = listener.port;
    await listener.close();
    var directRequests = 0;
    handler = (request) async {
      directRequests++;
      request.response.write('socks5://edge.example.test:1080#Unexpected');
      await request.response.close();
    };
    await expectLater(
        HttpSubscriptionFetcher(localProxyPort: () => closedPort)
            .fetch(base, SubscriptionCancellation()),
        throwsA(isA<NodeException>()
            .having((e) => e.message, 'route', contains('当前连接'))
            .having((e) => e.message, 'redacted',
                isNot(contains('fixture-secret')))));
    expect(directRequests, 0);
  });
  test('cancelled and invalid-route requests open no subscription connection',
      () async {
    var routeReads = 0;
    var requests = 0;
    handler = (request) async {
      requests++;
      await request.response.close();
    };
    final cancelled = SubscriptionCancellation()..cancel();
    await expectLater(
        HttpSubscriptionFetcher(localProxyPort: () {
          routeReads++;
          return server.port;
        }).fetch(base, cancelled),
        throwsA(isA<SubscriptionCancelled>()));
    expect(routeReads, 0);
    for (final port in [0, -1, 65536]) {
      await expectLater(
          HttpSubscriptionFetcher(localProxyPort: () => port)
              .fetch(base, SubscriptionCancellation()),
          throwsA(isA<NodeException>()));
    }
    expect(requests, 0);
  });
  test(
      'status errors, large responses and redirect loops are bounded and redacted',
      () async {
    for (final scenario in ['status', 'large', 'chunked', 'loop']) {
      handler = (request) async {
        if (scenario == 'status') {
          request.response.statusCode = 403;
          request.response.write('fixture-secret');
        }
        if (scenario == 'large') {
          request.response.contentLength = 100;
          request.response.write('a' * 100);
        }
        if (scenario == 'chunked') {
          request.response.write('a' * 100);
        }
        if (scenario == 'loop') {
          request.response.statusCode = 302;
          request.response.headers.set('location', '/sub');
        }
        await request.response.close();
      };
      await expectLater(
          const HttpSubscriptionFetcher(maxBytes: 64)
              .fetch(base, SubscriptionCancellation()),
          throwsA(isA<NodeException>().having((e) => e.message, 'redacted',
              isNot(contains('fixture-secret')))));
    }
  });
  for (final viaProxy in [false, true]) {
    test(
        'timeout and cancellation close subscription requests (proxy: $viaProxy)',
        () async {
      final requests = <Completer<void>>[];
      var arrived = Completer<void>();
      handler = (request) async {
        final pending = Completer<void>();
        requests.add(pending);
        if (!arrived.isCompleted) arrived.complete();
        await pending.future;
        try {
          await request.response.close();
        } on IOException {/* Request was deliberately closed. */}
      };
      final fetcher = HttpSubscriptionFetcher(
          localProxyPort: viaProxy ? () => server.port : null);
      final target =
          viaProxy ? Uri.parse('http://must-use-proxy.invalid/sub') : base;
      await expectLater(
          HttpSubscriptionFetcher(
                  timeout: const Duration(milliseconds: 80),
                  localProxyPort: viaProxy ? () => server.port : null)
              .fetch(target, SubscriptionCancellation()),
          throwsA(isA<NodeException>()));
      arrived = Completer<void>();
      final token = SubscriptionCancellation();
      final operation = fetcher.fetch(target, token);
      final expectation =
          expectLater(operation, throwsA(isA<SubscriptionCancelled>()));
      await arrived.future;
      token.cancel();
      await expectation;
      for (final request in requests) {
        request.complete();
      }
    });
  }
}
