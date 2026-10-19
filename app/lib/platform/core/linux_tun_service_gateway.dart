import '../../domain/core/core_gateway.dart';
import '../../domain/platform/tun_service.dart';
import 'host_session_client.dart';

class LinuxTunServiceGateway implements TunServiceGateway {
  LinuxTunServiceGateway(String executable, {HostSessionClient? client})
      : _client = client ??
            HostSessionClient(executable,
                arguments: const ['manage-tun-service'],
                requestTimeout: const Duration(minutes: 9));

  final HostSessionClient _client;

  @override
  Future<TunServiceStatus> inspect() async {
    final result = await _client.request('status');
    if (result
        case {
          'protocolVersion': 1,
          'state': String state,
          'canManage': bool canManage,
          'enabled': bool enabled,
          'active': bool active,
          'message': String message,
        } when message.isNotEmpty && message.length <= 256) {
      final parsed =
          TunServiceState.values.where((v) => v.name == state).firstOrNull;
      if (parsed != null &&
          (parsed != TunServiceState.missing || (!enabled && !active)) &&
          (parsed != TunServiceState.unavailable || !canManage)) {
        return TunServiceStatus(
            state: parsed,
            canManage: canManage,
            enabled: enabled,
            active: active,
            message: message);
      }
    }
    throw const CoreGatewayException('invalid_response', '权限服务状态无效，请更新应用或重试');
  }

  @override
  Future<void> change(TunServiceAction action) async {
    final result = await _client.request(action.name);
    if (result case {'completed': true}) return;
    throw const CoreGatewayException('invalid_response', '未收到服务管理完成确认');
  }

  @override
  Future<void> cancel() async {
    final result = await _client.request('cancel');
    if (result case {'requested': true}) return;
    throw const CoreGatewayException('invalid_response', '未收到取消请求确认');
  }

  @override
  Future<void> close() => _client.close();
}
