import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/core/tun_service_controller.dart';
import 'package:rainlink/domain/core/core_gateway.dart';
import 'package:rainlink/domain/platform/tun_service.dart';
import 'package:rainlink/platform/core/host_session_client.dart';
import 'package:rainlink/platform/core/linux_tun_service_gateway.dart';

import 'support/fake_tun_service.dart';

class _Client extends HostSessionClient {
  _Client() : super('fixture');
  Map<String, Object?> response = const {};
  final methods = <String>[];
  @override
  Future<Map<String, Object?>> request(String method,
      [Map<String, Object?> payload = const {}]) async {
    methods.add(method);
    expect(payload, isEmpty);
    return response;
  }
}

void main() {
  test('does not authorize while an active session needs restoration',
      () async {
    final gateway = FakeTunService();
    final busy = <bool>[];
    final controller =
        TunServiceController(gateway, canChange: () => false, onBusy: busy.add);
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);
    await controller.perform(TunServiceAction.install);
    expect(gateway.changes, 0);
    expect(controller.state.error, contains('断开连接'));
    expect(busy, isEmpty);
  });

  for (final action in TunServiceAction.values) {
    test('${action.name} only succeeds after confirmed read-back', () async {
      final gateway = FakeTunService();
      final busy = <bool>[];
      final controller = TunServiceController(gateway,
          canChange: () => true, onBusy: busy.add);
      addTearDown(controller.dispose);
      await Future<void>.delayed(Duration.zero);
      await controller.perform(action);
      expect(controller.state.error, isEmpty);
      expect(controller.state.message, contains('已重新检查'));
      expect(gateway.inspections, 2);
      expect(busy, [true, false]);
    });
  }

  test('a successful reply with unchanged files is not success', () async {
    final gateway = FakeTunService()..apply = false;
    final controller =
        TunServiceController(gateway, canChange: () => true, onBusy: (_) {});
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);
    await controller.perform(TunServiceAction.install);
    expect(controller.state.error, contains('回读确认'));
    expect(controller.state.message, isEmpty);
  });

  test('cancel acknowledgement keeps the lease until real completion',
      () async {
    final gateway = FakeTunService()
      ..operation = Completer<void>()
      ..failure = const CoreGatewayException('cancelled', '已取消授权');
    final busy = <bool>[];
    final controller =
        TunServiceController(gateway, canChange: () => true, onBusy: busy.add);
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);
    final installing = controller.perform(TunServiceAction.install);
    await controller.cancel();
    expect(controller.state.busy, isTrue);
    expect(controller.state.cancelling, isTrue);
    expect(busy, [true]);
    await controller.perform(TunServiceAction.uninstall);
    expect(gateway.changes, 1);
    expect(gateway.cancellations, 1);
    gateway.operation!.complete();
    await installing;
    expect(controller.state.busy, isFalse);
    expect(controller.state.error, '已取消授权');
    expect(controller.state.message, isEmpty);
    expect(busy, [true, false]);
  });

  test('failed read-back cannot reuse a stale ready state', () async {
    final gateway = FakeTunService()..operation = Completer<void>();
    final controller =
        TunServiceController(gateway, canChange: () => true, onBusy: (_) {});
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);
    final installing = controller.perform(TunServiceAction.install);
    gateway.inspectionFailure =
        const CoreGatewayException('host_exited', '检查失败');
    gateway.operation!.complete();
    await installing;
    expect(controller.state.status, isNull);
    expect(controller.state.error, '检查失败');
    expect(controller.state.message, isEmpty);
  });

  test('transport validates state and fixed completion/cancel acknowledgements',
      () async {
    final client = _Client();
    final gateway = LinuxTunServiceGateway('fixture', client: client);
    client.response = {
      'protocolVersion': 1,
      'state': 'missing',
      'canManage': true,
      'enabled': false,
      'active': false,
      'message': '尚未安装'
    };
    expect((await gateway.inspect()).state, TunServiceState.missing);
    client.response = {...client.response, 'active': true};
    await expectLater(gateway.inspect(), throwsA(isA<CoreGatewayException>()));
    client.response = {'completed': true};
    await gateway.change(TunServiceAction.install);
    client.response = {'requested': true};
    await gateway.cancel();
    client.response = {};
    await expectLater(gateway.change(TunServiceAction.recover),
        throwsA(isA<CoreGatewayException>()));
    await expectLater(gateway.cancel(), throwsA(isA<CoreGatewayException>()));
    expect(client.methods,
        ['status', 'status', 'install', 'cancel', 'recover', 'cancel']);
  });
}
