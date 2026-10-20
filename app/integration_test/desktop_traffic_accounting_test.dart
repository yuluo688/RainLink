import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/traffic/drift_traffic_repository.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/connection/traffic_repository.dart';
import 'package:rainlink/domain/export/data_export.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/platform/core/desktop_core_gateway.dart';

import 'support/local_proxy_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real closed-flow accounting reaches durable SQLite and separate CSV partitions',
    (tester) async {
      // Use disposable platform data when invoking this test so production host
      // recovery cannot touch an interactive session.
      final local =
          Platform.environment[Platform.isWindows
              ? 'LOCALAPPDATA'
              : 'XDG_DATA_HOME'] ??
          '';
      expect(
        local.replaceAll('\\', '/'),
        contains('/traffic-accounting/isolated-'),
      );
      final output = Directory(
        const String.fromEnvironment(
          'RAINLINK_EVIDENCE_OUTPUT',
          defaultValue: '../docs/verification/traffic-accounting',
        ),
      );
      final platform = Platform.operatingSystem;
      await output.create(recursive: true);
      final temporary = await Directory.systemTemp.createTemp(
        'rainlink-accounting-native-',
      );
      final file = File('${temporary.path}/ledger.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      final gateway = DesktopCoreGateway();
      var repository = DriftTrafficRepository(db);
      final controller = SessionController(
        gateway,
        traffic: repository,
        onMode: (_) {},
      );
      final payload = List.filled(32768, 82);
      var originRequests = 0;
      final hits = <String>[];
      final sockets = <Socket>{};
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final originEvents = origin.listen((request) async {
        originRequests++;
        request.response.add(payload);
        await request.response.close();
      });
      final proxy = await LocalProxyFixture.start('accounting', hits, sockets);
      try {
        final node = ProxyNode(
          id: 'fixture-http',
          name: '隔离 HTTP 节点',
          protocol: NodeProtocol.http,
          server: '127.0.0.1',
          port: proxy.server.port,
        );
        await controller.connect(node, ProxyMode.global);
        expect(
          controller.state.connected,
          isTrue,
          reason: controller.state.error,
        );
        final active = controller.state.active;
        expect(active, isNotNull);
        expect(active?.proxyPort, greaterThan(0));
        // Wait for the global-mode probe to finish its locally rejected attempt
        // before any direct route is enabled.
        for (var attempt = 0; attempt < 100; attempt++) {
          final observation = await gateway.observe();
          if (observation.telemetry?.probeError.isNotEmpty == true) break;
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        expect((await gateway.observe()).telemetry?.probeError, isNotEmpty);
        Future<void> transfer() async {
          final client =
              HttpClient()
                ..connectionTimeout = const Duration(seconds: 4)
                ..findProxy = (_) => 'PROXY 127.0.0.1:${active?.proxyPort}';
          try {
            final request = await client.getUrl(
              Uri.parse('http://127.0.0.1:${origin.port}/payload'),
            );
            request.persistentConnection = false;
            final response = await request.close().timeout(
              const Duration(seconds: 4),
            );
            final bytes = await response
                .fold<List<int>>([], (all, next) => all..addAll(next))
                .timeout(const Duration(seconds: 4));
            expect(bytes, payload);
          } finally {
            client.close(force: true);
          }
        }

        for (final mode in [
          ProxyMode.global,
          ProxyMode.direct,
          ProxyMode.rule,
        ]) {
          await controller.setMode(mode);
          expect(controller.state.active?.sessionId, active?.sessionId);
          for (var i = 0; i < 12; i++) {
            await transfer();
          }
          await controller.refresh();
          expect(controller.state.connected, isTrue);
          expect(controller.state.error, isEmpty);
        }
        final sessionId = active?.sessionId ?? '';
        for (var attempt = 0; attempt < 50; attempt++) {
          if ((await gateway.connections(
            sessionId: sessionId,
          )).entries.isEmpty) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(
          (await gateway.connections(sessionId: sessionId)).entries,
          isEmpty,
        );
        final exact = await gateway.traffic(sessionId: sessionId);
        await controller.refresh();
        var archive = await repository.watchArchive().first;
        var view = archive.forPeriod(TrafficPeriod.today, DateTime.now());
        expect(view.report.upload, exact.upload);
        expect(view.report.download, exact.download);
        expect(view.report.download, greaterThanOrEqualTo(payload.length * 36));
        expect(view.ranking.map((r) => r.target.kind).toSet(), {
          'node',
          'direct',
        });
        expect(
          view.applicationRanking.where((r) => r.target.id != 'unassigned'),
          isNotEmpty,
        );
        for (final dimension in [view.ranking, view.applicationRanking]) {
          expect(
            dimension.fold(0, (sum, r) => sum + r.upload),
            view.report.upload,
          );
          expect(
            dimension.fold(0, (sum, r) => sum + r.download),
            view.report.download,
          );
        }
        await repository.recordAccounting(exact);
        await repository.recordAccounting(exact);
        expect((await repository.watchToday().first).total, view.report.total);
        await controller.disconnect();
        expect(controller.state.error, isEmpty);
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        repository = DriftTrafficRepository(db);
        await repository.recordAccounting(exact);
        archive = await repository.watchArchive().first;
        view = archive.forPeriod(TrafficPeriod.today, DateTime.now());
        expect(view.report.total, exact.total);
        expect(archive.buckets.fold(0, (sum, r) => sum + r.total), exact.total);
        final csv = File('${output.path}/$platform-accounting.csv');
        await csv.writeAsString(trafficCsv(view));
        final exported = await csv.readAsString();
        expect(exported, contains('周期归属'));
        expect(exported, contains('周期应用归属'));
        expect(exported, isNot(contains('127.0.0.1')));
        expect(proxy.failures, isEmpty);
        final proxyRequests =
            hits.where((hit) => hit.endsWith(':${origin.port}')).length;
        expect(proxyRequests, 12);
        expect(originRequests, 36);
        await File('${output.path}/$platform-evidence.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'at': DateTime.now().toIso8601String(),
            'scope':
                'actual $platform core, private IPC, controller, SQLite and CSV; all network fixtures local',
            'payloadBytes': payload.length * 36,
            'originRequests': originRequests,
            'proxyRequests': proxyRequests,
            'upload': exact.upload,
            'download': exact.download,
            'targets': view.ranking.length,
            'applications':
                view.applicationRanking
                    .map(
                      (r) => {
                        'name': r.target.name,
                        'upload': r.upload,
                        'download': r.download,
                      },
                    )
                    .toList(),
            'closedFlowsCounted': true,
            'sameSessionAcrossModes': true,
            'bothPartitionsConserved': true,
            'duplicateSamplesIgnored': true,
            'databaseReopened': true,
            'csvReadBack': true,
            'userDatabaseModified': false,
            'systemProxyRequested': false,
            'tunRequested': false,
          }),
        );
      } on Exception catch (error) {
        final messages = <String>[];
        var logs = await gateway.logs();
        for (var page = 0; page < 125; page++) {
          messages.addAll(logs.entries.map((row) => row.message));
          if (!logs.more) break;
          logs = await gateway.logs(stream: logs.stream, after: logs.cursor);
        }
        await File(
          '${output.path}/$platform-fixture-diagnostic.json',
        ).writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'errorType': error.runtimeType.toString(),
            'requests': hits,
            'originRequests': originRequests,
            'proxyRequests': proxy.accepted,
            'proxyPort': controller.state.active?.proxyPort,
            'coreLogs': messages,
          }),
        );
        rethrow;
      } finally {
        await gateway.disconnect();
        controller.dispose();
        await gateway.close();
        await db.close();
        await proxy.server.close();
        for (final socket in sockets) {
          socket.destroy();
        }
        await origin.close(force: true);
        await originEvents.cancel();
        await temporary.delete(recursive: true);
      }
    },
  );
}
