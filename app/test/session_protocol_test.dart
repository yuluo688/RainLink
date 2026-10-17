import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/core/core_gateway.dart';
import 'package:rainlink/platform/core/session_protocol.dart';

void main() {
  Map<String, Object?> snapshot({String phase = 'connected'}) => {
        'phase': phase,
        'sessionId': 'session-a',
        'node': {'id': 'node-a', 'name': 'A', 'revision': 2},
        'mode': 'global',
        'configRevision': 'configuration-a',
        'systemProxy': true,
        'error': phase == 'failed' ? '核心状态无法确认' : '',
      };

  test('an unconfirmed core retains identity for safe disconnect', () {
    final state = SessionProtocol.decode(snapshot(phase: 'failed'));
    expect(state.phase, ConnectionPhase.failed);
    expect(state.active?.sessionId, 'session-a');
    expect(state.active?.target.revision, 2);
    expect(state.systemProxy, isTrue);
    expect(state.error, '核心状态无法确认');
  });

  test('TUN needs a typed state and an observed interface receipt', () {
    expect(SessionProtocol.decode(snapshot()).tun, isFalse);
    expect(
        SessionProtocol.decode(snapshot()
              ..addAll({'tun': true, 'tunInterface': 'RainLink-test'}))
            .tun,
        isTrue);
    for (final fields in [
      {'tun': 'true'},
      {'tun': true},
      {'tun': true, 'tunInterface': ''},
    ]) {
      expect(() => SessionProtocol.decode(snapshot()..addAll(fields)),
          throwsA(isA<CoreGatewayException>()));
    }
  });

  test('unsupported modes and phases cannot become confirmed connections', () {
    expect(() => SessionProtocol.decode(snapshot()..['mode'] = 'unsupported'),
        throwsA(isA<CoreGatewayException>()));
    expect(() => SessionProtocol.decode(snapshot(phase: 'starting')),
        throwsA(isA<CoreGatewayException>()));
  });

  test('idle with a recovery error remains actionable failure', () {
    final state =
        SessionProtocol.decode({'phase': 'idle', 'error': '系统代理恢复失败'});
    expect(state.phase, ConnectionPhase.failed);
    expect(state.active, isNull);
    expect(state.error, '系统代理恢复失败');
  });
}
