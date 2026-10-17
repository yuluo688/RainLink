import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:rainlink/domain/core/core_gateway.dart';
import 'package:rainlink/platform/core/host_command_runner.dart';

/// Exercises failure cleanup with actual OS processes, using this Dart VM.
Future<void> main(List<String> arguments) async {
  if (arguments case ['--fixture', final mode]) {
    final output = mode == 'stderr_limit' ? stderr : stdout;
    if (mode.endsWith('_limit')) {
      output.add(List<int>.filled(64 * 1024 + 1, 65));
      await output.flush();
    }
    await Future<void>.delayed(const Duration(minutes: 1));
    return;
  }
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: dart run tool/verify_host_process.dart');
    exitCode = 64;
    return;
  }

  final results = <Map<String, Object>>[];
  for (final scenario in [
    ('stdout_limit', 'invalid_response'),
    ('stderr_limit', 'invalid_response'),
    ('timeout', 'host_timeout'),
    ('dispose', 'disposed'),
  ]) {
    final spawned = Completer<Process>();
    final runner = ProcessHostCommandRunner(
      timeout: scenario.$1 == 'timeout'
          ? const Duration(milliseconds: 800)
          : const Duration(seconds: 5),
      startProcess: (executable, arguments) async {
        final process = await Process.start(executable, arguments);
        spawned.complete(process);
        return process;
      },
    );
    try {
      final result = runner.run(Platform.resolvedExecutable, [
        Platform.script.toFilePath(),
        '--fixture',
        scenario.$1,
      ]);
      final outcome = result.then<String>(
        (_) => throw StateError('Unexpected success: ${scenario.$1}'),
        onError: (Object error, StackTrace stack) {
          if (error is CoreGatewayException) return error.code;
          Error.throwWithStackTrace(error, stack);
        },
      );
      final cancellation = scenario.$1 == 'dispose'
          ? spawned.future.then((_) async {
              await Future<void>.delayed(const Duration(milliseconds: 50));
              runner.dispose();
            })
          : Future<void>.value();
      final code = await outcome;
      if (code != scenario.$2) {
        throw StateError('${scenario.$1}: expected ${scenario.$2}, got $code');
      }
      await cancellation;
      final process = await spawned.future;
      final childExit =
          await process.exitCode.timeout(const Duration(seconds: 1));
      if (childExit == 0) throw StateError('Child was not terminated');
      results.add({
        'scenario': scenario.$1,
        'error': code,
        'childReaped': true,
      });
    } finally {
      runner.dispose();
    }
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(results));
}
