import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/export/data_export.dart';

/// Streams a private temporary file into Android's system document picker.
/// A content URI is returned only after the chosen provider finishes writing.
class AndroidDocumentExportService implements DataExportService {
  AndroidDocumentExportService({
    MethodChannel? channel,
    Future<Directory> Function()? temporaryDirectory,
    this.timeout = const Duration(minutes: 5),
  })  : _channel = channel ?? const MethodChannel('rainlink/documents'),
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final MethodChannel _channel;
  final Future<Directory> Function() _temporaryDirectory;
  final Duration timeout;
  static const maxCharacters = 16 * 1024 * 1024;

  @override
  Future<String?> save(
      {required String suggestedName, required String content}) async {
    final name = p.basename(suggestedName);
    if (name != suggestedName ||
        name.isEmpty ||
        name.length > 180 ||
        name.contains(RegExp(r'[\x00-\x1f\\/]')) ||
        content.length > maxCharacters) {
      throw const FileSystemException('导出文件名称或内容大小无效');
    }
    final mime = switch (p.extension(name).toLowerCase()) {
      '.csv' => 'text/csv',
      '.json' => 'application/json',
      '.yaml' || '.yml' => 'application/yaml',
      '.txt' => 'text/plain',
      _ => throw const FileSystemException('不支持此导出文件格式'),
    };
    final root = Directory(
        p.join((await _temporaryDirectory()).path, 'rainlink-exports'));
    await root.create(recursive: true);
    final temporary = await root.createTemp('document-');
    final requestId = p.basename(temporary.path);
    try {
      final source = File(p.join(temporary.path, 'content'));
      await source.writeAsString(content, flush: true);
      final result = await _channel.invokeMethod<String>('saveDocument', {
        'requestId': requestId,
        'sourcePath': source.path,
        'suggestedName': name,
        'mimeType': mime,
      }).timeout(timeout);
      if (result == null) return null;
      final uri = Uri.tryParse(result);
      if (uri == null || uri.scheme != 'content' || uri.authority.isEmpty) {
        throw const FileSystemException('系统未返回有效的文件保存位置');
      }
      return result;
    } on TimeoutException {
      try {
        await _channel.invokeMethod<void>('cancelExport', {
          'requestId': requestId,
        }).timeout(const Duration(seconds: 2));
      } on Exception {
        throw const FileSystemException('保存等待超时，取消未确认，请关闭文件选择器后重试');
      }
      throw const FileSystemException('保存等待超时，已取消导出');
    } on PlatformException catch (error) {
      throw FileSystemException(error.message ?? '无法保存导出文件，请重试');
    } on MissingPluginException {
      throw const FileSystemException('系统文件保存服务不可用，请重新打开应用');
    } finally {
      await temporary.delete(recursive: true);
    }
  }
}
