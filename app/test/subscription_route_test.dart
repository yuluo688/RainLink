import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/app/dependencies.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/groups/group_providers.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/groups/node_group.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/platform/core/unavailable_core_gateway.dart';

class _Session extends SessionController {
  _Session()
      : super(const UnavailableCoreGateway('route fixture'), onMode: (_) {});
  void publish(SessionView value) => state = value;
}

SessionView _connected(int port) => SessionView(
    phase: ConnectionPhase.connected,
    active: ActiveConnectionSnapshot(
        sessionId: 'subscription-route',
        target: const ProxyTarget(id: 'node', name: 'Fixture', revision: 1),
        mode: ProxyMode.global,
        configRevision: 'route-fixture',
        proxyPort: port));

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late _Session session;
  late HttpServer origin;
  late HttpServer proxy;
  late Uri url;
  var originRequests = 0;
  var proxyRequests = 0;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    session = _Session();
    container = ProviderContainer(overrides: [
      ...createAppOverrides(database: db, initialTheme: AppTheme.dark),
      sessionControllerProvider.overrideWith((ref) => session),
    ]);
    originRequests = 0;
    proxyRequests = 0;
    origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = Uri.parse('http://127.0.0.1:${origin.port}/subscription');
    origin.listen((request) async {
      originRequests++;
      request.response.write('socks5://edge.example.test:1080#Direct');
      await request.response.close();
    });
    proxy.listen((request) async {
      proxyRequests++;
      request.response.write('socks5://edge.example.test:1080#Proxy');
      await request.response.close();
    });
  });
  tearDown(() async {
    container.dispose();
    await db.close();
    await origin.close(force: true);
    await proxy.close(force: true);
  });
  test(
      'production dependencies resolve each fetch without rebuilding repositories or previews',
      () async {
    final repository = container.read(groupRepositoryProvider);
    final fetcher = container.read(subscriptionFetcherProvider);
    Future<String> fetch() async =>
        (await fetcher.fetch(url, SubscriptionCancellation()))
            .nodes
            .single
            .name;
    expect(await fetch(), 'Direct');
    session.publish(_connected(proxy.port));
    expect(await fetch(), 'Proxy');
    expect(
        identical(container.read(groupRepositoryProvider), repository), isTrue);
    expect(identical(container.read(subscriptionFetcherProvider), fetcher),
        isTrue);
    session.publish(const SessionView());
    expect(await fetch(), 'Direct');
    expect(originRequests, 2);
    expect(proxyRequests, 1);
  });
  test(
      'changing and incomplete sessions refuse to fetch instead of silently going direct',
      () async {
    final fetcher = container.read(subscriptionFetcherProvider);
    for (final state in [
      const SessionView(phase: ConnectionPhase.starting),
      const SessionView(phase: ConnectionPhase.stopping),
      const SessionView(phase: ConnectionPhase.connected, busy: true),
      const SessionView(phase: ConnectionPhase.connected),
      _connected(0),
      _connected(65536),
    ]) {
      session.publish(state);
      await expectLater(fetcher.fetch(url, SubscriptionCancellation()),
          throwsA(isA<NodeException>()));
    }
    expect(originRequests, 0);
    expect(proxyRequests, 0);
  });
}
