import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/core/core_gateway.dart';

class HostCommandResult {
  const HostCommandResult({required this.exitCode, required this.stdout});

  final int exitCode;
  final String stdout;
}

abstract interface class HostCommandRunner {
  Future<HostCommandResult> run(String executable, List<String> arguments);

  void dispose();
}

typedef ProcessStarter = Future<Process> Function(
    String executable, List<String> arguments);

/// Bounds output and time, and reaps the direct child before completing a run.
class ProcessHostCommandRunner implements HostCommandRunner {
  ProcessHostCommandRunner({
    this.timeout = const Duration(seconds: 5),
    this.maxOutputBytes = 64 * 1024,
    ProcessStarter? startProcess,
  })  : assert(timeout > Duration.zero),
        assert(maxOutputBytes > 0),
        _startProcess = startProcess ?? Process.start;

  final Duration timeout;
  final int maxOutputBytes;
  final ProcessStarter _startProcess;
  final _commands = <_HostCommandExecution>{};
  bool _disposed = false;

  @override
  Future<HostCommandResult> run(String executable, List<String> arguments) {
    if (_disposed) {
      return Future.error(const CoreGatewayException('disposed', '核心接口已关闭'));
    }
    final command = _HostCommandExecution(
      executable: executable,
      arguments: List.unmodifiable(arguments),
      startProcess: _startProcess,
      timeout: timeout,
      maxOutputBytes: maxOutputBytes,
    );
    _commands.add(command);
    return command.run().whenComplete(() => _commands.remove(command));
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final command in _commands.toList()) {
      command.cancel();
    }
  }
}

class _HostCommandExecution {
  _HostCommandExecution({
    required this.executable,
    required this.arguments,
    required this.startProcess,
    required this.timeout,
    required this.maxOutputBytes,
  });

  final String executable;
  final List<String> arguments;
  final ProcessStarter startProcess;
  final Duration timeout;
  final int maxOutputBytes;
  final _cancelled = Completer<HostCommandResult>();
  Process? _process;
  Future<int>? _exitCode;
  StreamIterator<List<int>>? _stdout;
  StreamIterator<List<int>>? _stderr;
  Future<void>? _closing;
  bool _stopped = false;
  bool _exited = false;

  Future<HostCommandResult> run() async {
    try {
      return await Future.any([_startAndRead(), _cancelled.future]).timeout(
        timeout,
        onTimeout: () =>
            throw const CoreGatewayException('host_timeout', '桌面宿主响应超时'),
      );
    } on ProcessException {
      throw const CoreGatewayException('host_start_failed', '无法启动桌面宿主');
    } on FormatException {
      throw const CoreGatewayException('invalid_response', '宿主响应编码无效');
    } finally {
      _stopped = true;
      await _release();
    }
  }

  Future<HostCommandResult> _startAndRead() async {
    final process = await startProcess(executable, arguments);
    _process = process;
    final exitCode = _exitCode = process.exitCode.then((code) {
      _exited = true;
      return code;
    });
    final output = _stdout = StreamIterator(process.stdout);
    final diagnostics = _stderr = StreamIterator(process.stderr);
    // Process.start itself cannot be cancelled. Reclaim a late child on arrival.
    if (_stopped) {
      await _release();
      throw const CoreGatewayException('disposed', '核心接口已关闭');
    }
    final stdout = _readBounded(output);
    await Future.wait<void>([
      exitCode.then((_) {}),
      stdout.then((_) {}),
      _readBounded(diagnostics, retain: false).then((_) {}),
      process.stdin.close(),
    ], eagerError: true);
    return HostCommandResult(
      exitCode: await exitCode,
      stdout: utf8.decode(await stdout),
    );
  }

  Future<Uint8List> _readBounded(StreamIterator<List<int>> chunks,
      {bool retain = true}) async {
    final bytes = BytesBuilder(copy: false);
    var length = 0;
    while (await chunks.moveNext()) {
      final chunk = chunks.current;
      length += chunk.length;
      if (length > maxOutputBytes) {
        throw const CoreGatewayException('invalid_response', '宿主响应超过大小限制');
      }
      if (retain) bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  void cancel() {
    if (_stopped) return;
    _stopped = true;
    _cancelled.completeError(const CoreGatewayException('disposed', '核心接口已关闭'));
  }

  Future<void> _release() {
    final process = _process;
    if (process == null) return Future<void>.value();
    return _closing ??= _close(process);
  }

  Future<void> _close(Process process) async {
    if (!_exited) process.kill(ProcessSignal.sigkill);
    await Future.wait<void>([
      if (_stdout case final output?) output.cancel(),
      if (_stderr case final diagnostics?) diagnostics.cancel(),
      if (_exitCode case final exit?) exit.then((_) {}),
      process.stdin.close(),
    ]).timeout(const Duration(seconds: 1), onTimeout: () {
      throw const CoreGatewayException('host_shutdown_failed', '桌面宿主未能及时退出');
    });
  }
}
