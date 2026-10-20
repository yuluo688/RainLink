import '../connection/traffic_accounting.dart';
import 'core_gateway.dart';

/// Optional platform capability. A failed exact sample is never replaced with
/// a guess based on the user's selected node or currently active connections.
abstract interface class CoreTrafficGateway implements CoreGateway {
  Future<TrafficAccountingSnapshot> traffic({required String sessionId});
}
