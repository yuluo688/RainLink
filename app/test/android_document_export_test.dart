import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/platform/export/android_document_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('rainlink/document-test');
  late Directory directory;
  late AndroidDocumentExportService exporter;
  final calls = <MethodCall>[];
  late Future<Object?> Function(MethodCall) respond;
  const csv = '\uFEFF"日期","下载字节"\r\n"2026-10-17","100"\r\n';

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rainlink-document-test');
    exporter = AndroidDocumentExportService(
        channel: channel, temporaryDirectory: () async => directory);
    calls.clear();
    respond = (_) async => 'content://downloads/document/42';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return respond(call);
    });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  Future<void> expectTemporaryRemoved() async {
    final files = await directory
        .list(recursive: true)
        .where((entry) => entry is File)
        .toList();
    expect(files, isEmpty);
  }

  test('system export receives an exact UTF-8 file and returns its content URI',
      () async {
    respond = (call) async {
      expect(call.method, 'saveDocument');
      final arguments = call.arguments as Map;
      expect(arguments['mimeType'], 'text/csv');
      expect(arguments['suggestedName'], 'RainLink-流量.csv');
      expect(arguments.containsKey('content'), isFalse);
      final source = File(arguments['sourcePath'] as String);
      expect(await source.readAsBytes(), utf8.encode(csv));
      return 'content://downloads/document/42';
    };
    expect(await exporter.save(suggestedName: 'RainLink-流量.csv', content: csv),
        'content://downloads/document/42');
    await expectTemporaryRemoved();
  });

  test('picker cancellation returns null and removes temporary content',
      () async {
    respond = (_) async => null;
    expect(
        await exporter.save(suggestedName: 'logs.csv', content: csv), isNull);
    await expectTemporaryRemoved();
  });

  for (final reply in [
    'file:///private/secret',
    '',
    'content:/missing-authority'
  ]) {
    test('malformed saved URI is not reported as success: $reply', () async {
      respond = (_) async => reply;
      await expectLater(exporter.save(suggestedName: 'logs.csv', content: csv),
          throwsA(isA<FileSystemException>()));
      await expectTemporaryRemoved();
    });
  }

  for (final code in ['busy', 'write_failed', 'unavailable']) {
    test('native $code errors keep failure visible and release temporary files',
        () async {
      respond =
          (_) async => throw PlatformException(code: code, message: '保存失败');
      await expectLater(exporter.save(suggestedName: 'logs.csv', content: csv),
          throwsA(isA<FileSystemException>()));
      await expectTemporaryRemoved();
    });
  }

  test('timeout cancels only its request and ignores late provider completion',
      () async {
    exporter = AndroidDocumentExportService(
        channel: channel,
        temporaryDirectory: () async => directory,
        timeout: const Duration(milliseconds: 20));
    final result = Completer<String>();
    respond =
        (call) async => call.method == 'saveDocument' ? result.future : null;
    await expectLater(exporter.save(suggestedName: 'logs.csv', content: csv),
        throwsA(isA<FileSystemException>()));
    expect(calls.map((call) => call.method), ['saveDocument', 'cancelExport']);
    final first = calls.first.arguments as Map;
    expect(calls.last.arguments, {'requestId': first['requestId']});
    result.complete('content://downloads/document/late');
    await expectTemporaryRemoved();
  });

  test('invalid names and oversized content never cross the platform boundary',
      () async {
    for (final name in [
      '../logs.csv',
      'private\\logs.csv',
      'bad\u0000.csv',
      'file.bin'
    ]) {
      await expectLater(exporter.save(suggestedName: name, content: csv),
          throwsA(isA<FileSystemException>()));
    }
    await expectLater(
        exporter.save(
            suggestedName: 'large.csv',
            content: 'x' * (AndroidDocumentExportService.maxCharacters + 1)),
        throwsA(isA<FileSystemException>()));
    expect(calls, isEmpty);
    await expectTemporaryRemoved();
  });
}
