import 'dart:convert';

import '../../domain/updates/app_update.dart';
import '../database/app_database.dart';

class DriftUpdatePreferences implements UpdatePreferencesRepository {
  DriftUpdatePreferences(this.database);
  final AppDatabase database;
  static const preferenceKey = 'updates.preferences';
  @override
  Future<UpdatePreferences> load() async {
    final row = await (database.select(database.preferences)
          ..where((p) => p.key.equals(preferenceKey)))
        .getSingleOrNull();
    if (row == null) return const UpdatePreferences();
    try {
      final value = jsonDecode(row.value);
      if (value is Map<String, Object?>) {
        return UpdatePreferences.fromJson(value);
      }
    } on FormatException {
      throw const UpdateException('更新偏好损坏，无法读取');
    }
    throw const UpdateException('更新偏好格式无效');
  }

  @override
  Future<void> save(UpdatePreferences preferences) => database
      .into(database.preferences)
      .insertOnConflictUpdate(PreferencesCompanion.insert(
          key: preferenceKey, value: jsonEncode(preferences.toJson())));
}
