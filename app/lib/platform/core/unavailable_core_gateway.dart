import '../../domain/connection/connection_models.dart';
import '../../domain/core/core_gateway.dart';
import '../../domain/core/core_status.dart';

class UnavailableCoreGateway implements CoreGateway {
  const UnavailableCoreGateway(this.reason);

  final String reason;

  @override
  Future<CoreStatus> inspect() async => CoreStatus.unavailable(reason);

  @override
  Future<ActiveConnectionSnapshot> connect(ConnectRequest request) async {
    throw CoreGatewayException('core_unavailable', reason);
  }

  @override
  Future<void> disconnect() async {
    throw CoreGatewayException('core_unavailable', reason);
  }

  @override
  void dispose() {}
}
