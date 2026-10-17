import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/domain/core/core_gateway.dart';
import 'package:rainlink/platform/core/host_command_runner.dart';

Matcher commandError(String code) =>
    isA<CoreGatewayException>().having((error) => error.code, 'code', code);

void main() {
  test('reads chunked output at the limit and drains binary diagnostics',
      () async {
    final process = ControlledProcess();
    final runner = ProcessHostCommandRunner(
      maxOutputBytes: 4,
      startProcess: (_, __) async => process,
    );
    addTearDown(runner.dispose);
    final result = runner.run('host', ['status']);
    process.output.add([65, 66]);
    process.output.add([67, 68]);
    process.diagnostics.add([255, 255, 255, 255]);
    process.finish(0);
    expect((await result).stdout, 'ABCD');
    expect(process.killed, isFalse);
  });

  for (final channel in ['stdout', 'stderr']) {
    test('oversized $channel fails immediately and reaps the child', () async {
      final process = ControlledProcess();
      final runner = ProcessHostCommandRunner(
        maxOutputBytes: 4,
        startProcess: (_, __) async => process,
      );
      addTearDown(runner.dispose);
      final result = runner.run('host', ['status']);
      final output = channel == 'stdout' ? process.output : process.diagnostics;
      output.add([1, 2, 3, 4, 5]);
      await expectLater(result.timeout(const Duration(seconds: 1)),
          throwsA(commandError('invalid_response')));
      expect(process.killed, isTrue);
      expect(await process.exitCode, -9);
      expect(process.output.hasListener, isFalse);
      expect(process.diagnostics.hasListener, isFalse);
    });
  }

  test('timeout terminates a running command and waits for exit', () async {
    final process = ControlledProcess();
    final runner = ProcessHostCommandRunner(
      timeout: const Duration(milliseconds: 20),
      startProcess: (_, __) async => process,
    );
    addTearDown(runner.dispose);
    await expectLater(
        runner.run('host', ['status']), throwsA(commandError('host_timeout')));
    expect(process.killed, isTrue);
    expect(await process.exitCode, -9);
    expect(process.output.hasListener, isFalse);
    expect(process.diagnostics.hasListener, isFalse);
  });

  test('timeout includes startup and reclaims a late child', () async {
    final starting = Completer<Process>();
    final process = ControlledProcess();
    final runner = ProcessHostCommandRunner(
      timeout: const Duration(milliseconds: 20),
      startProcess: (_, __) => starting.future,
    );
    addTearDown(runner.dispose);
    await expectLater(
        runner.run('host', ['status']), throwsA(commandError('host_timeout')));
    starting.complete(process);
    await Future<void>.delayed(Duration.zero);
    expect(process.killed, isTrue);
    expect(await process.exitCode, -9);
    expect(process.output.hasListener, isFalse);
    expect(process.diagnostics.hasListener, isFalse);
  });

  test('dispose cancels active work and forbids new commands', () async {
    final process = ControlledProcess();
    final runner = ProcessHostCommandRunner(
      startProcess: (_, __) async => process,
    );
    final outcome = expectLater(
        runner.run('host', ['status']), throwsA(commandError('disposed')));
    await Future<void>.delayed(Duration.zero);
    runner.dispose();
    runner.dispose();
    await outcome;
    await expectLater(
        runner.run('host', ['status']), throwsA(commandError('disposed')));
    expect(process.killed, isTrue);
    expect(process.killCount, 1);
    expect(await process.exitCode, -9);
  });

  test('dispose during startup also reclaims the late child', () async {
    final starting = Completer<Process>();
    final process = ControlledProcess();
    final runner = ProcessHostCommandRunner(
      startProcess: (_, __) => starting.future,
    );
    final outcome = expectLater(
        runner.run('host', ['status']), throwsA(commandError('disposed')));
    runner.dispose();
    await outcome;
    starting.complete(process);
    await Future<void>.delayed(Duration.zero);
    expect(process.killed, isTrue);
    expect(await process.exitCode, -9);
  });

  test('invalid UTF-8 and failed startup use domain errors', () async {
    final process = ControlledProcess();
    final runner = ProcessHostCommandRunner(
      startProcess: (_, __) async => process,
    );
    addTearDown(runner.dispose);
    final result = runner.run('host', ['status']);
    process.output.add([255]);
    process.finish(0);
    await expectLater(result, throwsA(commandError('invalid_response')));

    final failedRunner = ProcessHostCommandRunner(
      startProcess: (_, __) async => throw const ProcessException(
          'private path', [], 'private diagnostic'),
    );
    addTearDown(failedRunner.dispose);
    await expectLater(failedRunner.run('host', ['status']),
        throwsA(commandError('host_start_failed')));
  });

  test('an unresponsive child reports failed shutdown', () async {
    final process = ControlledProcess(ignoreKill: true);
    final runner = ProcessHostCommandRunner(
      timeout: const Duration(milliseconds: 20),
      startProcess: (_, __) async => process,
    );
    addTearDown(runner.dispose);
    try {
      await expectLater(runner.run('host', ['status']),
          throwsA(commandError('host_shutdown_failed')));
    } finally {
      process.finish(-9);
    }
  });
}

/// Deterministic lifecycle tests; the desktop smoke test uses the real Go host.
class ControlledProcess implements Process {
  ControlledProcess({this.ignoreKill = false});

  final bool ignoreKill;
  final output = StreamController<List<int>>();
  final diagnostics = StreamController<List<int>>();
  final _input = StreamController<List<int>>.broadcast();
  final _exit = Completer<int>();
  bool killed = false;
  int killCount = 0;

  @override
  late final IOSink stdin = IOSink(_input.sink);
  @override
  Stream<List<int>> get stdout => output.stream;
  @override
  Stream<List<int>> get stderr => diagnostics.stream;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  int get pid => 1;

  void finish(int code) {
    if (_exit.isCompleted) return;
    _exit.complete(code);
    unawaited(output.close());
    unawaited(diagnostics.close());
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killCount++;
    killed = true;
    if (ignoreKill) return false;
    finish(-9);
    return true;
  }
}
