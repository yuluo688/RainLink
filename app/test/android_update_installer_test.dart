import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/domain/updates/app_update.dart';
import 'package:rainlink/platform/updates/android_update_installer.dart';

AppRelease androidUpdateFixture({
  String? name,
  String? digest =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
}) => AppRelease(
  tag: 'v0.2.0+5',
  version:
      AppVersion.tryParse('0.2.0+5') ?? (throw StateError('fixture version')),
  notes: '测试更新',
  publishedAt: DateTime.utc(2026, 10, 20),
  preview: false,
  page: Uri.https('github.com', '/yuluo688/RainLink/releases/tag/v0.2.0+5'),
  asset: ReleaseAsset(
    name: name ?? 'RainLink-0.2.0+5-android-universal.apk',
    url: Uri.https(
      'github.com',
      '/yuluo688/RainLink/releases/download/v0.2.0+5/RainLink-0.2.0+5-android-universal.apk',
    ),
    bytes: 128,
    sha256: digest,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('rainlink/updates-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall) handler;
  setUp(() {
    calls = [];
    handler =
        (call) async =>
            call.method == 'prepare'
                ? (call.arguments as Map<Object?, Object?>)['id']
                : null;
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  DownloadedUpdate package([AppRelease? release]) => DownloadedUpdate(
    release: release ?? androidUpdateFixture(),
    path:
        'cache/updates/download-fixture/RainLink-0.2.0+5-android-universal.apk',
  );

  test(
    'native preparation receives exact APK identity and commit does not happen automatically',
    () async {
      final prepared = await AndroidUpdateInstaller(
        channel: channel,
      ).prepare(package(), UpdateCancellation());
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['id'], matches(RegExp(r'^[a-f0-9]{32}$')));
      expect(args['versionName'], '0.2.0');
      expect(args['versionCode'], 5);
      expect(args['sha256'], 'a' * 64);
      expect(calls.map((c) => c.method), ['prepare']);
      await prepared.abort();
      await prepared.abort();
      expect(calls.map((c) => c.method), ['prepare', 'abort']);
      await expectLater(prepared.commit(), throwsA(isA<UpdateException>()));
    },
  );

  test(
    'wrong target or missing digest never invokes the native installer',
    () async {
      for (final release in [
        androidUpdateFixture(name: '../update.apk'),
        androidUpdateFixture(digest: null),
        androidUpdateFixture(name: 'RainLink-0.2.0+5-windows-x64.zip'),
      ]) {
        await expectLater(
          AndroidUpdateInstaller(
            channel: channel,
          ).prepare(package(release), UpdateCancellation()),
          throwsA(isA<UpdateException>()),
        );
      }
      expect(calls, isEmpty);
    },
  );

  test(
    'late preparation after cancellation is aborted, never committed',
    () async {
      final gate = Completer<Object?>();
      String? id;
      handler = (call) async {
        if (call.method == 'prepare') {
          id = (call.arguments as Map<Object?, Object?>)['id'] as String;
          return gate.future;
        }
        return null;
      };
      final token = UpdateCancellation();
      final result = AndroidUpdateInstaller(
        channel: channel,
      ).prepare(package(), token);
      await Future<void>.delayed(Duration.zero);
      token.cancel();
      gate.complete(id);
      await expectLater(result, throwsA(isA<UpdateCancelled>()));
      expect(calls.map((c) => c.method), ['prepare', 'cancelPrepare', 'abort']);
    },
  );

  test(
    'timeout tells native ownership to stop before returning a safe error',
    () async {
      final gate = Completer<Object?>();
      handler =
          (call) => call.method == 'prepare' ? gate.future : Future.value();
      final installer = AndroidUpdateInstaller(
        channel: channel,
        prepareTimeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        installer.prepare(package(), UpdateCancellation()),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'timeout',
            contains('超时'),
          ),
        ),
      );
      expect(calls.map((c) => c.method), ['prepare', 'cancelPrepare']);
      gate.complete(null);
      await Future<void>.delayed(Duration.zero);
    },
  );

  test('lost cancel acknowledgement has a bounded, visible failure', () async {
    final prepare = Completer<Object?>();
    final cancel = Completer<Object?>();
    handler =
        (call) => call.method == 'prepare' ? prepare.future : cancel.future;
    final installer = AndroidUpdateInstaller(
      channel: channel,
      prepareTimeout: const Duration(milliseconds: 10),
      controlTimeout: const Duration(milliseconds: 10),
    );
    await expectLater(
      installer.prepare(package(), UpdateCancellation()),
      throwsA(
        isA<UpdateException>().having(
          (e) => e.message,
          'safe timeout',
          contains('安装服务响应超时'),
        ),
      ),
    );
    expect(calls.map((c) => c.method), ['prepare', 'cancelPrepare']);
    prepare.complete(null);
    cancel.complete(null);
    await Future<void>.delayed(Duration.zero);
  });

  test(
    'abort and receipt do not wait forever for an unavailable channel',
    () async {
      final installer = AndroidUpdateInstaller(
        channel: channel,
        controlTimeout: const Duration(milliseconds: 10),
      );
      final prepared = await installer.prepare(package(), UpdateCancellation());
      final pending = <Completer<Object?>>[];
      handler = (_) {
        final gate = Completer<Object?>();
        pending.add(gate);
        return gate.future;
      };
      for (final request in [prepared.abort, installer.readReceipt]) {
        await expectLater(
          request(),
          throwsA(
            isA<UpdateException>().having(
              (e) => e.message,
              'safe timeout',
              contains('安装服务响应超时'),
            ),
          ),
        );
      }
      for (final gate in pending) {
        gate.complete(null);
      }
      await Future<void>.delayed(Duration.zero);
    },
  );

  for (final code in [
    'permission_denied',
    'invalid_package',
    'install_failed',
    'cancelled',
  ]) {
    test('native $code cannot become success or leak native details', () async {
      final prepared = await AndroidUpdateInstaller(
        channel: channel,
      ).prepare(package(), UpdateCancellation());
      handler = (call) async {
        if (call.method == 'commit') {
          throw PlatformException(
            code: code,
            message: 'private native details',
          );
        }
        return null;
      };
      await expectLater(
        prepared.commit(),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'safe',
            isNot(contains('private')),
          ),
        ),
      );
      await prepared.abort();
      expect(calls.last.method, 'abort');
    });
  }

  test(
    'receipts distinguish a replaced version, interrupted install and no install',
    () async {
      final installer = AndroidUpdateInstaller(channel: channel);
      for (final (status, expected) in [
        (null, null),
        ('installed', '上次更新已安装，当前运行新版本'),
        ('interrupted', '上次安装未完成，原版本仍可使用，请重新检查更新'),
      ]) {
        handler = (_) async => status;
        expect(await installer.readReceipt(), expected);
      }
      handler = (_) async => 'private unknown status';
      await expectLater(
        installer.readReceipt(),
        throwsA(isA<UpdateException>()),
      );
    },
  );
}
