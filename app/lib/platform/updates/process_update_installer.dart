import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/updates/app_update.dart';

/// Runs a copied helper outside the installation so its own EXE can be updated.
class ProcessUpdateInstaller implements UpdateInstaller {
  ProcessUpdateInstaller({
    String? executable,
    Future<Directory> Function()? supportDirectory,
    Future<Directory> Function()? cacheDirectory,
  })  : _executable = executable ?? Platform.resolvedExecutable,
        _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
        _cacheDirectory = cacheDirectory ?? getApplicationCacheDirectory;

  final String _executable;
  final Future<Directory> Function() _supportDirectory;
  final Future<Directory> Function() _cacheDirectory;

  @override
  Future<PreparedUpdate> prepare(
      DownloadedUpdate update, UpdateCancellation cancellation) async {
    cancellation.check();
    final digest = update.release.asset?.sha256;
    if (digest == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const UpdateException('更新包缺少可信校验信息');
    }
    Directory? helperDirectory;
    _ProcessPreparedUpdate? prepared;
    try {
      final target = p.dirname(_executable);
      final helper = File(p.join(target, 'rainlink-updater.exe'));
      final manifestFile = File(p.join(target, 'rainlink-bundle.json'));
      if (await manifestFile.length() > 2 * 1024 * 1024) {
        throw const UpdateException('当前安装的文件清单无效，请重新解压完整安装包');
      }
      final Object? manifest = jsonDecode(await manifestFile.readAsString());
      String? helperHash;
      if (manifest
          case {
            'schema': int schema,
            'product': 'RainLink',
            'platform': 'windows-x64',
            'files': List<Object?> files
          } when schema == 1 || schema == 2) {
        for (final file in files) {
          if (file
              case {'path': 'rainlink-updater.exe', 'sha256': String hash}) {
            helperHash = hash;
          }
        }
      }
      if (helperHash == null ||
          (await sha256.bind(helper.openRead()).first).toString() !=
              helperHash) {
        throw const UpdateException('安装程序校验失败，请重新解压完整安装包');
      }
      cancellation.check();
      final support = await _supportDirectory();
      final cache = await _cacheDirectory();
      final updates = await Directory(p.join(cache.path, 'updates'))
          .create(recursive: true);
      helperDirectory = await updates.createTemp('helper-');
      final copied = await helper
          .copy(p.join(helperDirectory.path, 'rainlink-updater.exe'));
      if ((await sha256.bind(copied.openRead()).first).toString() !=
          helperHash) {
        throw const UpdateException('无法校验临时安装程序');
      }
      cancellation.check();
      final process = await Process.start(copied.path, const [],
          workingDirectory: helperDirectory.path,
          mode: ProcessStartMode.detachedWithStdio);
      prepared = _ProcessPreparedUpdate(process, helperDirectory);
      cancellation.bind(prepared.requestAbort);
      process.stdin.writeln(jsonEncode({
        'target': p.normalize(p.absolute(target)),
        'support': p.normalize(p.absolute(support.path)),
        'archive': p.normalize(p.absolute(update.path)),
        'sha256': digest,
        'version': update.release.tag,
        'parent': pid,
      }));
      await process.stdin.flush();
      await prepared.expect('ready', const Duration(minutes: 2));
      cancellation.check();
      // Preparation cancellation is no longer allowed once the window starts
      // its exit sequence. The guard owns commit/abort from this point.
      cancellation.bind(null);
      return prepared;
    } on Exception {
      cancellation.bind(null);
      if (prepared != null) {
        await prepared.abort();
      } else if (helperDirectory != null && await helperDirectory.exists()) {
        await helperDirectory.delete(recursive: true);
      }
      cancellation.check();
      throw const UpdateException('无法准备更新，请检查安装目录权限、完整性与磁盘空间后重试');
    }
  }
}

