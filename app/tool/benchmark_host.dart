import 'dart:convert';
import 'dart:io';

import 'package:rainlink/platform/core/desktop_core_gateway.dart';

/// Measures only one-shot host inspection, excluding Dart VM startup.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr
        .writeln('Usage: dart run tool/benchmark_host.dart <host executable>');
    exitCode = 64;
    return;
  }
  final gateway = DesktopCoreGateway(executablePath: arguments.single);
  try {
    for (var i = 0; i < 5; i++) {
      if (!(await gateway.inspect()).hostAvailable) {
        throw StateError('Host unavailable');
      }
    }
    final samples = <String, Object>{};
    for (final concurrency in [1, 8]) {
      final timings = <int>[];
      for (var sample = 0; sample < 30; sample++) {
        final timer = Stopwatch()..start();
        final statuses = await Future.wait([
          for (var i = 0; i < concurrency; i++) gateway.inspect(),
        ]);
        timer.stop();
        if (statuses.any((status) => !status.hostAvailable)) {
          throw StateError('Host unavailable');
        }
        timings.add(timer.elapsedMicroseconds);
      }
      timings.sort();
      samples['concurrency_$concurrency'] = {
        'samples': timings.length,
        'p50_ms': timings[timings.length ~/ 2] / 1000,
        'p95_ms': timings[(timings.length * .95).ceil() - 1] / 1000,
      };
    }
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(samples));
  } finally {
    gateway.dispose();
  }
}
