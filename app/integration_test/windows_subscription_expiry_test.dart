import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rainlink/app/dependencies.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/app/router.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/groups/subscription_expiry_monitor.dart';
import 'package:rainlink/application/preferences/desktop_integration_controller.dart';
import 'package:rainlink/application/preferences/device_settings_controller.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/groups/drift_group_repository.dart';
import 'package:rainlink/data/groups/drift_subscription_expiry_store.dart';
import 'package:rainlink/data/preferences/drift_preferences_repository.dart';
import 'package:rainlink/design_system/widgets/rainlink_switch.dart';
import 'package:rainlink/domain/core/session_gateway.dart';
import 'package:rainlink/domain/groups/subscription_expiry.dart';
import 'package:rainlink/domain/platform/desktop_integration.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/platform/window/desktop_session_guard.dart';
import 'package:rainlink/platform/window/desktop_window.dart';
import 'package:rainlink/platform/window/windows_desktop_integration.dart';
import 'package:window_manager/window_manager.dart';

import '../test/support/subscription_fixtures.dart';

/// Counts real submissions; every call still goes through Windows/Shell.
class _ObservedWindows extends WindowsDesktopIntegration {
  final accepted = <({int expiringSoon, int expired})>[];
  @override
  Future<void> notifySubscriptionExpiry(
      {required int expiringSoon, required int expired}) async {
    await super
        .notifySubscriptionExpiry(expiringSoon: expiringSoon, expired: expired);
    accepted.add((expiringSoon: expiringSoon, expired: expired));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native expiry receipts, UI retry, callback routing and reopen',
      (tester) async {
    final directory = await Directory.systemTemp.createTemp('rainlink-expiry-');
    final file = File('${directory.path}/settings.sqlite');
    final database = AppDatabase(NativeDatabase(file));
    final router = createRouter(initialLocation: '/settings');
    final now = DateTime.now().toUtc();
    for (final (id, remaining) in [
      ('soon', const Duration(days: 2)),
      ('expired', const Duration(days: -1)),
      ('unknown', null),
    ]) {
      await database.into(database.nodeGroups).insert(
          NodeGroupsCompanion.insert(
              id: id,
              name: '本地验收-$id',
              kind: 'subscription',
              autoUpdate: const Value(false),
              expiresAt: Value(remaining == null ? null : now.add(remaining))));
    }
    ProviderContainer? container;
    var released = false;
    Future<void> release() async {
      if (released) return;
      released = true;
      try {
        if (container case final current?) {
          await current.read(subscriptionExpiryMonitorProvider)?.close();
          await current.read(desktopIntegrationProvider)?.close();
          final gateway = current.read(coreGatewayProvider);
          if (gateway is SessionGateway) await gateway.close();
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        router.dispose();
        await database.close();
      }
    }

    Future<void> waitFor(bool Function() ready) async {
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(ready(), isTrue);
    }

    try {
      await initializeDesktopWindow();
      await tester.pumpWidget(ProviderScope(
          overrides: createAppOverrides(
              database: database, initialTheme: AppTheme.dark),
          child: DesktopSessionGuard(child: RainlinkApp(router: router))));
      await tester.pumpAndSettle();
      final current =
          ProviderScope.containerOf(tester.element(find.byType(RainlinkApp)));
      container = current;
      final desktop = current.read(desktopIntegrationProvider);
      final monitor = current.read(subscriptionExpiryMonitorProvider);
      expect(desktop, isA<WindowsDesktopIntegration>());
      if (desktop == null || monitor == null) {
        throw StateError('Native desktop expiry adapters are unavailable');
      }
      final store = DriftSubscriptionExpiryStore(database);
      await monitor.checkNow();
      expect(await store.load(), isEmpty);
      expect(
          current
              .read(deviceSettingsControllerProvider)
              .general
              .subscriptionExpiryNotifications,
          isFalse);
      final registered = await Process.run('python', [
        '../tools/verify_desktop_window.py',
        '--pid',
        '$pid',
        '--assert-tray'
      ]);
      expect(registered.exitCode, 0, reason: '${registered.stderr}');

      const channel = MethodChannel('dev.rainlink/desktop');
      for (final counts in <Map<String, Object?>>[
        {'expiringSoon': -1, 'expired': 1},
        {'expiringSoon': 0, 'expired': 0},
        {'expiringSoon': 0x80000000, 'expired': 0},
        {'expiringSoon': '1', 'expired': 0},
      ]) {
        await expectLater(
            channel.invokeMethod<void>('notifySubscriptionExpiry', counts),
            throwsA(isA<PlatformException>().having(
                (e) => e.code, 'native validation', 'invalid_arguments')));
      }

      // Force a real native refusal without changing the user's system proxy.
      await desktop.setTrayVisible(false);
      await expectLater(
          desktop.notifySubscriptionExpiry(expiringSoon: 1, expired: 0),
          throwsException);
      final toggle = find.descendant(
          of: find.byKey(const ValueKey('subscription-expiry-notifications')),
          matching: find.byType(RainlinkSwitch));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await waitFor(
          () => current.read(subscriptionExpiryErrorProvider) != null);
      expect(current.read(subscriptionExpiryErrorProvider), contains('托盘'));
      expect(await store.load(), isEmpty);

      await desktop.setTrayVisible(true);
      await database.customStatement(
          "CREATE TRIGGER reject_expiry BEFORE INSERT ON preferences WHEN NEW.key = 'notifications.subscription_expiry' BEGIN SELECT RAISE(ABORT, 'fixture disk full'); END;");
      Future<void> retry() async {
        final button = find.byKey(const ValueKey('retry-subscription-expiry'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await monitor.checkNow();
        await tester.pumpAndSettle();
      }

      await retry();
      expect(current.read(subscriptionExpiryErrorProvider), contains('记录未保存'));
      expect(await store.load(), isEmpty);
      await retry();
      expect(current.read(subscriptionExpiryErrorProvider), contains('记录未保存'));
      await database.customStatement('DROP TRIGGER reject_expiry');
      await retry();
      expect(current.read(subscriptionExpiryErrorProvider), isNull);
      final receipts = await store.load();
      expect(receipts.keys.toSet(), {'soon', 'expired'});
      expect(receipts['soon']?.stage, SubscriptionExpiryStage.soon);
      expect(receipts['expired']?.stage, SubscriptionExpiryStage.expired);
      expect(
          (await DriftPreferencesRepository(database).loadDeviceSettings())
              .general
              .subscriptionExpiryNotifications,
          isTrue);

      // Send the actual native callback to this test PID. This is explicitly
      // not evidence that Windows displayed a banner or a person clicked it.
      final actions = <DesktopAction>[];
      final events = desktop.actions.listen(actions.add);
      try {
        await desktop.hideWindow();
        expect(await windowManager.isVisible(), isFalse);
        final activated = await Process.run('python', [
          '../tools/verify_desktop_window.py',
          '--pid',
          '$pid',
          '--activate-notification'
        ]);
        expect(activated.exitCode, 0, reason: '${activated.stderr}');
        await waitFor(
            () => router.routeInformationProvider.value.uri.path == '/groups');
        await tester.pumpAndSettle();
        expect(actions, contains(DesktopAction.showGroups));
        expect(await windowManager.isVisible(), isTrue);
        expect(find.text('添加订阅'), findsOneWidget);
      } finally {
        await events.cancel();
      }
      expect(tester.takeException(), isNull);
      await release();

      // New SQLite connection and monitor: receipts must suppress submissions.
      final reopened = AppDatabase(NativeDatabase(file));
      final native = _ObservedWindows();
      String? failure;
      final fetcher = TestSubscriptionFetcher();
      final next = SubscriptionExpiryMonitor(
          groups: DriftGroupRepository(reopened, TestSecretStore(), fetcher),
          store: DriftSubscriptionExpiryStore(reopened),
          notifications: native,
          enabled: () => true,
          onError: (message) => failure = message);
      try {
        final saved =
            await DriftPreferencesRepository(reopened).loadDeviceSettings();
        expect(saved.general.subscriptionExpiryNotifications, isTrue);
        await native.setTrayVisible(true);
        next.resume();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await next.checkNow();
        expect(failure, isNull);
        expect(native.accepted, isEmpty);
        expect((await DriftSubscriptionExpiryStore(reopened).load()).length, 2);
        // A renewed, different term becomes independently eligible.
        await (reopened.update(reopened.nodeGroups)
              ..where((g) => g.id.equals('soon')))
            .write(NodeGroupsCompanion(
                expiresAt: Value(now.subtract(const Duration(hours: 1)))));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await next.checkNow();
        expect(native.accepted, [(expiringSoon: 0, expired: 1)]);
        await next.checkNow();
        expect(native.accepted.length, 1);
        expect(fetcher.calls, 0);
      } finally {
        await next.close();
        await native.close();
        await reopened.close();
      }

      final output = File(
          '../docs/verification/subscription-expiry/windows-evidence.json');
      await output.parent.create(recursive: true);
      await output.writeAsString('${const JsonEncoder.withIndent('  ').convert({
            'at': DateTime.now().toIso8601String(),
            'nativeWindows': true,
            'temporaryDatabase': true,
            'defaultDisabledWithoutReceipts': true,
            'nativeInvalidCountsRejected': true,
            'nativeHiddenTrayRejected': true,
            'actualSqliteFailureShownInUI': true,
            'receiptRetrySaved': true,
            'initialReceiptCount': receipts.length,
            'nativeNotificationAccepted': true,
            'notificationDisplayVerified': false,
            'nativeCallbackSimulatedForTestPid': true,
            'callbackOpenedGroupsAndRestoredWindow': true,
            'fileReopenSuppressedDuplicateSubmissions': true,
            'renewedTermAcceptedOnceByShell': true,
            'subscriptionFetches': 0,
            'systemProxyEnabled': false,
            'tunEnabled': false,
          })}\n');
    } finally {
      await release();
      await directory.delete(recursive: true);
    }
  });
}
