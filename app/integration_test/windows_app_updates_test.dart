import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:rainlink/data/updates/github_release_source.dart';
import 'package:rainlink/domain/updates/app_update.dart';
import 'package:rainlink/platform/updates/file_update_downloader.dart';
import 'package:rainlink/platform/updates/process_update_installer.dart';
import 'package:rainlink/platform/window/desktop_window.dart';

const _bundleScript = r'''
import hashlib, json, pathlib, sys, zipfile
directory = pathlib.Path(sys.argv[1])
files = {name: ("fixture-" + name).encode() for name in [
    "rainlink.exe", "rainlink-host.exe", "rainlink-updater.exe", "sing-box.exe",
    "rainlink-ui.exe", "flutter_windows.dll", "data/app.so"]}
files["rainlink.exe"] = pathlib.Path(sys.argv[2]).read_bytes()
manifest = {"schema": 2, "product": "RainLink", "platform": "windows-x64",
            "version": "0.2.0+1", "files": [
                {"path": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
                for name, data in files.items()]}
with zipfile.ZipFile(directory / "fixture.zip", "w", zipfile.ZIP_DEFLATED) as output:
    for name, data in files.items():
        output.writestr(name, data)
    output.writestr("rainlink-bundle.json", json.dumps(manifest))
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real download, copied Windows helper readiness and safe abort',
      (tester) async {
    await initializeDesktopWindow();
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: Text('RainLink 更新隔离验收')))));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final target = Directory(p.dirname(Platform.resolvedExecutable));
      // This integration runs inside Flutter's disposable Debug build. It can
      // prepare/abort only; it never commits a replacement of its own runner.
      expect(p.basename(target.path), 'Debug');
      expect(target.path.replaceAll('\\', '/'),
          contains('/app/build/windows/x64/runner/Debug'));
      final temporary =
          await Directory.systemTemp.createTemp('rainlink-update-integration-');
      final created = <File>[];
      HttpServer? server;
      PreparedUpdate? prepared;
      try {
        final currentManifest =
            File(p.join(target.path, 'rainlink-bundle.json'));
        expect(await currentManifest.exists(), isFalse,
            reason: 'Never overwrite an existing installation manifest');
        final helperBuild =
            File(p.absolute('../build/host/rainlink-updater.exe'));
        expect(await helperBuild.exists(), isTrue);
        final helperTarget = File(p.join(target.path, 'rainlink-updater.exe'));
        if (!await helperTarget.exists()) {
          created.add(await helperBuild.copy(helperTarget.path));
        }
        expect((await sha256.bind(helperTarget.openRead()).first).toString(),
            (await sha256.bind(helperBuild.openRead()).first).toString());
        final entries = <Map<String, Object?>>[];
        for (final name in [
          'rainlink.exe',
          'rainlink-ui.exe',
          'rainlink-host.exe',
          'rainlink-updater.exe',
          'sing-box.exe',
          'flutter_windows.dll',
          'data/app.so'
        ]) {
          final file = File(p.join(target.path, name));
          if (!await file.exists()) {
            await file.parent.create(recursive: true);
            await file.writeAsString('current debug fixture', flush: true);
            created.add(file);
          }
          entries.add({
            'path': name,
            'bytes': await file.length(),
            'sha256': (await sha256.bind(file.openRead()).first).toString(),
          });
        }
        await currentManifest.writeAsString(
            jsonEncode({
              'schema': 2,
              'product': 'RainLink',
              'platform': 'windows-x64',
              'version': '0.1.0+3',
              'files': entries,
            }),
            flush: true);
        created.add(currentManifest);
        final generated = await Process.run(
            'python',
            [
              '-c',
              _bundleScript,
              temporary.path,
              p.join(target.path, 'rainlink.exe')
            ],
            runInShell: false);
        expect(generated.exitCode, 0, reason: 'Local bundle fixture creation');
        final bundle = File(p.join(temporary.path, 'fixture.zip'));
        final bytes = await bundle.readAsBytes();
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final origin = ReleaseOrigin.loopback(
            Uri.parse('http://127.0.0.1:${server.port}'));
        final name = 'RainLink-0.2.0+1-windows-x64.zip';
        server.listen((request) async {
          if (request.uri.path.startsWith('/repos/')) {
            request.response.write(jsonEncode([
              {
                'tag_name': 'v0.2.0+1',
                'draft': false,
                'prerelease': false,
                'published_at': '2026-10-17T00:00:00Z',
                'body': '本地测试',
                'html_url': origin.page('v0.2.0+1').toString(),
                'assets': [
                  {
                    'name': name,
                    'size': bytes.length,
                    'digest': 'sha256:${sha256.convert(bytes)}',
                    'browser_download_url':
                        origin.asset('v0.2.0+1', name).toString(),
                  }
                ],
              }
            ]));
          } else {
            request.response.add(bytes);
          }
          await request.response.close();
        });
        final source = GithubReleaseSource(origin: origin);
        final release = await source.latest(
            includePreview: false, cancellation: UpdateCancellation());
        expect(release, isNotNull);
        if (release == null) throw StateError('Fixture release missing');
        final cache = await Directory(p.join(temporary.path, 'cache')).create();
        final support =
            await Directory(p.join(temporary.path, 'support')).create();
        final downloader = FileUpdateDownloader(
            origin: origin, cacheDirectory: () async => cache);
        final downloaded = await downloader
            .download(release, UpdateCancellation(), onProgress: (_, __) {});
        final installer = ProcessUpdateInstaller(
            supportDirectory: () async => support,
            cacheDirectory: () async => cache);
        prepared = await installer.prepare(downloaded, UpdateCancellation());
        expect(await File(p.join(target.path, '.rainlink-updating')).exists(),
            isTrue);
        // Readiness must not touch any installed runtime bytes.
        for (final entry in entries) {
          final file = File(p.join(target.path, entry['path']! as String));
          expect((await sha256.bind(file.openRead()).first).toString(),
              entry['sha256']);
        }
        await prepared.abort();
        prepared = null;
        expect(await File(p.join(target.path, '.rainlink-updating')).exists(),
            isFalse);
        expect(
            (await cache.list(recursive: true).toList())
                .whereType<File>()
                .where((file) => file.path.endsWith('.exe')),
            isEmpty);
        await downloader.discard(downloaded);
        await Directory('../docs/verification/app-update-recovery')
            .create(recursive: true);
        await File(
                '../docs/verification/app-update-recovery/windows-evidence.json')
            .writeAsString('${const JsonEncoder.withIndent('  ').convert({
              'realLoopbackHttp': true,
              'actualSha256Download': true,
              'copiedWindowsHelperReady': true,
              'safeAbortAcknowledged': true,
              'installedRuntimeUnchanged': true,
              'helperCacheRemoved': true,
              'committedInThisTest': false,
              'userDatabaseUsed': false,
            })}\n');
      } finally {
        await prepared?.abort();
        await server?.close(force: true);
        for (final file in created.reversed) {
          if (await file.exists()) await file.delete();
        }
        await temporary.delete(recursive: true);
      }
    });
    expect(tester.takeException(), isNull);
  });
}
