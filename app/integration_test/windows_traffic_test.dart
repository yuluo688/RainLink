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
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/traffic/drift_traffic_repository.dart';
import 'package:rainlink/domain/connection/traffic_repository.dart';
import 'package:rainlink/domain/core/session_gateway.dart';
import 'package:rainlink/domain/export/data_export.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/platform/export/file_data_export_service.dart';
import 'package:rainlink/platform/window/desktop_window.dart';

class _FileExport implements DataExportService {
  const _FileExport(this.file);
  final File file;
  @override
  Future<String?> save(
      {required String suggestedName, required String content}) async {
    await file.writeAsString(content, flush: true);
    return file.path;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'actual core traffic persists off overview and exports exact period',
      (tester) async {
    final directory =
        await Directory.systemTemp.createTemp('rainlink-traffic-native-');
    final dbFile = File('${directory.path}/traffic.sqlite');
    final db = AppDatabase(NativeDatabase(dbFile));
    final output = Directory('../docs/verification/traffic');
    await output.create(recursive: true);
    final csv = File('${output.path}/windows-traffic.csv');
    final payload = 'R' * 131072;
    var originRequests = 0;
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final originEvents = origin.listen((request) async {
      originRequests++;
      request.response.write(payload);
      await request.response.close();
    });
    final router = createRouter(initialLocation: '/overview');
    ProviderContainer? container;
    var released = false;
    Future<void> releaseApp() async {
      if (released) return;
      released = true;
      try {
        final current = container;
        if (current != null) {
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
        container = null;
      }
    }

    try {
      await initializeDesktopWindow();
      await tester.pumpWidget(ProviderScope(overrides: [
        ...createAppOverrides(database: db, initialTheme: AppTheme.dark),
        dataExportServiceProvider.overrideWithValue(_FileExport(csv)),
      ], child: RainlinkApp(router: router)));
      await tester.pumpAndSettle();
      final activeContainer =
          ProviderScope.containerOf(tester.element(find.byType(RainlinkApp)));
      container = activeContainer;
      final nodes = activeContainer.read(nodeRepositoryProvider);
      final node = await nodes.save(const NodeDraft(
          name: '本机流量验收',
          protocol: NodeProtocol.http,
          server: '127.0.0.1',
          port: 9));
      await nodes.select(node.id);
      await tester.pumpAndSettle();
      await tester.tap(find.text('直连'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('connect-button')));
      Future<void> waitFor(bool Function() condition) async {
        for (var i = 0; i < 200 && !condition(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(condition(), isTrue);
      }

      await waitFor(
          () => activeContainer.read(sessionControllerProvider).connected);
      final session = activeContainer.read(sessionControllerProvider.notifier);
      final initial = activeContainer.read(sessionControllerProvider).active;
      expect(initial, isNotNull);
      Future<void> transfer() async {
        final active = activeContainer.read(sessionControllerProvider).active;
        expect(active?.sessionId, initial?.sessionId);
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 3);
        client.findProxy = (_) => 'PROXY 127.0.0.1:${active?.proxyPort}';
        try {
          final request = await client
              .getUrl(Uri.parse('http://127.0.0.1:${origin.port}/payload'));
          final response =
              await request.close().timeout(const Duration(seconds: 4));
          expect(await utf8.decoder.bind(response).join(), payload);
        } finally {
          client.close(force: true);
        }
      }

      await transfer();
      router.go('/nodes');
      await tester.pumpAndSettle();
      await transfer();
      router.go('/traffic');
      await tester.pumpAndSettle();
      await waitFor(() =>
          (activeContainer
                  .read(trafficArchiveProvider(TrafficPeriod.today))
                  .valueOrNull
                  ?.forPeriod(TrafficPeriod.today, DateTime.now())
                  .report
                  .download ??
              0) >=
          payload.length * 2);
      final snapshot = activeContainer
          .read(trafficArchiveProvider(TrafficPeriod.today))
          .requireValue
          .forPeriod(TrafficPeriod.today, DateTime.now());
      expect(snapshot.buckets.fold(0, (sum, b) => sum + b.download),
          snapshot.report.download);
      expect(snapshot.ranking.single.target.kind, 'direct');
      expect(snapshot.ranking.single.total, snapshot.report.total);
      await tester.tap(find.byKey(const ValueKey('export-traffic')));
      await tester.pumpAndSettle();
      final exported = await csv.readAsString();
      expect(exported, contains('日汇总'));
      expect(exported, contains('时段明细'));
      expect(exported, contains('直连'));
      expect(
          exported,
          contains(
              '"${snapshot.report.upload}","${snapshot.report.download}","${snapshot.report.total}"'));
      expect(exported, isNot(contains('127.0.0.1')));
      await session.disconnect();
      final saved = await DriftTrafficRepository(db).watchArchive().first;
      await releaseApp();
      final reopened = AppDatabase(NativeDatabase(dbFile));
      try {
        final history =
            await DriftTrafficRepository(reopened).watchArchive().first;
        expect(history.days.single.total, saved.days.single.total);
        expect(history.buckets.single.total, saved.buckets.single.total);
      } finally {
        await reopened.close();
      }
      await File('${output.path}/windows-evidence.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert({
        'at': DateTime.now().toIso8601String(),
        'scenario': 'local origin through actual core in direct mode',
        'payloadBytes': payload.length * 2,
        'originRequests': originRequests,
        'downloadRecorded': snapshot.report.download,
        'uploadRecorded': snapshot.report.upload,
        'sampledAwayFromOverview': true,
        'sameActiveSession': true,
        'dailyBucketAndRankingConserved': true,
        'databaseReopened': true,
        'csvWrittenAndReadBack': true,
        'csvPicker': 'shared service replaced with fixed test output',
        'userDatabaseModified': false,
        'systemProxyRequested': false,
      }));
      expect(tester.takeException(), isNull);
    } finally {
      await releaseApp();
      await origin.close(force: true);
      await originEvents.cancel();
      await directory.delete(recursive: true);
    }
  });
}
