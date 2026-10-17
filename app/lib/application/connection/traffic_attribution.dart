import '../../domain/connection/connection_models.dart';
import '../../domain/connection/traffic_repository.dart';

/// Existing flows can keep their old route after a live mode change. Once a
/// session becomes mixed, aggregate counters cannot identify a single target.
class SessionTrafficAttribution {
  ActiveConnectionSnapshot? _started;
  bool _mixed = true;

  void start(ActiveConnectionSnapshot active) {
    _started = active;
    _mixed = active.mode == ProxyMode.rule;
  }

  void invalidate() => _mixed = true;

  TrafficAttribution resolve(ActiveConnectionSnapshot active) {
    final started = _started;
    if (started == null ||
        active.sessionId != started.sessionId ||
        active.mode != started.mode ||
        active.target.id != started.target.id ||
        active.target.kind != started.target.kind ||
        active.target.revision != started.target.revision) {
      _mixed = true;
    }
    if (_mixed) return TrafficAttribution.unassigned;
    if (active.mode == ProxyMode.direct) return TrafficAttribution.direct;
    return TrafficAttribution(
        id: active.target.id,
        name: active.target.name,
        kind: active.target.kind);
  }
}
