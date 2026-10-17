import '../../domain/core/runtime_settings.dart';
import 'host_session_client.dart';

/// Disposable diagnostics cannot change an interactive session or system DNS.
class DesktopSettingsGateway implements RuntimeSettingsGateway {
  DesktopSettingsGateway(this.executablePath);
  final String executablePath;
  final _clients = <HostSessionClient, String>{};
  bool _closed = false;

  Future<Map<String, Object?>> _request(
      String method, CoreRuntimeSettings settings) async {
    if (_closed) throw const SettingsException('设置接口已关闭');
    final client = HostSessionClient(executablePath,
        arguments: const ['serve-test'],
        requestTimeout: const Duration(seconds: 12));
    _clients[client] = method;
    try {
      return await client.request(method, settings.validated().toJson());
    } finally {
      await client.close();
      _clients.remove(client);
    }
  }

  @override
  Future<void> validateRuntime(CoreRuntimeSettings settings) async {
    await _request('validateSettings', settings);
  }

  @override
  Future<DnsTestResult> testDns(CoreRuntimeSettings settings) async {
    final value = await _request('testDNS', settings);
    return DnsTestResult.fromJson(value);
  }

  @override
  Future<void> cancelDnsTest() async {
    await _cancel('testDNS');
  }

  @override
  Future<void> cancelValidation() => _cancel('validateSettings');

  Future<void> _cancel(String method) async => Future.wait([
        for (final entry in _clients.entries.toList())
          if (entry.value == method) entry.key.close()
      ]);

  Future<void> close() async {
    _closed = true;
    await Future.wait(
        [for (final client in _clients.keys.toList()) client.close()]);
  }
}
