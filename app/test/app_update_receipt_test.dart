import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rainlink/domain/updates/app_update.dart';
import 'package:rainlink/platform/updates/process_update_installer.dart';

void main() {
  late Directory support;
  late File receipt;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('rainlink-receipt-test-');
    receipt = File(p.join(support.path, 'update-result.json'));
  });
  tearDown(() async => support.delete(recursive: true));

  test('interrupted recovery is reported once without exposing local details',
      () async {
    await receipt.writeAsString(jsonEncode({
      'status': 'interrupted-restored',
      'version': '0.1.0+3',
      'untrusted': 'private-path-and-credential',
    }));
    expect(await readUpdateReceipt(supportDirectory: () async => support),
        '上次更新意外中断，已恢复原版本和升级前的数据。');
    expect(await receipt.exists(), isFalse);
    expect(
        await readUpdateReceipt(supportDirectory: () async => support), isNull);
  });

  test('accepted and unresolved updates have distinct receipts', () async {
    await receipt.writeAsString('{"status":"installed"}');
    expect(await readUpdateReceipt(supportDirectory: () async => support),
        '应用更新已安装，新版本已通过启动检查。');
    await receipt.writeAsString('{"status":"recovery-required"}');
    expect(await readUpdateReceipt(supportDirectory: () async => support),
        '上次更新未能完成恢复，备份已保留，请检查安装目录。');
  });

  test('invalid or oversized state cannot report success', () async {
    await receipt.writeAsString('{"status":"unexpected","path":"private"}');
    expect(await readUpdateReceipt(supportDirectory: () async => support),
        '上次更新回执无效，请检查安装目录。');
    await receipt.writeAsString('x' * 4097);
    await expectLater(readUpdateReceipt(supportDirectory: () async => support),
        throwsA(isA<UpdateException>()));
    expect(await receipt.exists(), isTrue,
        reason:
            'Retain unreadable evidence for recovery instead of consuming it');
  });
}
