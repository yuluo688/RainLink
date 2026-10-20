import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rainlink/app/dependencies.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/app/router.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/application/preferences/theme_controller.dart';
import 'package:rainlink/application/telemetry/core_log_collector.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/traffic/drift_traffic_repository.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/connection/traffic_history.dart';
import 'package:rainlink/domain/connection/traffic_repository.dart';
import 'package:rainlink/domain/core/core_telemetry.dart';
import 'package:rainlink/domain/core/core_traffic.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/platform/export/file_data_export_service.dart';

/// The host verifier runs a shell-UID client through the real system tunnel.
/// File handshakes live only in this test entrypoint, never the product bridge.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android closed flows persist as conserved traffic partitions',
    (tester) async {
      expect(Platform.isAndroid, isTrue);
      const run = String.fromEnvironment('RAINLINK_TRAFFIC_QA_RUN');
      const proxyPort = int.fromEnvironment('RAINLINK_TRAFFIC_QA_PROXY_PORT');
      expect(RegExp(r'^[a-f0-9]{16}$').hasMatch(run), isTrue);
      expect(proxyPort, inInclusiveRange(1, 65535));
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (binding.platformDispatcher.implicitView?.physicalSize.isEmpty !=
            false) {
          if (DateTime.now().isAfter(deadline)) {
            throw StateError('Android surface did not become ready');
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
      final cache = await getTemporaryDirectory();
      final work = Directory('${cache.path}/traffic-accounting-qa/$run');
      await work.create(recursive: true);
      final file = File('${work.path}/ledger.sqlite');
      var database = AppDatabase(NativeDatabase(file));
      final router = createRouter(initialLocation: '/traffic');
      final boundary = GlobalKey();
      ProviderContainer? scope;
      final captures = <Map<String, Object?>>[];
      var reopened = false;

      Future<ProviderContainer> mount(AppTheme theme) async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: ProviderScope(
              overrides: [
                ...createAppOverrides(database: database, initialTheme: theme),
                // SAF is covered by the native document tests. Here the page
                // must produce and write its own actual CSV, read back below.
                dataExportServiceProvider.overrideWithValue(
                  const FileDataExportService(),
                ),
              ],
              child: RainlinkApp(router: router),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(RainlinkApp)),
        );
        scope = container;
        await container.read(sessionControllerProvider.notifier).initialized;
        return container;
      }

      Future<void> handshake(String stage, String acknowledgement) async {
        final pending = File('${work.path}/state.next');
        await pending.writeAsString(
          jsonEncode({'run': run, 'stage': stage}),
          flush: true,
        );
        await pending.rename('${work.path}/state.json');
        final done = File('${work.path}/$stage.done');
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (!await done.exists()) {
          if (DateTime.now().isAfter(deadline)) {
            throw StateError('The external $stage step did not finish');
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(await done.readAsString(), acknowledgement);
      }

      try {
        final container = await mount(AppTheme.dark);
        final controller = container.read(sessionControllerProvider.notifier);
        final gateway = container.read(coreGatewayProvider);
        expect(gateway, isA<CoreTrafficGateway>());
        expect(gateway, isA<CoreTelemetryGateway>());
        final node = await container
            .read(nodeRepositoryProvider)
            .save(
              const NodeDraft(
                name: 'Android 流量验收',
                protocol: NodeProtocol.http,
                server: '10.0.2.2',
                port: proxyPort,
                authenticate: true,
                username: 'fixture-user',
                password: 'fixture-password',
              ),
            );
        await controller.connect(node, ProxyMode.global);
        expect(
          controller.state.connected,
          isTrue,
          reason: controller.state.error,
        );
        expect(controller.state.tun, isTrue);
        final sessionId =
            controller.state.active?.sessionId ??
            (throw StateError('Missing actual Android session'));
        for (final mode in [
          ProxyMode.global,
          ProxyMode.direct,
          ProxyMode.rule,
        ]) {
          await controller.setMode(mode);
          expect(controller.state.error, isEmpty);
          expect(controller.state.active?.sessionId, sessionId);
          await handshake(mode.name, '12');
          await controller.refresh();
          expect(controller.state.error, isEmpty);
        }
        final telemetry = gateway as CoreTelemetryGateway;
        for (var attempt = 0; attempt < 50; attempt++) {
          final entries =
              (await telemetry.connections(sessionId: sessionId)).entries;
          if (!entries.any(
            (entry) =>
                entry.destination.startsWith('198.51.100.42:') ||
                entry.destination.startsWith('10.0.2.2:'),
          )) {
            break;
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        final closed =
            (await telemetry.connections(sessionId: sessionId)).entries;
        expect(
          closed.where(
            (entry) =>
                entry.destination.startsWith('198.51.100.42:') ||
                entry.destination.startsWith('10.0.2.2:'),
          ),
          isEmpty,
        );
        final exact = await (gateway as CoreTrafficGateway).traffic(
          sessionId: sessionId,
        );
        exact.validate();
        // All 36 responses have already completed; active connections alone
        // cannot account for these payloads or reproduce the application row.
        expect(exact.download, greaterThanOrEqualTo(32768 * 36));
        expect(
          exact.targets.map((row) => row.target.kind).toSet(),
          containsAll({'node', 'direct'}),
        );
        expect(
          exact.applications.any(
            (row) =>
                row.target.name == 'com.android.shell' &&
                row.download >= 32768 * 36,
          ),
          isTrue,
        );
        await controller.disconnect();
        expect(controller.state.error, isEmpty);
        final repository = container.read(trafficRepositoryProvider);
        if (repository is! DriftTrafficRepository) {
          throw StateError('The real SQLite traffic repository is required');
        }
        final ledger = repository;
        final saved = (await ledger.watchArchive().first).forPeriod(
          TrafficPeriod.today,
          DateTime.now(),
        );
        expect(saved.report.download, greaterThanOrEqualTo(exact.download));
        final savedTotal = saved.report.total;
        _expectPartitions(
          saved.report,
          saved.ranking,
          saved.applicationRanking,
        );
        await ledger.recordAccounting(exact);
        await ledger.recordAccounting(exact);
        expect((await ledger.watchToday().first).total, savedTotal);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.textContaining('com.android.shell').first,
        );
        captures.add(await _capture(boundary, 'applications-dark.png'));
        await tester.tap(find.text('出站'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Android 流量验收'), findsOneWidget);
        expect(find.textContaining('直连'), findsOneWidget);
        captures.add(await _capture(boundary, 'outbounds-dark.png'));
        await container
            .read(themeControllerProvider.notifier)
            .setTheme(AppTheme.light);
        await tester.pumpAndSettle();
        captures.add(await _capture(boundary, 'outbounds-light.png'));
        await tester.tap(find.text('应用'));
        await tester.pumpAndSettle();
        captures.add(await _capture(boundary, 'applications-light.png'));
        await tester.ensureVisible(
          find.byKey(const ValueKey('export-traffic-mobile')),
        );
        await tester.tap(find.byKey(const ValueKey('export-traffic-mobile')));
        await tester.pumpAndSettle();
        expect(find.text('已导出当前周期流量'), findsOneWidget);
        final documents = await getApplicationDocumentsDirectory();
        final day = DateTime.now().toIso8601String().substring(0, 10);
        final csv =
            await File(
              '${documents.path}/exports/RainLink-流量-$day-$day.csv',
            ).readAsString();
        expect(csv, contains('周期归属'));
        expect(csv, contains('周期应用归属'));
        expect(csv, contains('com.android.shell'));
        expect(csv, isNot(contains('fixture-password')));
        expect(csv, isNot(contains('10.0.2.2')));
        expect(csv, isNot(contains('198.51.100.42')));
        await File('${work.path}/verified.csv').writeAsString(csv, flush: true);
        await container.read(coreLogCollectorProvider.notifier).suspend();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        scope = null;
        await database.close();
        database = AppDatabase(NativeDatabase(file));
        final restored = DriftTrafficRepository(database);
        final archive = await restored.watchArchive().first;
        final view = archive.forPeriod(TrafficPeriod.today, DateTime.now());
        expect(view.report.total, savedTotal);
        expect(
          archive.buckets.fold(0, (sum, row) => sum + row.total),
          savedTotal,
        );
        _expectPartitions(view.report, view.ranking, view.applicationRanking);
        await restored.recordAccounting(exact);
        expect((await restored.watchToday().first).total, savedTotal);
        await mount(AppTheme.light);
        await tester.ensureVisible(
          find.byKey(const ValueKey('traffic-ranking-dimension')),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('com.android.shell'), findsOneWidget);
        captures.add(
          await _capture(boundary, 'reopened-applications-light.png'),
        );
        reopened = true;
        expect(tester.takeException(), isNull);
        binding.reportData = {
          'accounting': {
            'run': run,
            'scope':
                'Android actual system tunnel, shell-UID client, embedded '
                'core, SQLite, traffic UI and app-private CSV; isolated AVD only',
            'systemTunnelEstablished': true,
            'sameSessionAcrossModes': true,
            'completedPayloadBytes': 32768 * 36,
            'upload': view.report.upload,
            'download': view.report.download,
            'actualClosedFlowsIncluded': true,
            'bothPartitionsConserved': true,
            'shellApplicationIdentified': true,
            'duplicateSamplesIgnored': true,
            'databaseReopened': reopened,
            'uiCsvReadBack': true,
            'userDatabaseModified': false,
            'applications': [
              for (final row in view.applicationRanking)
                {
                  'name': row.target.name,
                  'upload': row.upload,
                  'download': row.download,
                },
            ],
            'targets': [
              for (final row in view.ranking)
                {
                  'name': row.target.name,
                  'kind': row.target.kind,
                  'upload': row.upload,
                  'download': row.download,
                },
            ],
          },
          'captures': captures,
        };
      } finally {
        if (scope case final container?) {
          await container.read(coreLogCollectorProvider.notifier).suspend();
          await container.read(coreGatewayProvider).disconnect();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        router.dispose();
        await database.close();
        if (reopened) {
          // flutter drive may remove its test application on exit. Copy the
          // closed database and CSV before telling the driver to finish.
          await handshake('finished', 'collected');
        } else {
          await File('${work.path}/state.json').writeAsString(
            jsonEncode({'run': run, 'stage': 'failed'}),
            flush: true,
          );
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

void _expectPartitions(
  DailyTraffic total,
  List<TrafficUsage> targets,
  List<TrafficUsage> applications,
) {
  for (final rows in [targets, applications]) {
    expect(rows.fold(0, (sum, row) => sum + row.upload), total.upload);
    expect(rows.fold(0, (sum, row) => sum + row.download), total.download);
  }
}

Future<Map<String, Object?>> _capture(GlobalKey key, String filename) async {
  final boundary = key.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) {
    throw StateError('Missing Android accounting capture boundary');
  }
  final rendered = await boundary.toImage(pixelRatio: 1);
  try {
    final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw StateError('Screenshot encoding failed');
    return {
      'file': filename,
      'width': rendered.width,
      'height': rendered.height,
      'png': base64Encode(png.buffer.asUint8List()),
    };
  } finally {
    rendered.dispose();
  }
}
