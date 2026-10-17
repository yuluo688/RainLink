import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rainlink/app/dependencies.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/app/router.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/application/telemetry/core_log_collector.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/nodes/drift_node_repository.dart';
import 'package:rainlink/data/preferences/drift_preferences_repository.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/core/session_gateway.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/domain/preferences/general_preferences.dart';
import 'package:rainlink/platform/core/android_core_gateway.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'Android startup connects saved selection and UI recreation preserves the original native session',
      (tester) async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = origin.listen((request) {
      request.response.write('RainLink automatic startup actual core');
      unawaited(request.response.close());
    });
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    ProviderContainer? container;
    GoRouter? router;
    AppDatabase? database;
    var responses = 0;
    try {
      Future<ProviderContainer> launch(String name) async {
        final store = AppDatabase(NativeDatabase.memory());
        database = store;
        final preferences = DriftPreferencesRepository(store);
        await preferences
            .saveGeneral(const GeneralPreferences(autoConnect: true));
        await preferences.saveConnection(
            const ConnectionPreferences(mode: ProxyMode.direct));
        final bootstrap = AndroidCoreGateway();
        try {
          final nodes = DriftNodeRepository(store, bootstrap);
          final node = await nodes.save(NodeDraft(
              name: name,
              protocol: NodeProtocol.http,
              server: '127.0.0.1',
              port: 9,
              authenticate: true,
              username: 'fixture-user',
              password: 'fixture-password'));
          await nodes.select(node.id);
        } finally {
          bootstrap.dispose();
        }
        final appRouter = createRouter();
        router = appRouter;
        await tester.pumpWidget(ProviderScope(
            overrides: createAppOverrides(
                database: store,
                initialTheme: AppTheme.dark,
                initialSettings: await preferences.loadDeviceSettings()),
            child: RainlinkApp(router: appRouter)));
        await tester.pumpAndSettle();
        final scope =
            ProviderScope.containerOf(tester.element(find.byType(RainlinkApp)));
        container = scope;
        for (var attempt = 0;
            attempt < 200 && !scope.read(sessionControllerProvider).connected;
            attempt++) {
          if (scope.read(sessionControllerProvider).phase ==
              ConnectionPhase.failed) {
            break;
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(scope.read(sessionControllerProvider).connected, isTrue,
            reason: scope.read(sessionControllerProvider).error);
        return scope;
      }

      Future<void> transfer(ProviderContainer scope) async {
        final session = scope.read(sessionControllerProvider);
        expect(session.tun, isTrue);
        final port = session.active?.proxyPort;
        expect(port, isNotNull);
        client.findProxy = (_) => 'PROXY 127.0.0.1:$port';
        final response = await (await client
                .getUrl(Uri.parse('http://127.0.0.1:${origin.port}/startup')))
            .close();
        expect(
            await utf8.decoder
                .bind(response)
                .join()
                .timeout(const Duration(seconds: 5)),
            'RainLink automatic startup actual core');
        responses++;
      }

      final first = await launch('自动连接验收 A');
      final original = first.read(sessionControllerProvider).active;
      expect(original?.mode, ProxyMode.direct);
      await transfer(first);
      await first.read(coreLogCollectorProvider.notifier).suspend();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      router?.dispose();
      router = null;
      await database?.close();
      database = null;
      container = null;

      // The new UI deliberately selects B while the system still owns A.
      final second = await launch('待应用选择 B');
      final selectedId = await second.read(selectedNodeIdProvider.future);
      expect(selectedId, isNotNull);
      expect(selectedId, isNot(original?.target.id));
      final restored = second.read(sessionControllerProvider).active;
      expect(restored?.sessionId, original?.sessionId);
      expect(restored?.target.id, original?.target.id);
      await transfer(second);
      await second.read(sessionControllerProvider.notifier).disconnect();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(
          second.read(sessionControllerProvider).phase, ConnectionPhase.idle);
      expect((await second.read(coreGatewayProvider).inspect()).hostAvailable,
          isTrue);
      final native = second.read(coreGatewayProvider);
      expect(native, isA<SessionGateway>());
      final stopped = await (native as SessionGateway).observe();
      expect(stopped.phase, ConnectionPhase.idle);
      expect(stopped.active, isNull);
      expect(tester.takeException(), isNull);
      binding.reportData = {
        ...?binding.reportData,
        'startup': {
          'scope':
              'actual Android bridge, Keystore and core; isolated memory SQLite; localhost traffic through explicit proxy; UI recreation within the same Activity',
          'savedSelectionAutoConnected': true,
          'systemTunnelEstablished': true,
          'originalSessionSurvivedUiRecreation': true,
          'differentSelectedTargetDidNotReplaceActive': true,
          'foregroundResumeDidNotReconnectAfterManualStop': true,
          'nativeSessionIdleAfterManualStop': true,
          'actualCoreResponses': responses,
          'at': DateTime.now().toIso8601String(),
        }
      };
    } finally {
      client.close(force: true);
      if (container case final scope?) {
        await scope.read(coreLogCollectorProvider.notifier).suspend();
        await scope.read(coreGatewayProvider).disconnect();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      router?.dispose();
      await database?.close();
      await origin.close(force: true);
      await serving.cancel();
    }
  });
}
