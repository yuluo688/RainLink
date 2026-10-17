import '../connection/connection_models.dart';
import 'core_gateway.dart';

class TrafficRateSample {
  const TrafficRateSample(
      {required this.at, required this.upload, required this.download});
  final DateTime at;
  final int upload;
  final int download;
}

class SessionTelemetry {
  const SessionTelemetry(
      {this.upload = 0,
      this.download = 0,
      this.uploadTotal = 0,
      this.downloadTotal = 0,
      this.ip = '',
      this.country = '',
      this.countryCode = '',
      this.latency,
      this.latencyAt = 0,
      this.probeError = ''});
  final int upload;
  final int download;
  final int uploadTotal;
  final int downloadTotal;
  final String ip;
  final String country;
  final String countryCode;
  final int? latency;
  final int latencyAt;
  final String probeError;
}

class SessionObservation {
  const SessionObservation(
      {required this.phase,
      this.active,
      this.systemProxy = false,
      this.tun = false,
      this.error = '',
      this.telemetry});
  final ConnectionPhase phase;
  final ActiveConnectionSnapshot? active;
  final bool systemProxy;
  final bool tun;
  final String error;
  final SessionTelemetry? telemetry;
}

/// A native service can outlive the UI. Recovery includes its original encrypted
/// domain request, so restarting never substitutes the current UI selection.
class RecoveredSession {
  const RecoveredSession(this.observation, this.request);
  final SessionObservation observation;
  final ConnectRequest? request;
}

abstract interface class SessionRecoveryGateway {
  Future<RecoveredSession> recoverSession();
}

/// Optional session operations, unavailable until a platform implements them.
abstract interface class SessionGateway implements CoreGateway {
  Stream<Exception> get failures;
  Future<SessionObservation> observe();
  Future<void> setMode(ProxyMode mode);
  Future<void> setSystemProxy(bool enabled);
  Future<void> probe();
  Future<void> cancel();
  Future<void> close();
}
