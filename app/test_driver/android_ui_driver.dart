import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
    timeout: const Duration(minutes: 5),
    responseDataCallback: (data) async {
      final captures = data?['captures'];
      if (captures is! List<Object?> || captures.length != 16) {
        throw StateError('Missing Android UI captures');
      }
      final output = Directory('../docs/verification/android/ui');
      await output.create(recursive: true);
      final entries = <Map<String, Object?>>[];
      for (final capture in captures) {
        if (capture is! Map<String, Object?> ||
            capture['file'] is! String ||
            capture['png'] is! String) {
          throw StateError('Invalid Android UI capture');
        }
        final file = capture['file'] as String;
        if (!RegExp(r'^[a-z-]+-fixture\.png$').hasMatch(file)) {
          throw StateError('Invalid Android UI capture path');
        }
        await File('${output.path}/$file')
            .writeAsBytes(base64Decode(capture['png'] as String));
        entries.add({...capture}..remove('png'));
      }
      await File('${output.path}/evidence.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert({
        'scope':
            'Android renderer with isolated UI fixtures; no real network values',
        'captures': entries,
      }));
      final telemetry = data?['telemetry'];
      final realCaptures = data?['telemetryCaptures'];
      if (telemetry is! Map<String, Object?> ||
          realCaptures is! List<Object?> ||
          realCaptures.length != 2 ||
          telemetry['heldRequestClosedByUi'] != true ||
          telemetry['confirmedClearVerified'] != true) {
        throw StateError('Missing actual Android UI telemetry verification');
      }
      final realEntries = <Map<String, Object?>>[];
      for (final capture in realCaptures) {
        if (capture is! Map<String, Object?> ||
            !{'connections-real.png', 'logs-real.png'}
                .contains(capture['file']) ||
            capture['png'] is! String) {
          throw StateError('Invalid actual Android UI capture');
        }
        await File('../docs/verification/android/${capture['file']}')
            .writeAsBytes(base64Decode(capture['png'] as String));
        realEntries.add({...capture}..remove('png'));
      }
      await File('../docs/verification/android/flutter-telemetry-evidence.json')
          .writeAsString(const JsonEncoder.withIndent('  ')
              .convert({...telemetry, 'captures': realEntries}));
      final startup = data?['startup'];
      if (startup is! Map<String, Object?> ||
          startup['savedSelectionAutoConnected'] != true ||
          startup['originalSessionSurvivedUiRecreation'] != true ||
          startup['differentSelectedTargetDidNotReplaceActive'] != true ||
          startup['foregroundResumeDidNotReconnectAfterManualStop'] != true ||
          startup['nativeSessionIdleAfterManualStop'] != true ||
          startup['actualCoreResponses'] != 2) {
        throw StateError(
            'Missing actual Android automatic startup verification');
      }
      await File('../docs/verification/android/flutter-startup-evidence.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(startup));
    });
