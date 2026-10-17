import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rainlink/app/dependencies.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/app/router.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/core/session_gateway.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/platform/window/desktop_window.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('overview switches control real TUN and retain the active target',
      (tester) async {
    final directory = await Directory.systemTemp.createTemp('rainlink-tun-ui-');
    final db =
        AppDatabase(NativeDatabase(File('${directory.path}/test.sqlite')));
    final upstream = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    var transfers = 0;
    final upstreamEvents = upstream.listen((socket) {
      sockets.add(socket);
      var input = '';
      var tunnel = false;
      socket.listen((bytes) {
        input += latin1.decode(bytes);
        if (input.length > 8192) {
          socket.destroy();
          return;
        }
        final end = input.indexOf('\r\n\r\n');
        if (end < 0) return;
        if (!tunnel) {
          if (!input.startsWith('CONNECT 198.19.0.80:18080 HTTP/1.1')) {
            socket.destroy();
            return;
          }
          tunnel = true;
          socket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
          input = input.substring(end + 4);
          return;
        }
        if (input.startsWith('GET /rainlink-tun ')) {
          transfers++;
          socket.write('HTTP/1.1 200 OK\r\nContent-Length: 16\r\n'
              'Connection: close\r\n\r\nrainlink-tun-ui!');
          unawaited(socket.flush().then((_) => socket.close()));
          input = '';
        }
      }, onError: (Object _) => socket.destroy());
    });
    final router = createRouter(initialLocation: '/overview');
    final boundaryKey = GlobalKey();
    ProviderContainer? container;
    Process? watchdog;
    try {
      await initializeDesktopWindow();
      await tester.pumpWidget(ProviderScope(
          overrides:
              createAppOverrides(database: db, initialTheme: AppTheme.dark),
          child: RepaintBoundary(
              key: boundaryKey, child: RainlinkApp(router: router))));
      await tester.pumpAndSettle();
      final current =
          ProviderScope.containerOf(tester.element(find.byType(RainlinkApp)));
      container = current;
      final capabilities = await current.read(coreStatusProvider.future);
      expect(capabilities.capabilities.tun, isTrue);
      final nodes = current.read(nodeRepositoryProvider);
      final first = await nodes.save(NodeDraft(
          name: 'TUN 验收 A',
          protocol: NodeProtocol.http,
          server: '127.0.0.1',
          port: upstream.port));
      final second = await nodes.save(NodeDraft(
          name: '待应用 B',
          protocol: NodeProtocol.http,
          server: '127.0.0.1',
          port: upstream.port));
      await nodes.select(first.id);
      await tester.pumpAndSettle();

      // Inspect only this app's host; the watchdog checks its exact executable
      // path before opening a process handle and cannot target another client.
      final processResult = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'Get-CimInstance Win32_Process | Where-Object { '
            '\$_.ParentProcessId -eq $pid -and \$_.Name -eq "rainlink-host.exe" '
            '} | Select-Object ProcessId,ExecutablePath | ConvertTo-Json -Compress',
      ]);
      expect(processResult.exitCode, 0);
      final process = jsonDecode('${processResult.stdout}');
      expect(process, isA<Map<String, Object?>>());
      final host = process as Map<String, Object?>;
      watchdog = await Process.start('python', [
        '../tools/verify_tun.py',
        '--watchdog',
        '${host['ProcessId']}',
        '${host['ExecutablePath']}'
      ]);

      final controller = current.read(sessionControllerProvider.notifier);
      Future<void> waitFor(bool Function() condition) async {
        for (var attempt = 0; attempt < 250 && !condition(); attempt++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(condition(), isTrue,
            reason: current.read(sessionControllerProvider).error);
      }

      await tester.tap(find.text('全局'));
      await tester.tap(find.byKey(const ValueKey('capture-TUN 模式')));
      await tester.pumpAndSettle();
      expect(current.read(sessionControllerProvider).tun, isTrue);
      await tester.tap(find.byKey(const ValueKey('connect-button')));
      await waitFor(() => current.read(sessionControllerProvider).connected);
      expect(
          current.read(sessionControllerProvider).active?.target.id, first.id);
      final nativeGateway = current.read(coreGatewayProvider) as SessionGateway;
      expect((await nativeGateway.observe()).tun, isTrue);

      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      client.connectionTimeout = const Duration(seconds: 4);
      try {
        final request = await client
            .getUrl(Uri.parse('http://198.19.0.80:18080/rainlink-tun'));
        final response = await request.close();
        expect(response.statusCode, HttpStatus.ok);
        expect(await utf8.decoder.bind(response).join(), 'rainlink-tun-ui!');
      } finally {
        client.close(force: true);
      }
      expect(transfers, 1);
      await controller.refresh();
      await tester.pumpAndSettle();
      final boundary = boundaryKey.currentContext?.findRenderObject();
      expect(boundary, isA<RenderRepaintBoundary>());
      final image = await (boundary as RenderRepaintBoundary).toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      expect(png, isNotNull);
      final output = Directory('../docs/verification/tun');
      await output.create(recursive: true);
      await File('${output.path}/overview-native.png')
          .writeAsBytes(png!.buffer.asUint8List());

      await nodes.select(second.id);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('capture-TUN 模式')));
      await waitFor(() =>
          current.read(sessionControllerProvider).connected &&
          !current.read(sessionControllerProvider).tun);
      expect(
          current.read(sessionControllerProvider).active?.target.id, first.id);
      expect((await nativeGateway.observe()).tun, isFalse);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('capture-TUN 模式')));
      await waitFor(() =>
          current.read(sessionControllerProvider).connected &&
          current.read(sessionControllerProvider).tun);
      expect(
          current.read(sessionControllerProvider).active?.target.id, first.id);
      expect((await nativeGateway.observe()).tun, isTrue);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('connect-button')));
      await waitFor(() =>
          current.read(sessionControllerProvider).phase ==
          ConnectionPhase.idle);
      expect((await nativeGateway.observe()).active, isNull);
      expect(tester.takeException(), isNull);
      await File('${output.path}/flutter-evidence.json')
          .writeAsString('${const JsonEncoder.withIndent('  ').convert({
            'at': DateTime.now().toIso8601String(),
            'temporaryDatabase': true,
            'nativeWindows': true,
            'overviewSwitchStartedTUN': true,
            'unproxiedTcpCaptured': true,
            'actualTransfers': transfers,
            'switchRetainedOriginalTarget': true,
            'switchDisabledAndEnabledTUN': true,
            'overviewDisconnected': true,
            'systemProxyEnabled': false,
          })}\n');
    } finally {
      try {
        if (container case final current?) {
          final gateway = current.read(coreGatewayProvider);
          try {
            await gateway.disconnect();
          } finally {
            if (gateway is SessionGateway) await gateway.close();
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        router.dispose();
        await db.close();
        for (final socket in sockets) {
          socket.destroy();
        }
        await upstreamEvents.cancel();
        await upstream.close();
        await directory.delete(recursive: true);
        await watchdog?.exitCode.timeout(const Duration(seconds: 8));
      }
    }
  });
}
