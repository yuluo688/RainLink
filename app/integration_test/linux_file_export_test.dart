import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/app/router.dart';
import 'package:rainlink/platform/window/desktop_window.dart';

import '../test/support/ui_fixture.dart';

// The helper touches only this process's real GTK dialogs. It runs separately
// because GTK can enter a nested native event loop while the picker is open.
const _dialogDriver = r'''
import json, subprocess, sys, time

pid, action, target, capture = sys.argv[1:]
deadline = time.monotonic() + 20
dialog = None
while time.monotonic() < deadline:
    windows = subprocess.run(
        ['xdotool', 'search', '--onlyvisible', '--pid', pid],
        capture_output=True, text=True, timeout=3)
    for window in windows.stdout.splitlines():
        kind = subprocess.run(
            ['xprop', '-id', window, '_NET_WM_WINDOW_TYPE'],
            capture_output=True, text=True, timeout=3)
        if '_NET_WM_WINDOW_TYPE_DIALOG' in kind.stdout:
            dialog = window
            break
    if dialog:
        break
    time.sleep(.1)
if dialog is None:
    raise RuntimeError('No GTK dialog belonging to the test process appeared')
subprocess.run(['import', '-window', 'root', capture], check=True, timeout=10)
subprocess.run(['xdotool', 'windowactivate', '--sync', dialog], check=True, timeout=5)
if action == 'cancel':
    subprocess.run(['xdotool', 'key', '--clearmodifiers', 'Escape'], check=True, timeout=5)
elif action == 'save':
    subprocess.run(['xdotool', 'key', '--clearmodifiers', 'ctrl+a'], check=True, timeout=5)
    subprocess.run(['xdotool', 'type', '--clearmodifiers', '--', target], check=True, timeout=5)
    subprocess.run(['xdotool', 'key', '--clearmodifiers', 'Return'], check=True, timeout=5)
else:
    raise ValueError('Unknown dialog action')
print(json.dumps({'dialog': dialog, 'action': action}))
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real GTK export cancels, retries and writes the selected CSV',
    (tester) async {
      expect(Platform.isLinux, isTrue);
      expect(const String.fromEnvironment('RAINLINK_TEST_DESKTOP'), 'isolated');
      expect(
        Platform.environment['XDG_CONFIG_HOME'],
        startsWith('/tmp/rainlink-file-export-'),
      );
      final output = Directory(
        const String.fromEnvironment(
          'RAINLINK_VISUAL_OUTPUT',
          defaultValue: '/qa/output/linux-lifecycle/file-export',
        ),
      );
      await output.create(recursive: true);
      final temporary = await Directory.systemTemp.createTemp(
        'rainlink-file-export-files-',
      );
      final destination = Directory('${temporary.path}/Export folder');
      await destination.create();
      final csv = File('${destination.path}/rainlink-traffic.csv');
      final router = createRouter(initialLocation: '/traffic');
      final results = <String, Object?>{};
      try {
        await initializeDesktopWindow();
        await tester.pumpWidget(
          ProviderScope(
            overrides: visualOverrides(),
            child: RainlinkApp(router: router),
          ),
        );
        await tester.pumpAndSettle();

        Future<void> usePicker(String action) async {
          final helper = await Process.start('python3', [
            '-c',
            _dialogDriver,
            '$pid',
            action,
            csv.path,
            '${output.path}/picker-$action.png',
          ]);
          final stdout = utf8.decoder.bind(helper.stdout).join();
          final stderr = utf8.decoder.bind(helper.stderr).join();
          try {
            await tester.tap(find.byKey(const ValueKey('export-traffic')));
            final exitCode = await helper.exitCode.timeout(
              const Duration(seconds: 35),
            );
            expect(exitCode, 0, reason: await stderr);
            results[action] = jsonDecode(await stdout);
          } finally {
            if (helper.kill(ProcessSignal.sigkill)) {
              await helper.exitCode.timeout(const Duration(seconds: 5));
            }
          }
          for (var attempt = 0; attempt < 50; attempt++) {
            await tester.pump(const Duration(milliseconds: 100));
            if (find.text('导出中…').evaluate().isEmpty) break;
          }
          expect(find.text('导出中…'), findsNothing);
          expect(find.text('导出失败，请检查保存位置和磁盘空间'), findsNothing);
        }

        await usePicker('cancel');
        expect(await csv.exists(), isFalse);
        expect(find.text('已导出当前周期流量'), findsNothing);
        results['cancelDoesNotWriteOrReportSuccess'] = true;

        await usePicker('save');
        final content = await csv.readAsString();
        expect(content, contains('日汇总'));
        expect(content, contains('时段明细'));
        expect(content, contains('东京 · 樱花'));
        expect(content, isNot(contains('example.test')));
        expect(find.text('已导出当前周期流量'), findsOneWidget);
        expect(tester.takeException(), isNull);
        results['selectedPathWithSpacesWrittenAndReadBack'] = true;
        results['csvBytes'] = await csv.length();
        results['fixtureDataOnly'] = true;
        await File('${output.path}/exported.csv').writeAsString(content);
        await File('${output.path}/result.json').writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(results)}\n',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        router.dispose();
        await temporary.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
