import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
    timeout: const Duration(minutes: 5),
    responseDataCallback: (data) async {
      final report = data?['configuration'];
      const requiredChecks = [
        'visualEditorSavedWithoutConnecting',
        'overviewConnectedSavedChain',
        'actualForwardAndReverseOrderVerified',
        'editingAndSelectionKeptActivePath',
        'liveAdvancedRejectPreventedActualRequest',
        'liveApplyKeptOriginalTargetModeAndHops',
        'advancedAndPreviousPersistedAtomically',
        'failedRestartRestoredActualTransfer',
        'ruleChainAndAllThreeModesVerified',
      ];
      if (report is! Map<String, Object?> ||
          report['successfulResponses'] != 9 ||
          report['originRequests'] != 9 ||
          requiredChecks.any((key) => report[key] != true)) {
        throw StateError('Missing actual Android configuration verification');
      }
      await File(
              '../docs/verification/android/flutter-configuration-evidence.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    });
