import 'dart:io';

import 'advanced_config.dart';

enum DnsMode { system, encrypted, custom }

enum CoreLogLevel { debug, info, warn, error }

/// Settings for the next session. Live sessions keep their applied snapshot.
class CoreRuntimeSettings {
  const CoreRuntimeSettings({
    this.proxyPort = 0,
    this.dnsMode = DnsMode.system,
    this.resolver = 'https://dns.alidns.com/dns-query',
    this.bootstrapDns = '223.5.5.5',
    this.ipv6 = false,
    this.logLevel = CoreLogLevel.info,
    this.advanced = const AdvancedConfig.empty(),
  });

  final int proxyPort;
  final DnsMode dnsMode;
  final String resolver;
  final String bootstrapDns;
  final bool ipv6;
  final CoreLogLevel logLevel;
  final AdvancedConfig advanced;

  CoreRuntimeSettings copyWith({
    int? proxyPort,
    DnsMode? dnsMode,
    String? resolver,
    String? bootstrapDns,
    bool? ipv6,
    CoreLogLevel? logLevel,
    AdvancedConfig? advanced,
  }) =>
      CoreRuntimeSettings(
          proxyPort: proxyPort ?? this.proxyPort,
          dnsMode: dnsMode ?? this.dnsMode,
          resolver: resolver ?? this.resolver,
          bootstrapDns: bootstrapDns ?? this.bootstrapDns,
          ipv6: ipv6 ?? this.ipv6,
          logLevel: logLevel ?? this.logLevel,
          advanced: advanced ?? this.advanced);

  CoreRuntimeSettings validated() {
    if (proxyPort < 0 || proxyPort > 65535) {
      throw const SettingsException('混合端口应为 1–65535，或使用 0 自动分配');
    }
    if (resolver.length > 512 || bootstrapDns.length > 64) {
      throw const SettingsException('DNS 地址过长');
    }
    if (dnsMode != DnsMode.system) {
      if (InternetAddress.tryParse(bootstrapDns) == null) {
        throw const SettingsException('引导解析器应为 IPv4 或 IPv6 地址');
      }
      final uri = Uri.tryParse(resolver);
      final https = uri?.scheme == 'https';
      final udp = uri?.scheme == 'udp';
      if (uri == null ||
          !uri.hasAuthority ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          (!https && !udp) ||
          (dnsMode == DnsMode.encrypted && !https) ||
          (udp &&
              (InternetAddress.tryParse(uri.host) == null ||
                  (uri.path.isNotEmpty && uri.path != '/'))) ||
          (uri.hasPort && (uri.port < 1 || uri.port > 65535)) ||
          resolver.contains(RegExp(r'[\s\x00]'))) {
        throw const SettingsException(
            '解析器应为 HTTPS 地址或 udp://IP:端口，不包含认证、查询参数或片段');
      }
    }
    return this;
  }

  Map<String, Object?> toJson() => {
        'proxyPort': proxyPort,
        'dnsMode': dnsMode.name,
        'resolver': resolver,
        'bootstrapDns': bootstrapDns,
        'ipv6': ipv6,
        'logLevel': logLevel.name,
        'advanced': advanced.canonicalJson,
      };

  factory CoreRuntimeSettings.fromJson(Map<String, Object?> value) {
    if (value
        case {
          'proxyPort': int port,
          'dnsMode': String dns,
          'resolver': String resolver,
          'bootstrapDns': String bootstrap,
          'ipv6': bool ipv6,
          'logLevel': String level,
        }) {
      final modes = DnsMode.values.where((v) => v.name == dns);
      final levels = CoreLogLevel.values.where((v) => v.name == level);
      if (modes.isNotEmpty && levels.isNotEmpty) {
        return CoreRuntimeSettings(
                proxyPort: port,
                dnsMode: modes.first,
                resolver: resolver,
                bootstrapDns: bootstrap,
                ipv6: ipv6,
                logLevel: levels.first,
                advanced: value['advanced'] == null
                    ? const AdvancedConfig.empty()
                    : value['advanced'] is String
                        ? AdvancedConfig.parse(
                            value['advanced'] as String, ConfigFormat.json)
                        : throw const SettingsException('高级配置格式无效'))
            .validated();
      }
    }
    throw const SettingsException('网络设置格式无效');
  }
}

class DnsTestResult {
  const DnsTestResult({required this.addresses, required this.latency});
  final List<String> addresses;
  final int latency;

  factory DnsTestResult.fromJson(Map<String, Object?> value) {
    if (value
        case {'addresses': List<Object?> addresses, 'latency': int latency}
        when addresses.isNotEmpty &&
            addresses.length <= 256 &&
            addresses.every((address) =>
                address is String &&
                InternetAddress.tryParse(address) != null) &&
            latency >= 0 &&
            latency <= 60000) {
      return DnsTestResult(
          addresses: List.unmodifiable(addresses.cast<String>()),
          latency: latency);
    }
    throw const SettingsException('DNS 测试回执无效');
  }
}

abstract interface class RuntimeSettingsGateway {
  Future<void> validateRuntime(CoreRuntimeSettings settings);
  Future<void> cancelValidation();
  Future<DnsTestResult> testDns(CoreRuntimeSettings settings);
  Future<void> cancelDnsTest();
}

class SettingsException implements Exception {
  const SettingsException(this.message);
  final String message;
  @override
  String toString() => message;
}