class _ProcessPreparedUpdate implements PreparedUpdate {
  _ProcessPreparedUpdate(this.process, this.directory) {
    _stdout = process.stdout.listen(
        (bytes) {
          _bytes += bytes.length;
          if (_bytes > 4096) {
            _failure();
            return;
          }
          _buffer += utf8.decode(bytes, allowMalformed: true);
          for (var newline = _buffer.indexOf('\n');
              newline >= 0;
              newline = _buffer.indexOf('\n')) {
            final line = _buffer.substring(0, newline).trim();
            _buffer = _buffer.substring(newline + 1);
            try {
              final Object? decoded = jsonDecode(line);
              if (decoded case {'status': String status}
                  when ['ready', 'committed', 'aborted', 'failed']
                      .contains(status)) {
                _statuses.add(status);
              } else {
                _failure();
              }
            } on FormatException {
              _failure();
            }
            _signal();
          }
        },
        onError: (Object _, StackTrace __) => _failure(),
        onDone: () {
          _finished = true;
          _signal();
        });
    // The helper emits no diagnostic details; drain stderr to avoid deadlock.
    _stderr = process.stderr
        .listen((_) {}, onError: (Object _, StackTrace __) => _failure());
  }
  final Process process;
  final Directory directory;
  late final StreamSubscription<List<int>> _stdout;
  late final StreamSubscription<List<int>> _stderr;
  final _statuses = <String>{};
  String _buffer = '';
  int _bytes = 0;
  bool _finished = false;
  bool _aborting = false;
  Future<void>? _abort;
  Completer<void>? _changed;

  void _signal() {
    final changed = _changed;
    _changed = null;
    if (changed != null && !changed.isCompleted) changed.complete();
  }

  void _failure() {
    _statuses.add('failed');
    _signal();
  }

  Future<void> expect(String status, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (!_statuses.contains(status)) {
      if (_statuses.contains('failed') || _finished) {
        throw const UpdateException('安装程序未能完成交接');
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw const UpdateException('安装交接超时，当前应用保持打开');
      }
      _changed ??= Completer<void>();
      try {
        await _changed?.future.timeout(remaining);
      } on TimeoutException {
        throw const UpdateException('安装交接超时，当前应用保持打开');
      }
    }
  }

  void requestAbort() {
    if (_finished || _aborting) return;
    _aborting = true;
    try {
      process.stdin.writeln('{"command":"abort"}');
    } on IOException {
      _failure();
    } on StateError {
      _failure();
    }
  }

  @override
  Future<void> commit() async {
    if (_aborting) throw const UpdateCancelled();
    process.stdin.writeln('{"command":"commit"}');
    await process.stdin.flush();
    await expect('committed', const Duration(seconds: 10));
    // Keep the pipe open until the app exits: a failed window close can still
    // send abort while the helper is waiting on this process's retained handle.
  }

  @override
  Future<void> abort() => _abort ??= _abortAndClean();

  Future<void> _abortAndClean() async {
    requestAbort();
    try {
      if (!_finished && !_statuses.contains('failed')) {
        await process.stdin.flush();
        await expect('aborted', const Duration(seconds: 10));
      }
      await process.stdin.close();
      // The helper acknowledges before exiting; wait for EOF before deleting
      // its mapped EXE. Never kill an unrelated process by a reused PID.
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!_finished && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      if (!_finished) throw const UpdateException('安装程序尚未退出，请稍后重试');
      await _stdout.cancel();
      await _stderr.cancel();
      if (await directory.exists()) await directory.delete(recursive: true);
    } on Exception {
      throw const UpdateException('准备操作已停止，但安装缓存未能完全清理，请稍后重试');
    }
  }
}

/// A fixed, sanitized receipt survives rollback and is consumed once.
Future<String?> readUpdateReceipt({
  Future<Directory> Function()? supportDirectory,
}) async {
  final support = await (supportDirectory ?? getApplicationSupportDirectory)();
  final receipt = File(p.join(support.path, 'update-result.json'));
  if (!await receipt.exists()) return null;
  try {
    if (await receipt.length() > 4096) {
      throw const UpdateException('上次更新回执无效，请检查安装目录');
    }
    final Object? value = jsonDecode(await receipt.readAsString());
    final message = switch (value) {
      {'status': 'installed'} => '应用更新已安装，新版本已通过启动检查。',
      {'status': 'rolled-back'} => '新版本启动失败，已恢复原版本和升级前的数据。',
      {'status': 'interrupted-restored'} => '上次更新意外中断，已恢复原版本和升级前的数据。',
      {'status': 'recovery-required'} => '上次更新未能完成恢复，备份已保留，请检查安装目录。',
      {'status': 'failed'} => '更新未能开始，已保留原版本。',
      _ => '上次更新回执无效，请检查安装目录。',
    };
    await receipt.delete();
    return message;
  } on UpdateException {
    rethrow;
  } on Exception {
    throw const UpdateException('无法读取上次更新结果，请检查本地存储');
  }
}
