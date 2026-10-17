import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/updates/app_update_controller.dart';
import 'package:rainlink/domain/core/core_gateway.dart';
import 'package:rainlink/platform/core/desktop_core_gateway.dart';
import 'package:rainlink/platform/core/host_command_runner.dart';

import 'core_gateway_test.dart' show statusPayload;

Matcher gatewayError(String code) =>
    isA<CoreGatewayException>().having((error) => error.code, 'code', code);

void main() {
  late ControlledRunner runner;
  late DesktopCoreGateway gateway;

  setUp(() {
    runner = ControlledRunner();
    gateway = DesktopCoreGateway(
      executablePath: Platform.resolvedExecutable,
      commandRunner: runner,
    );
  });
  tearDown(() async {
    gateway.dispose();
    await runner.started.close();
  });

  test('concurrent inspections share one command; later refresh runs again',
      () async {
    final started = runner.started.stream.first;
    final statuses = Future.wait([
      for (var i = 0; i < 8; i++) gateway.inspect(),
    ]);
    await started;
    expect(runner.commands, hasLength(1));
    runner.commands.single.complete(
        HostCommandResult(exitCode: 0, stdout: jsonEncode(statusPayload())));
    expect((await statuses).every((status) => status.hostAvailable), isTrue);

    final refreshed = runner.started.stream.first;
    final next = gateway.inspect();
    await refreshed;
    expect(runner.commands, hasLength(2));
    runner.commands.last.complete(
        HostCommandResult(exitCode: 0, stdout: jsonEncode(statusPayload())));
    expect((await next).hostAvailable, isTrue);
  });

  test('a failed command does not poison later inspections', () async {
    final started = runner.started.stream.first;
    final failed = expectLater(gateway.inspect(), throwsStateError);
    await started;
    runner.commands.single.completeError(StateError('IO failed'));
    await failed;

    final refreshed = runner.started.stream.first;
    final next = gateway.inspect();
    await refreshed;
    runner.commands.last.complete(
        HostCommandResult(exitCode: 0, stdout: jsonEncode(statusPayload())));
    expect((await next).hostAvailable, isTrue);
  });

  test('a nonzero exit cannot report valid stdout as success', () async {
    final started = runner.started.stream.first;
    final outcome =
        expectLater(gateway.inspect(), throwsA(gatewayError('host_failed')));
    await started;
    runner.commands.single.complete(
        HostCommandResult(exitCode: 2, stdout: jsonEncode(statusPayload())));
    await outcome;
  });

  test('disposed gateways reject late results and new requests', () async {
    final started = runner.started.stream.first;
    final outcome =
        expectLater(gateway.inspect(), throwsA(gatewayError('disposed')));
    await started;
    gateway.dispose();
    gateway.dispose();
    runner.commands.single.complete(
        HostCommandResult(exitCode: 0, stdout: jsonEncode(statusPayload())));
    await outcome;
    await expectLater(gateway.inspect(), throwsA(gatewayError('disposed')));
    expect(runner.disposeCount, 1);
  });

  test('missing executables are unavailable without launching a command',
      () async {
    final directory = await Directory.systemTemp.createTemp('rainlink-test-');
    addTearDown(() => directory.delete());
    gateway.dispose();
    gateway = DesktopCoreGateway(
      executablePath: '${directory.path}${Platform.pathSeparator}missing',
      commandRunner: runner,
    );
    final status = await gateway.inspect();
    expect(status.hostAvailable, isFalse);
    expect(runner.commands, isEmpty);
  });

  test('update startup gates native inspection and ignores disposed consumers',
      () async {
    for (final disposeBeforeReady in [false, true]) {
      final ready = Completer<void>();
      final container = ProviderContainer(overrides: [
        coreGatewayProvider.overrideWithValue(gateway),
        startupReadyProvider.overrideWithValue(ready.future),
      ]);
      final reading = container.read(coreStatusProvider.future);
      await Future<void>.delayed(Duration.zero);
      final previous = runner.commands.length;
      if (disposeBeforeReady) container.dispose();
      final started = disposeBeforeReady ? null : runner.started.stream.first;
      ready.complete();
      if (started != null) {
        await started;
        runner.commands.last.complete(HostCommandResult(
            exitCode: 0, stdout: jsonEncode(statusPayload())));
        expect((await reading).hostAvailable, isTrue);
        container.dispose();
      } else {
        await Future<void>.delayed(Duration.zero);
        expect(runner.commands.length, previous);
      }
    }
  });
}

class ControlledRunner implements HostCommandRunner {
  final commands = <Completer<HostCommandResult>>[];
  final started = StreamController<void>.broadcast();
  int disposeCount = 0;

  @override
  Future<HostCommandResult> run(String executable, List<String> arguments) {
    expect(arguments, ['status']);
    final command = Completer<HostCommandResult>();
    commands.add(command);
    started.add(null);
    return command.future;
  }

  @override
  void dispose() => disposeCount++;
}
