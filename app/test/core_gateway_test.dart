import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/core/core_gateway.dart';
import 'package:rainlink/platform/core/host_status_protocol.dart';
import 'package:rainlink/platform/core/unavailable_core_gateway.dart';

Map<String, Object?> statusPayload() => {
  'protocolVersion': 1,
  'host': {'version': '0.1.0', 'platform': 'windows', 'arch': 'amd64'},
  'core': {'state': 'not_configured', 'version': null},
  'capabilities': {'connect': false, 'systemProxy': false, 'tun': false},
};

void main() {
  test('macOS local core does not advertise unimplemented capture', () {
    for (final arch in ['arm64', 'amd64']) {
      final payload =
          statusPayload()
            ..['host'] = {
              'version': '0.1.0',
              'platform': 'darwin',
              'arch': arch,
            }
            ..['core'] = {'state': 'ready', 'version': '1.12.25-rainlink.1'}
            ..['capabilities'] = {
              'connect': true,
              'systemProxy': false,
              'tun': false,
            };
      final status = HostStatusProtocol.decode(jsonEncode(payload));
      expect(status.capabilities.connect, isTrue);
      expect(status.capabilities.systemProxy, isFalse);
      expect(status.capabilities.tun, isFalse);
      expect(status.message, contains('本地代理端口'));
      for (final unsupported in [
        {'connect': true, 'systemProxy': true, 'tun': false},
        {'connect': true, 'systemProxy': false, 'tun': true},
      ]) {
        payload['capabilities'] = unsupported;
        expect(
          () => HostStatusProtocol.decode(jsonEncode(payload)),
          throwsA(isA<CoreGatewayException>()),
        );
      }
    }
  });

  test('Linux local core keeps unavailable capture capabilities disabled', () {
    final payload =
        statusPayload()
          ..['host'] = {
            'version': '0.1.0',
            'platform': 'linux',
            'arch': 'amd64',
          }
          ..['core'] = {'state': 'ready', 'version': '1.12.25-rainlink.1'}
          ..['capabilities'] = {
            'connect': true,
            'systemProxy': false,
            'tun': false,
          };
    final status = HostStatusProtocol.decode(jsonEncode(payload));
    expect(status.capabilities.connect, isTrue);
    expect(status.capabilities.systemProxy, isFalse);
    expect(status.capabilities.tun, isFalse);
    expect(status.message, contains('本地代理端口'));
  });
  for (final systemProxy in [false, true]) {
    test('Linux accepts observed TUN with system proxy $systemProxy', () {
      final payload =
          statusPayload()
            ..['host'] = {
              'version': '0.1.0',
              'platform': 'linux',
              'arch': 'amd64',
            }
            ..['core'] = {'state': 'ready', 'version': '1.12.25-rainlink.1'}
            ..['capabilities'] = {
              'connect': true,
              'systemProxy': systemProxy,
              'tun': true,
            };
      final status = HostStatusProtocol.decode(jsonEncode(payload));
      expect(status.capabilities.connect, isTrue);
      expect(status.capabilities.systemProxy, systemProxy);
      expect(status.capabilities.tun, isTrue);
      expect(status.message, contains('TUN 已就绪'));
      payload['capabilities'] = {
        'connect': true,
        'systemProxy': systemProxy,
        'tun': 'true',
      };
      expect(
        () => HostStatusProtocol.decode(jsonEncode(payload)),
        throwsA(isA<CoreGatewayException>()),
      );
    });
  }
  test('Linux desktop capability enables only the observed system proxy', () {
    final payload =
        statusPayload()
          ..['host'] = {
            'version': '0.1.0',
            'platform': 'linux',
            'arch': 'amd64',
          }
          ..['core'] = {'state': 'ready', 'version': '1.12.25-rainlink.1'}
          ..['capabilities'] = {
            'connect': true,
            'systemProxy': true,
            'tun': false,
          };
    final status = HostStatusProtocol.decode(jsonEncode(payload));
    expect(status.capabilities.connect, isTrue);
    expect(status.capabilities.systemProxy, isTrue);
    expect(status.capabilities.tun, isFalse);
    expect(status.message, contains('系统代理已就绪'));
  });
  test('ready Windows host reports its observed TUN capability', () {
    final payload =
        statusPayload()
          ..['core'] = {'state': 'ready', 'version': '1.12.25-rainlink.1'}
          ..['capabilities'] = {
            'connect': true,
            'systemProxy': true,
            'tun': true,
          };
    final status = HostStatusProtocol.decode(jsonEncode(payload));
    expect(status.capabilities.tun, isTrue);
    expect(status.capabilities.connect, isTrue);
  });
  test('host availability does not imply core capabilities', () {
    final status = HostStatusProtocol.decode(jsonEncode(statusPayload()));
    expect(status.hostAvailable, isTrue);
    expect(status.capabilities.connect, isFalse);
    expect(status.capabilities.systemProxy, isFalse);
    expect(status.capabilities.tun, isFalse);
    expect(status.coreVersion, isNull);
  });

  test('malformed or incompatible status fails closed', () {
    final futureProtocol = statusPayload()..['protocolVersion'] = 2;
    final unsupportedCore =
        statusPayload()..['core'] = {'state': 'ready', 'version': 'unknown'};
    final unsupportedCapability =
        statusPayload()
          ..['capabilities'] = {
            'connect': true,
            'systemProxy': false,
            'tun': false,
          };
    final incompleteStatus = statusPayload()..remove('capabilities');
    final incompleteHost = statusPayload()..['host'] = {'version': '0.1.0'};
    final emptyVersion =
        statusPayload()
          ..['host'] = {
            'version': '  ',
            'platform': 'windows',
            'arch': 'amd64',
          };
    final wrongHostType =
        statusPayload()
          ..['host'] = {'version': '0.1.0', 'platform': 1, 'arch': 'amd64'};
    final missingCoreVersion =
        statusPayload()..['core'] = {'state': 'not_configured'};
    final nonIntegerProtocol = statusPayload()..['protocolVersion'] = 1.0;
    for (final payload in [
      futureProtocol,
      unsupportedCore,
      unsupportedCapability,
      incompleteStatus,
      incompleteHost,
      emptyVersion,
      wrongHostType,
      missingCoreVersion,
      nonIntegerProtocol,
    ]) {
      expect(
        () => HostStatusProtocol.decode(jsonEncode(payload)),
        throwsA(isA<CoreGatewayException>()),
      );
    }
    expect(
      () => HostStatusProtocol.decode('invalid JSON'),
      throwsA(isA<CoreGatewayException>()),
    );
  });

  test('invalid top-level JSON values fail with a domain exception', () {
    for (final output in ['null', '[]', '42', '"status"', '{}']) {
      expect(
        () => HostStatusProtocol.decode(output),
        throwsA(isA<CoreGatewayException>()),
      );
    }
  });

  test(
    'unavailable adapters cannot report successful connection commands',
    () async {
      const gateway = UnavailableCoreGateway('未接入');
      const request = ConnectRequest(
        target: ProxyTarget(id: 'test', name: 'test', revision: 1),
        mode: ProxyMode.rule,
      );
      await expectLater(
        gateway.connect(request),
        throwsA(isA<CoreGatewayException>()),
      );
      await expectLater(
        gateway.disconnect(),
        throwsA(isA<CoreGatewayException>()),
      );
    },
  );

  test('selection preserves active snapshot and signals pending changes', () {
    const original = ProxyTarget(id: 'node-a', name: 'A', revision: 1);
    const active = ActiveConnectionSnapshot(
      sessionId: 'session',
      target: original,
      mode: ProxyMode.rule,
      configRevision: 'revision-a',
    );
    const state = ConnectionSessionState(
      phase: ConnectionPhase.connected,
      selectedTarget: original,
      activeSnapshot: active,
    );
    expect(state.pendingApply, isFalse);
    final changed = state.select(
      const ProxyTarget(id: 'node-b', name: 'B', revision: 1),
    );
    expect(changed.activeSnapshot, same(active));
    expect(changed.pendingApply, isTrue);
    expect(
      state
          .select(const ProxyTarget(id: 'node-a', name: 'A', revision: 2))
          .pendingApply,
      isTrue,
    );
    expect(state.select(null).pendingApply, isTrue);
    expect(
      const ConnectionSessionState().select(original).activeSnapshot,
      isNull,
    );
  });
}
