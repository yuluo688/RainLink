import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/export/data_export.dart';
import 'android_document_export_service.dart';

final dataExportServiceProvider = Provider<DataExportService>((ref) =>
    Platform.isAndroid
        ? AndroidDocumentExportService()
        : const FileDataExportService());

class FileDataExportService implements DataExportService {
  const FileDataExportService();

  @override
  Future<String?> save(
      {required String suggestedName, required String content}) async {
    final String path;
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final extension = p.extension(suggestedName).replaceFirst('.', '');
      final target = await getSaveLocation(
          suggestedName: suggestedName,
          acceptedTypeGroups: [
            XTypeGroup(
                label: '${extension.toUpperCase()} 文件', extensions: [extension])
          ]);
      if (target == null) return null;
      path = target.path;
    } else {
      final directory = await getApplicationDocumentsDirectory();
      path = p.join(directory.path, 'exports', p.basename(suggestedName));
      await File(path).parent.create(recursive: true);
    }
    try {
      await File(path).writeAsString(content, flush: true);
    } on FileSystemException {
      throw const FileSystemException('无法写入导出文件，请检查保存位置和磁盘空间');
    }
    return path;
  }
}
