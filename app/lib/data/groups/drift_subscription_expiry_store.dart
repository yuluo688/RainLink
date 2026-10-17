import 'dart:convert';

import '../../domain/core/runtime_settings.dart';
import '../../domain/groups/subscription_expiry.dart';
import '../database/app_database.dart';

class DriftSubscriptionExpiryStore implements SubscriptionExpiryStore {
  DriftSubscriptionExpiryStore(this.database);
  final AppDatabase database;
  static const preferenceKey = 'notifications.subscription_expiry';

  @override
  Future<Map<String, SubscriptionExpiryAlert>> load() async {
    final row = await (database.select(database.preferences)
          ..where((table) => table.key.equals(preferenceKey)))
        .getSingleOrNull();
    if (row == null) return {};
    try {
      final value = jsonDecode(row.value);
      if (value case {'version': 1, 'receipts': Map<String, Object?> items}) {
        final result = <String, SubscriptionExpiryAlert>{};
        for (final entry in items.entries) {
          if (entry.value
              case {'expiresAt': int at, 'stage': String stageName}) {
            final stage = SubscriptionExpiryStage.values
                .where((item) => item.name == stageName)
                .firstOrNull;
            if (entry.key.isEmpty || stage == null) break;
            result[entry.key] = SubscriptionExpiryAlert(
                groupId: entry.key,
                expiresAt: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
                stage: stage);
          } else {
            break;
          }
        }
        if (result.length == items.length) return result;
      }
    } on FormatException {
      throw const SettingsException('订阅提醒记录格式无效');
    } on RangeError {
      throw const SettingsException('订阅提醒记录格式无效');
    }
    throw const SettingsException('订阅提醒记录格式无效');
  }

  @override
  Future<void> record(List<SubscriptionExpiryAlert> alerts,
          {required Set<String> validGroupIds}) =>
      database.transaction(() async {
        final receipts = await load();
        final before = _encode(receipts);
        receipts.removeWhere((id, _) => !validGroupIds.contains(id));
        for (final alert in alerts) {
          if (validGroupIds.contains(alert.groupId) &&
              receipts[alert.groupId]?.covers(alert) != true) {
            receipts[alert.groupId] = alert;
          }
        }
        if (_encode(receipts) == before) return;
        if (receipts.isEmpty) {
          await (database.delete(database.preferences)
                ..where((table) => table.key.equals(preferenceKey)))
              .go();
        } else {
          await database.into(database.preferences).insertOnConflictUpdate(
              PreferencesCompanion.insert(
                  key: preferenceKey, value: _encode(receipts)));
        }
      });

  String _encode(Map<String, SubscriptionExpiryAlert> receipts) {
    final ids = receipts.keys.toList()..sort();
    return jsonEncode({
      'version': 1,
      'receipts': {
        for (final id in ids)
          id: {
            'expiresAt': receipts[id]?.expiresAt.millisecondsSinceEpoch,
            'stage': receipts[id]?.stage.name,
          },
      },
    });
  }
}
