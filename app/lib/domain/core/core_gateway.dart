import '../connection/connection_models.dart';
import 'core_status.dart';

/// Platform boundary. UI code must not invoke processes or system proxy APIs.
abstract interface class CoreGateway {
  Future<CoreStatus> inspect();

  Future<ActiveConnectionSnapshot> connect(ConnectRequest request);

  Future<void> disconnect();

  void dispose();
}

class CoreGatewayException implements Exception {
  const CoreGatewayException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}
