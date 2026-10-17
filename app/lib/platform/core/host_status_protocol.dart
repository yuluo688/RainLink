import 'dart:convert';

import '../../domain/core/core_gateway.dart';
import '../../domain/core/core_status.dart';

abstract final class HostStatusProtocol {
  /// Reject incomplete/unknown states rather than assuming the core is ready.
  static CoreStatus decode(String output) {
    final Object? value;
    try {
      value = jsonDecode(output);
    } on FormatException {
      throw const CoreGatewayException('invalid_response', '宿主响应无效或版本不兼容');
    }

    return switch (value) {
      {
        'protocolVersion': int protocolVersion,
        'host': {
          'version': String version,
          'platform': String platform,
          'arch': String arch,
        },
        'core': {'state': 'not_configured', 'version': null},
        'capabilities': {
          'connect': false,
          'systemProxy': false,
          'tun': false,
        },
      }
          when protocolVersion == 1 &&
              version.trim().isNotEmpty &&
              platform.trim().isNotEmpty &&
              arch.trim().isNotEmpty =>
        CoreStatus(
          hostAvailable: true,
          hostVersion: version,
          message: '桌面宿主已就绪，网络核心尚未接入',
        ),
      {
        'protocolVersion': 1,
        'host': {
          'version': String version,
          'platform': 'windows',
          'arch': String arch
        },
        'core': {'state': 'ready', 'version': String coreVersion},
        'capabilities': {'connect': true, 'systemProxy': true, 'tun': bool tun},
      }
          when version.trim().isNotEmpty &&
              arch.trim().isNotEmpty &&
              coreVersion.trim().isNotEmpty =>
        CoreStatus(
            hostAvailable: true,
            hostVersion: version,
            coreVersion: coreVersion,
            message:
                'sing-box $coreVersion · ${tun ? '系统代理与 TUN 已就绪' : '系统代理已就绪'}',
            capabilities:
                CoreCapabilities(connect: true, systemProxy: true, tun: tun)),
      {
        'protocolVersion': 1,
        'host': {
          'version': String version,
          'platform': 'linux',
          'arch': String arch,
        },
        'core': {'state': 'ready', 'version': String coreVersion},
        'capabilities': {
          'connect': true,
          'systemProxy': bool systemProxy,
          'tun': false,
        },
      }
          when version.trim().isNotEmpty &&
              arch.trim().isNotEmpty &&
              coreVersion.trim().isNotEmpty =>
        CoreStatus(
          hostAvailable: true,
          hostVersion: version,
          coreVersion: coreVersion,
          message:
              'sing-box $coreVersion · ${systemProxy ? '系统代理已就绪' : '本地代理端口已就绪'}',
          capabilities:
              CoreCapabilities(connect: true, systemProxy: systemProxy),
        ),
      _ => throw const CoreGatewayException('invalid_response', '宿主响应无效或版本不兼容'),
    };
  }
}
