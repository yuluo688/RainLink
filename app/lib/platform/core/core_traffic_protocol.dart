import '../../domain/connection/traffic_accounting.dart';
import '../../domain/connection/traffic_repository.dart';
import '../../domain/core/core_gateway.dart';

abstract final class CoreTrafficProtocol {
  static TrafficAccountingSnapshot parse(
    Map<String, Object?> data, {
    required String sessionId,
  }) {
    try {
      int number(Map<String, Object?> row, String key) {
        final value = row[key];
        if (value is! int || value < 0 || value > maximumTrafficCounter) {
          throw const FormatException();
        }
        return value;
      }

      String text(Map<String, Object?> row, String key) {
        final value = row[key];
        if (value is! String || value.length > 512) {
          throw const FormatException();
        }
        return value;
      }

      List<TrafficCounter> rows(String key, int limit) {
        final source = data[key];
        if (source is! List<Object?> || source.length > limit) {
          throw const FormatException();
        }
        return List.unmodifiable(
          source.map((row) {
            if (row is! Map<String, Object?>) throw const FormatException();
            return TrafficCounter(
              target: TrafficAttribution(
                id: text(row, 'id'),
                kind: text(row, 'kind'),
                name: text(row, 'name'),
              ),
              upload: number(row, 'upload'),
              download: number(row, 'download'),
            );
          }),
        );
      }

      if (data['version'] != 1 || data['limited'] is! bool) {
        throw const FormatException();
      }
      final at = number(data, 'sampledAt');
      if (at > 8640000000000000) throw const FormatException();
      final snapshot = TrafficAccountingSnapshot(
        sessionId: text(data, 'sessionId'),
        epoch: text(data, 'epoch'),
        sampledAt: DateTime.fromMillisecondsSinceEpoch(at),
        upload: number(data, 'uploadTotal'),
        download: number(data, 'downloadTotal'),
        limited: data['limited'] == true,
        targets: rows('targets', 35),
        applications: rows('applications', 128),
      );
      snapshot.validate();
      if (snapshot.sessionId != sessionId) {
        throw const CoreGatewayException('session_changed', '连接会话已改变，请刷新');
      }
      return snapshot;
    } on FormatException {
      throw const CoreGatewayException('invalid_response', '核心流量响应无效，本次统计未保存');
    }
  }
}
