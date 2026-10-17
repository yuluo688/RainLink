import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/core/core_gateway.dart';

/// The inherited stdio channel is private to this UI and its host process.
class HostSessionClient {
  HostSessionClient(this.executable,
      {this.arguments = const ['serve'],
      this.connectTimeout = const Duration(seconds: 95),
      this.disconnectTimeout = const Duration(seconds: 50),
      this.requestTimeout = const Duration(seconds: 25)});
  final String executable;
  final List<String> arguments;
  final Duration requestTimeout;
  final Duration connectTimeout;
  final Duration disconnectTimeout;
  static const maxFrameBytes = 128 * 1024;
  Process? _process;
  Future<void>? _opening;
  bool _closed = false;
  bool _terminated = false;
  bool get terminated => _closed || _terminated;
  int _nextId = 0;
  Future<void> _writes = Future.value();
  final _pending = <int, Completer<Map<String, Object?>>>{};
  StreamSubscription<String>? _output;
  StreamSubscription<List<int>>? _diagnostics;
  final _failures = StreamController<CoreGatewayException>.broadcast();
  Stream<CoreGatewayException> get failures => _failures.stream;

  Future<void> _ensureOpen() => _opening ??= _open().catchError((Object error) {
        _opening = null;
        Error.throwWithStackTrace(error, StackTrace.current);
      });

  Future<void> _open() async {
    if (_closed) throw const CoreGatewayException('disposed', '核心接口已关闭');
    final Process process;
    try {
      process = await Process.start(executable, arguments);
    } on ProcessException {
      throw const CoreGatewayException('host_start_failed', '无法启动桌面宿主');
    }
    _process = process;
    if (_closed) {
      await process.stdin.close();
      return;
    }
    // Host stderr is drained, never copied into UI errors or logs.
    _diagnostics = process.stderr.listen((_) {});
    var lineSize = 0;
    final lines = process.stdout
        .map((bytes) {
          for (final byte in bytes) {
            lineSize = byte == 10 ? 0 : lineSize + 1;
            if (lineSize > 128 * 1024) {
              throw const FormatException('Host frame exceeds limit');
            }
          }
          return bytes;
        })
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    _output = lines.listen(_receive,
        onError: (Object error) =>
            _fail(const CoreGatewayException('invalid_response', '宿主通信中断')),
        onDone: () =>
            _fail(const CoreGatewayException('host_exited', '宿主已退出，请重试连接')));
    unawaited(process.exitCode.then((_) {
      _fail(const CoreGatewayException('host_exited', '宿主已退出，系统代理将由恢复保护清理'));
    }));
  }

  void _receive(String line) {
    try {
      final Object? message = jsonDecode(line);
      if (message
          case {
            'id': int id,
            'error': {'code': String code, 'message': String text}
          }) {
        _pending.remove(id)?.completeError(CoreGatewayException(code, text));
      } else if (message case {'id': int id}) {
        final result = (message as Map<String, Object?>)['result'];
        if (result == null) {
          _pending.remove(id)?.complete(const {});
        } else if (result is Map<String, Object?>) {
          _pending.remove(id)?.complete(result);
        } else {
          throw const FormatException('Invalid response payload');
        }
      } else {
        throw const FormatException('Invalid response');
      }
    } on FormatException {
      _fail(const CoreGatewayException('invalid_response', '宿主响应格式无效'));
    }
  }

  void _fail(CoreGatewayException error) {
    if (_terminated) return;
    _terminated = true;
    for (final pending in _pending.values) {
      pending.completeError(error);
    }
    _pending.clear();
    if (!_closed && !_failures.isClosed) _failures.add(error);
  }

  Future<void> _write(Process process, String frame) {
    // IOSink forbids writes while flush() binds its stream. Serialize frames,
    // while allowing independent callers to await their replies concurrently.
    final writing = _writes.then((_) async {
      if (_closed || _terminated) {
        throw const CoreGatewayException('host_unavailable', '桌面宿主不可用');
      }
      process.stdin.writeln(frame);
      await process.stdin.flush();
    });
    // Errors still reach the originating request; the barrier only sequences
    // the next writer and the eventual close without duplicating that error.
    _writes = writing.then((_) {}, onError: (Object _) {});
    return writing;
  }

  Future<Map<String, Object?>> request(String method,
      [Map<String, Object?> payload = const {}]) async {
    final id = ++_nextId;
    final frame = jsonEncode({'id': id, 'method': method, 'payload': payload});
    // Reject before writing a partial frame: exceeding Go Scanner's bound would
    // otherwise kill the channel and disconnect an unrelated active session.
    if (utf8.encode(frame).length + 1 >= maxFrameBytes) {
      throw const CoreGatewayException(
          'request_too_large', '配置超出单次传输限制，请减少规则出站数量');
    }
    await _ensureOpen();
    if (_closed || _terminated) {
      throw const CoreGatewayException('host_unavailable', '桌面宿主不可用');
    }
    final process = _process;
    if (process == null) {
      throw const CoreGatewayException('host_unavailable', '桌面宿主不可用');
    }
    final pending = Completer<Map<String, Object?>>();
    _pending[id] = pending;
    // Install the error listener before flushing the pipe: a fast host failure
    // can arrive while flush is still pending.
    // Native TUN restoration can take longer than an ordinary read. Keep the
    // channel alive for the host's 45-second bounded disconnect operation.
    final timeout = switch (method) {
      'connect' => connectTimeout,
      'disconnect' => disconnectTimeout,
      _ => requestTimeout,
    };
    final reply = pending.future.timeout(timeout);
    try {
      await Future.wait<void>([_write(process, frame), reply.then((_) {})],
          eagerError: true);
      return await reply;
    } on TimeoutException {
      // A timeout closes the channel. The host cancels and rolls back on EOF,
      // so a late success cannot leave capture running behind a failed UI.
      unawaited(close());
      throw const CoreGatewayException('host_timeout', '宿主响应超时，正在恢复网络设置');
    } on IOException {
      _fail(const CoreGatewayException('host_io_failed', '宿主通信失败'));
      throw const CoreGatewayException('host_io_failed', '宿主通信失败');
    } on StateError {
      _fail(const CoreGatewayException('host_io_failed', '宿主通信失败'));
      throw const CoreGatewayException('host_io_failed', '宿主通信失败');
    } finally {
      _pending.remove(id);
    }
  }

  Future<void>? _closing;
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    // A cancel can arrive during Process.start. Wait for that attempt so its
    // process is also reaped; the original request reports any start failure.
    await _opening?.then<void>((_) {}, onError: (Object _) {});
    final process = _process;
    if (process != null) {
      try {
        await _writes.timeout(const Duration(seconds: 2));
        await process.stdin.close();
        await process.exitCode.timeout(const Duration(seconds: 6));
      } on TimeoutException {
        process.kill();
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on IOException {
        process.kill();
        await process.exitCode.timeout(const Duration(seconds: 2));
      } finally {
        await _output?.cancel();
        await _diagnostics?.cancel();
      }
    }
    _fail(const CoreGatewayException('disposed', '核心接口已关闭'));
    await _failures.close();
  }
}
