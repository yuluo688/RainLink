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
import 'package:rainlink/app/router.dart';
import 'package:rainlink/application/chains/chain_providers.dart';
import 'package:rainlink/application/connection/connection_providers.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/application/preferences/device_settings_controller.dart';
import 'package:rainlink/application/routing/routing_providers.dart';
import 'package:rainlink/application/telemetry/core_log_collector.dart';
import 'package:rainlink/data/chains/chain_records.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/preferences/drift_preferences_repository.dart';
import 'package:rainlink/domain/chains/proxy_chain.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/core/advanced_config.dart';
import 'package:rainlink/domain/core/runtime_settings.dart';
import 'package:rainlink/domain/core/session_gateway.dart';
import 'package:rainlink/domain/core/core_telemetry.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/domain/routing/route_rules.dart';

import 'support/local_proxy_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'Android visual chains, rule targets and live configuration use the actual core',
      (tester) async {
    expect(Platform.isAndroid, isTrue);
    // The drive isolate can start before Android attaches a nonzero surface.
    // Keep the real device dimensions rather than rendering a zero-size view.
    await tester.runAsync(() async {
      final view = binding.platformDispatcher.implicitView;
      if (view == null) throw StateError('Android did not attach a view');
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (view.physicalSize.isEmpty) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Android surface did not become ready');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    final database = AppDatabase(NativeDatabase.memory());
    final hits = <String>[];
    final sockets = <Socket>{};
    final first = await LocalProxyFixture.start('A', hits, sockets);
    final second = await LocalProxyFixture.start('B', hits, sockets);
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var originRequests = 0;
    final serving = origin.listen((request) {
      originRequests++;
      request.response.write('RainLink Android configuration actual core');
      unawaited(request.response.close());
    });
    final router = createRouter(initialLocation: '/chain');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    ProviderContainer? container;
    var successfulResponses = 0;
    var requestSequence = 0;
    var requestToken = '';
    try {
      await tester.pumpWidget(ProviderScope(
          overrides: createAppOverrides(
              database: database, initialTheme: AppTheme.dark),
          child: RainlinkApp(router: router)));
      await tester.pumpAndSettle();
      debugPrint('RAINLINK_CONFIG: actual mobile UI ready');
      final scope =
          ProviderScope.containerOf(tester.element(find.byType(RainlinkApp)));
      container = scope;
      final session = scope.read(sessionControllerProvider.notifier);
      await session.initialized;
      final nodes = scope.read(nodeRepositoryProvider);
      final a = await nodes.save(NodeDraft(
          name: '本地入口 A',
          protocol: NodeProtocol.http,
          server: '127.0.0.1',
          port: first.server.port));
      final b = await nodes.save(NodeDraft(
          name: '本地出口 B',
          protocol: NodeProtocol.http,
          server: '127.0.0.1',
          port: second.server.port));
      final rules = scope.read(routeRepositoryProvider);
      RouteRuleSet fallback(RouteTarget target, int revision) =>
          RouteRuleSet(revision: revision, rules: [
            RouteRule(
                id: 'fallback',
                kind: RouteRuleKind.match,
                value: '',
                target: target)
          ]);
      await rules.save(fallback(const RouteTarget(RouteTargetKind.proxy), 0));
      await tester.pumpAndSettle();
      for (final node in [a, b]) {
        await tester.ensureVisible(find.byKey(const ValueKey('chain-add-hop')));
        await tester.tap(find.byKey(const ValueKey('chain-add-hop')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('chain-pick-${node.id}')));
        await tester.pumpAndSettle();
        debugPrint('RAINLINK_CONFIG: visual hop selected ${node.name}');
      }
      await tester.enterText(find.byType(TextFormField).first, '本地双跳验收');
      expect(scope.read(chainEditorProvider).draft.hopIds, [a.id, b.id]);
      await tester.ensureVisible(find.byKey(const ValueKey('chain-save')));
      await tester.tap(find.byKey(const ValueKey('chain-save')));
      debugPrint('RAINLINK_CONFIG: visual chain validation started');
      await tester.pumpAndSettle();
      for (var attempt = 0;
          attempt < 300 && scope.read(chainEditorProvider).saving;
          attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(scope.read(chainEditorProvider).saving, isFalse,
          reason: 'The actual native chain validation must finish');
      expect(scope.read(chainEditorProvider).error, isEmpty,
          reason: 'The visual editor must save through the actual native core');
      final saved = (await loadChains(database)).single;
      debugPrint('RAINLINK_CONFIG: visual chain persisted');
      expect(saved.hopIds, [a.id, b.id]);
      expect(scope.read(sessionControllerProvider).connected, isFalse);
      router.go('/overview');
      await scope.read(coreStatusProvider.future);
      scope.read(proxyModeProvider.notifier).state = ProxyMode.rule;
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('connect-button')));
      await tester.pumpAndSettle();
      for (var attempt = 0;
          attempt < 900 && scope.read(sessionControllerProvider).working;
          attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      var active = scope.read(sessionControllerProvider).active;
      expect(scope.read(sessionControllerProvider).connected, isTrue,
          reason: scope.read(sessionControllerProvider).error);
      expect(active?.target.kind, 'chain');
      expect(active?.target.id, saved.id);
      expect(scope.read(sessionControllerProvider).tun, isTrue);

      Future<String> transfer() async {
        hits.clear();
        requestToken = 'configuration-${++requestSequence}';
        final port = scope.read(sessionControllerProvider).active?.proxyPort;
        expect(port, isNotNull);
        client.findProxy = (_) => 'PROXY 127.0.0.1:$port';
        final request = await client
            .getUrl(Uri.parse('http://127.0.0.1:${origin.port}/configuration'))
            .timeout(const Duration(seconds: 5));
        request.headers.set(HttpHeaders.connectionHeader, 'close');
        request.headers.set('x-rainlink-qa', requestToken);
        final response =
            await request.close().timeout(const Duration(seconds: 5));
        return utf8.decoder
            .bind(response)
            .join()
            .timeout(const Duration(seconds: 5));
      }

      Future<void> assertPath(String entry, String exit, int exitPort) async {
        String response;
        try {
          response = await transfer();
        } on Exception {
          final logs =
              await (scope.read(coreGatewayProvider) as CoreTelemetryGateway)
                  .logs();
          debugPrint('RAINLINK_CONFIG_FAILURE: ${jsonEncode({
                'accepted': [...first.accepted, ...second.accepted],
                'fixtureErrors': [...first.failures, ...second.failures],
                'forwarded': hits,
                'originRequests': originRequests,
                'logs': logs.entries.map((entry) => entry.message).toList(),
              })}');
          rethrow;
        }
        expect(response, 'RainLink Android configuration actual core');
        successfulResponses++;
        // Background public probes may open other A -> B tunnels. Verify the
        // actual marked HTTP request at both hops, with no extra forwarding.
        final entryFixture = entry == 'A' ? first : second;
        final exitFixture = exit == 'A' ? first : second;
        expect(entryFixture.requestPaths[requestToken],
            ['$entry>127.0.0.1:$exitPort']);
        expect(exitFixture.requestPaths[requestToken],
            ['$exit>127.0.0.1:${origin.port}']);
      }

      await assertPath('A', 'B', second.server.port);
      debugPrint('RAINLINK_CONFIG: actual forward path verified');
      final chains = scope.read(chainRepositoryProvider);
      final reversed = await chains
          .save(ChainSnapshot(saved.copyWith(hopIds: [b.id, a.id]), [b, a]));
      await nodes.select(b.id);
      await assertPath('A', 'B', second.server.port);

      final preferences = scope.read(deviceSettingsControllerProvider.notifier);
      final blocked = AdvancedConfig.parse(
          jsonEncode({
            'log': {'level': 'debug'},
            'route': {
              'rules': [
                {
                  'ip_cidr': ['127.0.0.1/32'],
                  'port': [origin.port],
                  'action': 'reject'
                }
              ]
            }
          }),
          ConfigFormat.json);
      final originalSession = active?.sessionId;
      await preferences.applyAdvanced(blocked,
          expectedRuntime: scope.read(deviceSettingsControllerProvider).runtime,
          expectedSessionRevision: session.operationRevision);
      debugPrint('RAINLINK_CONFIG: live advanced patch applied');
      active = scope.read(sessionControllerProvider).active;
      expect(active?.sessionId, isNot(originalSession));
      expect(active?.target.id, saved.id);
      expect(active?.target.revision, saved.revision);
      expect(active?.mode, ProxyMode.rule);
      expect(active?.routeBindings['proxy/hop/0']?.id, a.id);
      expect(active?.routeBindings['proxy/hop/1']?.id, b.id);
      final beforeReject = originRequests;
      var receivedPayload = false;
      try {
        receivedPayload =
            (await transfer()) == 'RainLink Android configuration actual core';
      } on IOException {
        // A reset or a proxy error is expected for an actual reject rule.
      }
      expect(receivedPayload, isFalse);
      expect(originRequests, beforeReject);
      final persisted =
          await DriftPreferencesRepository(database).loadDeviceSettings();
      expect(persisted.runtime.advanced.canonicalJson, blocked.canonicalJson);
      expect(persisted.previousAdvanced?.isEmpty, isTrue);

      await preferences.applyAdvanced(const AdvancedConfig.empty(),
          expectedRuntime: scope.read(deviceSettingsControllerProvider).runtime,
          expectedSessionRevision: session.operationRevision);
      await assertPath('A', 'B', second.server.port);
      debugPrint('RAINLINK_CONFIG: previous behavior restored');
      final reverted =
          await DriftPreferencesRepository(database).loadDeviceSettings();
      expect(reverted.runtime.advanced.isEmpty, isTrue);
      expect(reverted.previousAdvanced?.canonicalJson, blocked.canonicalJson);

      final occupied = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      try {
        await expectLater(
            session.applyRuntime(scope
                .read(deviceSettingsControllerProvider)
                .runtime
                .copyWith(proxyPort: occupied.port)),
            throwsA(isA<SettingsException>()));
        expect(scope.read(sessionControllerProvider).connected, isTrue);
        expect(
            scope.read(sessionControllerProvider).active?.target.id, saved.id);
        await assertPath('A', 'B', second.server.port);
        debugPrint('RAINLINK_CONFIG: failed restart recovered');
      } finally {
        await occupied.close();
      }

      await session.disconnect();
      await session.connectChain(reversed, ProxyMode.rule);
      await assertPath('B', 'A', first.server.port);
      debugPrint('RAINLINK_CONFIG: reversed path verified');
      await session.disconnect();
      await rules.save(fallback(RouteTarget(RouteTargetKind.chain, reversed.id),
          (await rules.load()).revision));
      await session.connect(a, ProxyMode.rule);
      expect(scope.read(sessionControllerProvider).active?.target.kind, 'node');
      expect(
          scope
              .read(sessionControllerProvider)
              .active
              ?.routeBindings['chain:${reversed.id}/hop/0']
              ?.id,
          b.id);
      await assertPath('B', 'A', first.server.port);
      await session.setMode(ProxyMode.global);
      expect(await transfer(), 'RainLink Android configuration actual core');
      successfulResponses++;
      expect(first.requestPaths[requestToken], ['A>127.0.0.1:${origin.port}']);
      expect(second.requestPaths[requestToken], isNull);
      await session.setMode(ProxyMode.direct);
      expect(await transfer(), 'RainLink Android configuration actual core');
      successfulResponses++;
      expect(first.requestPaths[requestToken], isNull);
      expect(second.requestPaths[requestToken], isNull);
      await session.setMode(ProxyMode.rule);
      await assertPath('B', 'A', first.server.port);
      await session.disconnect();
      expect(
          (await (scope.read(coreGatewayProvider) as SessionGateway).observe())
              .active,
          isNull);
      expect(tester.takeException(), isNull);
      binding.reportData = {
        'configuration': {
          'scope':
              'actual Android gateway, Keystore, memory SQLite and libbox; localhost HTTP CONNECT fixtures; no remote subscription',
          'visualEditorSavedWithoutConnecting': true,
          'overviewConnectedSavedChain': true,
          'actualForwardAndReverseOrderVerified': true,
          'editingAndSelectionKeptActivePath': true,
          'liveAdvancedRejectPreventedActualRequest': true,
          'liveApplyKeptOriginalTargetModeAndHops': true,
          'advancedAndPreviousPersistedAtomically': true,
          'failedRestartRestoredActualTransfer': true,
          'ruleChainAndAllThreeModesVerified': true,
          'successfulResponses': successfulResponses,
          'originRequests': originRequests,
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
      router.dispose();
      for (final socket in sockets) {
        socket.destroy();
      }
      await first.server.close();
      await second.server.close();
      await origin.close(force: true);
      await serving.cancel();
      await database.close();
    }
  });
}
