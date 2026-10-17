import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/updates/drift_update_preferences.dart';
import 'package:rainlink/data/updates/github_release_source.dart';
import 'package:rainlink/domain/updates/app_update.dart';
import 'package:rainlink/platform/updates/file_update_downloader.dart';

void main() {
  test('release versions compare semantic stages and numeric build numbers',
      () {
    final ordered = [
      '0.1.0-alpha',
      '0.1.0-alpha.2',
      '0.1.0-alpha.10',
      '0.1.0-beta',
      '0.1.0-rc.1',
      '0.1.0',
      '0.1.0+1',
      '0.1.0+2',
      '0.1.1',
      '0.2.0',
      '1.0.0'
    ];
    for (var i = 1; i < ordered.length; i++) {
      final before = AppVersion.tryParse(ordered[i - 1]);
      final next = AppVersion.tryParse('v${ordered[i]}');
      expect(before, isNotNull);
      expect(next, isNotNull);
      expect(before?.compareTo(next ?? before), lessThan(0),
          reason: ordered[i]);
    }
    for (final invalid in [
      '01.2.3',
      '1.2',
      '1.2.3+foo',
      '1.2.3-01',
      '1.2.3+01',
      '2147483648.0.0',
      '1.2.3\n',
      '../1.2.3',
      'v1.2.3/other'
    ]) {
      expect(AppVersion.tryParse(invalid), isNull, reason: invalid);
    }
    expect(AppVersion.tryParse('1.0.0-beta.123456789012345678901234567890'),
        isNotNull);
  });

  test('production update policy only trusts the repository and release CDN',
      () {
    final origin = ReleaseOrigin();
    expect(
        origin.permitsAsset(
            Uri.parse(
                'https://github.com/yuluo688/RainLink/releases/download/v1.0.0/RainLink-1.0.0-windows-x64.zip'),
            'v1.0.0',
            'RainLink-1.0.0-windows-x64.zip'),
        isTrue);
    for (final url in [
      'http://release-assets.githubusercontent.com/a',
      'https://github.com/attacker/RainLink/releases/download/v1.0.0/a.zip',
      'https://release-assets.githubusercontent.com.evil.test/a',
      'https://user@release-assets.githubusercontent.com/a',
      'https://release-assets.githubusercontent.com:444/a'
    ]) {
      expect(origin.permitsRedirect(Uri.parse(url)), isFalse);
    }
    expect(
        origin.permitsRedirect(Uri.parse(
            'https://release-assets.githubusercontent.com/a?signature=fixture')),
        isTrue);
    expect(() => ReleaseOrigin.loopback(Uri.parse('http://example.test')),
        throwsArgumentError);
  });

  group('actual HTTP release metadata and file downloads', () {
    late HttpServer server;
    late ReleaseOrigin origin;
    late Directory temporary;
    late Future<void> Function(HttpRequest) handler;
    late StreamSubscription<HttpRequest> requests;
    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      origin =
          ReleaseOrigin.loopback(Uri.parse('http://127.0.0.1:${server.port}'));
      temporary =
          await Directory.systemTemp.createTemp('rainlink-update-http-');
      requests = server.listen((request) async {
        try {
          await handler(request);
        } on HttpException {/* Client cancelled. */} on SocketException {
          /* Client cancelled. */
        }
      });
    });
    tearDown(() async {
      await requests.cancel();
      await server.close(force: true);
      await temporary.delete(recursive: true);
    });
    Map<String, Object?> release(String tag,
        {bool preview = false,
        bool draft = false,
        int bytes = 5,
        String? digest =
            'sha256:0000000000000000000000000000000000000000000000000000000000000000'}) {
      final version = tag.startsWith('v') ? tag.substring(1) : tag;
      final name = 'RainLink-$version-windows-x64.zip';
      return {
        'tag_name': tag,
        'draft': draft,
        'prerelease': preview,
        'published_at': '2026-10-17T00:00:00Z',
        'body': '更新说明',
        'html_url': origin.page(tag).toString(),
        'assets': [
          {
            'name': name,
            'size': bytes,
            'digest': digest,
            'browser_download_url': origin.asset(tag, name).toString()
          }
        ]
      };
    }

    GithubReleaseSource source({Duration? timeout}) => GithubReleaseSource(
        origin: origin, timeout: timeout ?? const Duration(seconds: 2));
    FileUpdateDownloader downloader({Duration? timeout}) =>
        FileUpdateDownloader(
            origin: origin,
            cacheDirectory: () async => temporary,
            timeout: timeout ?? const Duration(seconds: 3));
    Future<AppRelease> getRelease(Map<String, Object?> value) async {
      handler = (request) async {
        expect(request.headers.value(HttpHeaders.userAgentHeader),
            'RainLink-update-check');
        request.response.write(jsonEncode([value]));
        await request.response.close();
      };
      final found = await source()
          .latest(includePreview: true, cancellation: UpdateCancellation());
      if (found == null) throw StateError('Missing fixture release');
      return found;
    }

    test(
        'selects numeric versions, filters drafts and explicitly permits previews',
        () async {
      handler = (request) async {
        expect(request.uri.queryParameters['per_page'], '100');
        request.response.write(jsonEncode([
          release('v0.2.0-beta.2', preview: true),
          release('v0.1.0+2'),
          release('v9.0.0', draft: true),
          release('v0.1.0+10')
        ]));
        await request.response.close();
      };
      expect(
          (await source().latest(
                  includePreview: false, cancellation: UpdateCancellation()))
              ?.tag,
          'v0.1.0+10');
      expect(
          (await source().latest(
                  includePreview: true, cancellation: UpdateCancellation()))
              ?.tag,
          'v0.2.0-beta.2');
      handler = (request) async {
        request.response.write('[]');
        await request.response.close();
      };
      expect(
          await source().latest(
              includePreview: false, cancellation: UpdateCancellation()),
          isNull);
    });

    test('rejects malformed metadata and never exposes response body details',
        () async {
      for (final value in [
        'fixture-private-error',
        {'token': 'private'},
        [
          {...release('v1.0.0'), 'html_url': 'https://evil.test/private'}
        ],
        [
          {...release('v1.0.0'), 'prerelease': 'true'}
        ],
        [
          {
            ...release('v1.0.0'),
            'assets': [
              {
                'name': 'RainLink-1.0.0-windows-x64.zip',
                'size': 5,
                'digest': 'sha256:private',
                'browser_download_url': 'https://evil.test/private'
              }
            ]
          }
        ]
      ]) {
        handler = (request) async {
          request.response.write(jsonEncode(value));
          await request.response.close();
        };
        await expectLater(
            source().latest(
                includePreview: false, cancellation: UpdateCancellation()),
            throwsA(isA<UpdateException>().having(
                (e) => e.message, 'redacted', isNot(contains('private')))));
      }
      handler = (request) async {
        request.response.statusCode = 429;
        request.response.write('private');
        await request.response.close();
      };
      await expectLater(
          source()
              .latest(includePreview: true, cancellation: UpdateCancellation()),
          throwsA(isA<UpdateException>()
              .having((e) => e.message, 'rate limit', contains('限制'))));
    });

    test(
        'metadata cancellation closes an in-flight request and timeout is bounded',
        () async {
      final waiting = Completer<void>();
      handler = (request) async {
        if (!waiting.isCompleted) waiting.complete();
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await request.response.close();
      };
      final cancellation = UpdateCancellation();
      final pending =
          source().latest(includePreview: false, cancellation: cancellation);
      final expectation = expectLater(pending, throwsA(isA<UpdateCancelled>()));
      await waiting.future;
      cancellation.cancel();
      await expectation;
      await expectLater(
          source(timeout: const Duration(milliseconds: 30)).latest(
              includePreview: false, cancellation: UpdateCancellation()),
          throwsA(isA<UpdateException>()
              .having((e) => e.message, 'timeout', contains('超时'))));
    });

    test(
        'downloads actual bytes and returns a file only after SHA256 verification',
        () async {
      final bytes = List<int>.generate(128 * 1024, (i) => i % 251);
      final found = await getRelease(release('v0.2.0+1',
          bytes: bytes.length, digest: 'sha256:${sha256.convert(bytes)}'));
      handler = (request) async {
        request.response.add(bytes);
        await request.response.close();
      };
      var transferred = 0;
      final downloaded = await downloader()
          .download(found, UpdateCancellation(), onProgress: (got, total) {
        expect(total, bytes.length);
        expect(got, greaterThanOrEqualTo(transferred));
        transferred = got;
      });
      expect(await File(downloaded.path).readAsBytes(), bytes);
      expect(transferred, bytes.length);
      expect(
          temporary
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.partial')),
          isEmpty);
      await downloader().discard(downloaded);
      expect(await File(downloaded.path).exists(), isFalse);
      final outside = File('${temporary.path}/outside.zip');
      await outside.writeAsString('preserve');
      await expectLater(
          downloader()
              .discard(DownloadedUpdate(release: found, path: outside.path)),
          throwsA(isA<UpdateException>()));
      expect(await outside.readAsString(), 'preserve');
      await outside.delete();
    });

    test('mismatched digest, oversized and truncated files are discarded',
        () async {
      for (final mode in ['hash', 'large', 'short']) {
        final found = await getRelease(release('v0.2.0', bytes: 5));
        handler = (request) async {
          request.response.add(utf8.encode(mode == 'large'
              ? '123456'
              : mode == 'short'
                  ? '1234'
                  : '12345'));
          await request.response.close();
        };
        await expectLater(
            downloader()
                .download(found, UpdateCancellation(), onProgress: (_, __) {}),
            throwsA(isA<UpdateException>()));
        expect(temporary.listSync(recursive: true).whereType<File>(), isEmpty);
      }
    });

    test('missing digest disables download and untrusted redirects are refused',
        () async {
      final noDigest = await getRelease(release('v0.2.0', digest: null));
      var fetched = false;
      handler = (request) async {
        fetched = true;
        await request.response.close();
      };
      await expectLater(
          downloader()
              .download(noDigest, UpdateCancellation(), onProgress: (_, __) {}),
          throwsA(isA<UpdateException>()));
      expect(fetched, isFalse);
      final found = await getRelease(release('v0.2.0'));
      handler = (request) async {
        request.response.statusCode = 302;
        request.response.headers
            .set('location', 'https://evil.test/private-token');
        await request.response.close();
      };
      await expectLater(
          downloader()
              .download(found, UpdateCancellation(), onProgress: (_, __) {}),
          throwsA(isA<UpdateException>().having(
              (e) => e.message, 'safe redirect error', contains('不受信任'))));
      expect(temporary.listSync(recursive: true).whereType<File>(), isEmpty);
    });

    test(
        'cancel and timeout wait for file handles before cleaning temporary downloads',
        () async {
      for (final mode in ['cancel', 'timeout']) {
        final found = await getRelease(release('v0.2.0', bytes: 100));
        final started = Completer<void>();
        handler = (request) async {
          request.response.add([1, 2, 3]);
          await request.response.flush();
          if (!started.isCompleted) started.complete();
          await Future<void>.delayed(const Duration(milliseconds: 500));
          await request.response.close();
        };
        final cancellation = UpdateCancellation();
        final pending = downloader(
                timeout:
                    mode == 'timeout' ? const Duration(milliseconds: 30) : null)
            .download(found, cancellation, onProgress: (_, __) {});
        final expectation = expectLater(
            pending,
            throwsA(mode == 'cancel'
                ? isA<UpdateCancelled>()
                : isA<UpdateException>()
                    .having((e) => e.message, 'timeout', contains('超时'))));
        await started.future;
        if (mode == 'cancel') cancellation.cancel();
        await expectation;
        expect(temporary.listSync(recursive: true).whereType<File>(), isEmpty);
      }
    });
  });

  test(
      'update preferences use real SQLite and failed writes preserve old values',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftUpdatePreferences(database);
    expect((await repository.load()).checkOnStartup, isFalse);
    await repository.save(const UpdatePreferences(checkOnStartup: true));
    await database.customStatement(
        "CREATE TRIGGER refuse_updates BEFORE UPDATE ON preferences WHEN NEW.key='updates.preferences' BEGIN SELECT RAISE(ABORT, 'fixture disk full'); END;");
    await expectLater(
        repository.save(const UpdatePreferences(includePreview: true)),
        throwsException);
    expect((await repository.load()).checkOnStartup, isTrue);
    expect((await repository.load()).includePreview, isFalse);
    await database.customStatement('DROP TRIGGER refuse_updates');
    await database.into(database.preferences).insertOnConflictUpdate(
        PreferencesCompanion.insert(
            key: DriftUpdatePreferences.preferenceKey,
            value: '{"checkOnStartup":"private","includePreview":true}'));
    await expectLater(
        repository.load(),
        throwsA(isA<UpdateException>()
            .having((e) => e.message, 'redacted', isNot(contains('private')))));
  });
}
