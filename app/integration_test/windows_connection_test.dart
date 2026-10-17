import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rainlink/app/dependencies.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/core/session_gateway.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/platform/window/desktop_window.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const capture = bool.fromEnvironment('RAINLINK_CAPTURE_UI');
  const verifyEgress = bool.fromEnvironment('RAINLINK_TEST_PUBLIC_EGRESS');

  Future<void> captureWindow(String name) async {
    if (!capture) return;
    final result = await Process.run('python', [
      '../tools/capture_window.py',
      '--pid',
      '$pid',
      '--output',
      '../docs/verification/windows-session-$name.png',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
  }

  testWidgets(
      'manual node dialog connects through real core and restores capture',
      (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final upstream = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    var upstreamRequests = 0;
    final originRequests = origin.listen((request) async {
      request.response.headers.contentType = ContentType.text;
      request.response.write('RainLink real core integration');
      await request.response.close();
    });
    final proxyRequests = upstream.listen((local) async {
      sockets.add(local);
      final incoming = StreamIterator(local);
      try {
        final header = <int>[];
        var headerEnd = -1;
        while (headerEnd < 0 && await incoming.moveNext()) {
          header.addAll(incoming.current);
          headerEnd = latin1.decode(header).indexOf('\r\n\r\n');
          if (header.length > 8192) break;
        }
        if (headerEnd < 0) return;
        final firstLine = latin1.decode(header).split('\r\n').first;
        final target = Uri.parse('http://${firstLine.split(' ')[1]}');
        if (!firstLine.startsWith('CONNECT ') ||
            !verifyEgress &&
                (target.host != '127.0.0.1' || target.port != origin.port)) {
          local.write('HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n');
          await local.flush();
          return;
        }
        final remote = await Socket.connect(target.host, target.port)
            .timeout(const Duration(seconds: 8));
        sockets.add(remote);
        upstreamRequests++;
        local.write('HTTP/1.1 200 Connection Established\r\n\r\n');
        await local.flush();
        remote.listen(local.add,
            onDone: () => unawaited(local.close()),
            onError: (Object _) => local.destroy());
        remote.add(header.sublist(headerEnd + 4));
        while (await incoming.moveNext()) {
          remote.add(incoming.current);
        }
        await remote.flush();
        await remote.close();
      } on SocketException {
        // The core also probes public endpoints, which this fixture rejects.
      } on TimeoutException {
        // Public checks are optional and bounded independently of connection.
      } finally {
        await incoming.cancel();
        local.destroy();
      }
    });
    await initializeDesktopWindow();
    await tester.pumpWidget(ProviderScope(
        overrides:
            createAppOverrides(database: database, initialTheme: AppTheme.dark),
        child: const RainlinkApp()));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(RainlinkApp)));
    final gateway = container.read(coreGatewayProvider);
    final status = await container.read(coreStatusProvider.future);
    expect(status.capabilities.connect, isTrue);
    try {
      await tester.tap(find.byKey(const ValueKey('nav-nodes')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-node')));
      await tester.pumpAndSettle();
      await captureWindow('add-node');
      await tester.enterText(
          find.byKey(const ValueKey('node-name')), '本机验证 · HTTP');
      await tester.enterText(
          find.byKey(const ValueKey('node-server')), '127.0.0.1');
      await tester.enterText(
          find.byKey(const ValueKey('node-port')), upstream.port.toString());
      await tester.tap(find.byKey(const ValueKey('save-node')));
      await tester.pumpAndSettle();
      final node =
          (await container.read(nodeRepositoryProvider).watchNodes().first)
              .single;
      await tester.tap(find.byKey(ValueKey('node-${node.id}')));
      await tester.pumpAndSettle();
      await captureWindow('nodes');
      await tester.tap(find.byKey(const ValueKey('nav-overview')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全局'));
      await tester.pumpAndSettle();
      await container
          .read(sessionControllerProvider.notifier)
          .setSystemProxy(true);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('connect-button')));
      for (var attempt = 0;
          attempt < 100 && !container.read(sessionControllerProvider).connected;
          attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(container.read(sessionControllerProvider).connected, isTrue,
          reason: container.read(sessionControllerProvider).error);
      expect(find.text('断开连接'), findsOneWidget);
      expect(find.text('未连接'), findsNothing);
      expect(find.text('已连接'), findsNWidgets(2));
      final proxyResult = await Process.run('reg', const [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyServer'
      ]);
      final match = RegExp(r'127\.0\.0\.1:(\d+)')
          .firstMatch(proxyResult.stdout.toString());
      expect(match, isNotNull);
      final client = HttpClient()
        ..findProxy = (_) => 'PROXY 127.0.0.1:${match?.group(1)}';
      try {
        final request = await client
            .getUrl(Uri.parse('http://127.0.0.1:${origin.port}/verify'));
        final response = await request.close();
        final body = await utf8.decoder.bind(response).join();
        expect(response.statusCode, HttpStatus.ok, reason: body);
        expect(body, 'RainLink real core integration');
      } finally {
        client.close(force: true);
      }
      expect(upstreamRequests, greaterThan(0));
      final interactive = gateway as SessionGateway;
      // Overlapping UI polling and actions must not write into a flushing sink.
      await Future.wait([
        interactive.observe(),
        interactive.observe(),
        interactive.probe(),
        interactive.setMode(ProxyMode.global),
      ]);
      await container.read(sessionControllerProvider.notifier).refresh();
      if (verifyEgress) {
        final deadline = DateTime.now().add(const Duration(seconds: 28));
        while (DateTime.now().isBefore(deadline) &&
            (container.read(sessionControllerProvider).telemetry?.ip.isEmpty ??
                true)) {
          await tester.pump(const Duration(milliseconds: 400));
          await container.read(sessionControllerProvider.notifier).refresh();
        }
        expect(container.read(sessionControllerProvider).telemetry?.ip,
            isNotEmpty);
        expect(container.read(sessionControllerProvider).telemetry?.countryCode,
            isNotEmpty);
      }
      await tester.pumpAndSettle();
      // The country SVG loads after the first frame containing a probe result.
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      await captureWindow('connected');
      final telemetry = container.read(sessionControllerProvider).telemetry;
      expect(telemetry?.uploadTotal, greaterThan(0));
      expect(telemetry?.downloadTotal, greaterThan(0));
      await tester.tap(find.byKey(const ValueKey('connect-button')));
      for (var attempt = 0;
          attempt < 100 &&
              container.read(sessionControllerProvider).phase !=
                  ConnectionPhase.idle;
          attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
          container.read(sessionControllerProvider).phase, ConnectionPhase.idle,
          reason: container.read(sessionControllerProvider).error);
      expect(tester.takeException(), isNull);
    } finally {
      await gateway.disconnect();
      if (gateway is SessionGateway) await gateway.close();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      for (final socket in sockets) {
        socket.destroy();
      }
      await proxyRequests.cancel();
      await originRequests.cancel();
      await upstream.close();
      await origin.close(force: true);
      await database.close();
    }
  });
}
