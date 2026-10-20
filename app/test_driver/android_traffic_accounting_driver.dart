import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 7),
  responseDataCallback: (data) async {
    final report = data?['accounting'];
    final captures = data?['captures'];
    const checks = [
      'systemTunnelEstablished',
      'sameSessionAcrossModes',
      'actualClosedFlowsIncluded',
      'bothPartitionsConserved',
      'shellApplicationIdentified',
      'duplicateSamplesIgnored',
      'databaseReopened',
      'uiCsvReadBack',
    ];
    if (report is! Map<String, Object?> ||
        checks.any((check) => report[check] != true) ||
        report['userDatabaseModified'] != false ||
        captures is! List<Object?> ||
        captures.length != 5) {
      throw StateError('Missing Android actual traffic accounting evidence');
    }
    final output = Directory(
      Platform.environment['RAINLINK_QA_OUTPUT'] ??
          '../docs/verification/android-traffic-accounting/android',
    );
    await output.create(recursive: true);
    final entries = <Map<String, Object?>>[];
    for (final capture in captures) {
      if (capture is! Map<String, Object?> ||
          capture['file'] is! String ||
          capture['png'] is! String ||
          !RegExp(r'^[a-z-]+\.png$').hasMatch(capture['file'] as String)) {
        throw StateError('Invalid accounting screenshot');
      }
      await File(
        '${output.path}/${capture['file']}',
      ).writeAsBytes(base64Decode(capture['png'] as String));
      entries.add({...capture}..remove('png'));
    }
    await File('${output.path}/flutter-evidence.json').writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert({...report, 'captures': entries}),
    );
  },
);
