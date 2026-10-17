import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/build_info.g.dart';
import '../../domain/updates/app_update.dart';

/// The candidate stays offline until the helper accepts its bootstrap and
/// first rendered frame. Failure allows the helper to restore the old database.
class WindowsUpdateStartup {
  WindowsUpdateStartup._(this.directory, this.token, this.version);
  final Directory directory;
  final String token;
  final String version;

  static Future<WindowsUpdateStartup?> detect(List<String> arguments) async {
    final flags =
        arguments.where((arg) => arg.startsWith('--rainlink-update-')).toList();
    if (flags.isEmpty) return null;
    if (!Platform.isWindows || flags.length != 2) {
      throw const UpdateException('更新启动参数无效');
    }
    String flag(String name) {
      final values = flags.where((arg) => arg.startsWith('$name=')).toList();
      if (values.length != 1) throw const UpdateException('更新启动参数无效');
      return values.single.substring(name.length + 1);
    }

    final directory = Directory(flag('--rainlink-update-health'));
    final token = flag('--rainlink-update-token');
    final target = p.dirname(Platform.resolvedExecutable);
    final marker = await _read(File(p.join(target, '.rainlink-updating')));
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(token)) {
      throw const UpdateException('更新启动凭证无效');
    }
    if (marker case {'token': String expected, 'work': String work}) {
      if (token != expected ||
          !p.isAbsolute(work) ||
          !p.equals(p.dirname(work), p.dirname(target)) ||
          !p.basename(work).startsWith('.rainlink-update-') ||
          !p.equals(directory.path, p.join(work, 'health'))) {
        throw const UpdateException('更新启动路径无效');
      }
    } else {
      throw const UpdateException('更新启动凭证无效');
    }
    for (var current = directory.path;
        current != p.dirname(current);
        current = p.dirname(current)) {
      if (await FileSystemEntity.type(current, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw const UpdateException('更新启动目录无效');
      }
    }
    final request = await _read(File(p.join(directory.path, 'request.json')));
    final support = await getApplicationSupportDirectory();
    if (request
        case {
          'token': String expectedToken,
          'version': String version,
          'executable': String executable,
          'support': String expectedSupport
        }
        when expectedToken == token &&
            version.replaceFirst(RegExp(r'^v'), '') == rainlinkVersion &&
            p.equals(executable, Platform.resolvedExecutable) &&
            p.equals(expectedSupport, support.path)) {
      return WindowsUpdateStartup._(directory, token, version);
    }
    throw const UpdateException('新版本与更新包不一致');
  }

  static Future<Object?> _read(File file) async {
    if (await file.length() > 8192) {
      throw const UpdateException('更新启动状态无效');
    }
    return jsonDecode(await file.readAsString());
  }

  Future<void> acknowledge() async {
    final ready = File(p.join(directory.path, 'ready.partial'));
    await ready.writeAsString(
        jsonEncode({'token': token, 'version': version, 'pid': pid}),
        flush: true);
    await ready.rename(p.join(directory.path, 'ready.json'));
    final accepted = File(p.join(directory.path, 'accepted.json'));
    final deadline = DateTime.now().add(const Duration(seconds: 55));
    while (DateTime.now().isBefore(deadline)) {
      if (await accepted.exists()) {
        if (await _read(accepted) case {'token': String expected}
            when expected == token) {
          await File(p.join(directory.path, 'consumed'))
              .writeAsString(token, flush: true);
          return;
        }
        throw const UpdateException('更新确认无效');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw const UpdateException('未能确认新版本启动，正在恢复原版本');
  }
}
