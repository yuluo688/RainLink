import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';

Future<AppDatabase> openAppDatabase() async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  return AppDatabase(
    NativeDatabase.createInBackground(
        File(p.join(directory.path, 'rainlink.sqlite'))),
  );
}
