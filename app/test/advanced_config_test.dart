import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/domain/core/advanced_config.dart';
import 'package:rainlink/domain/core/runtime_settings.dart';

void main() {
  test('YAML and JSON round-trip DNS policies and supplementary route rules',
      () {
    const source = '''
log:
  level: debug
  timestamp: true
dns:
  servers:
    - type: https
      tag: secure
      server: dns.example.test
      tls:
        enabled: true
  independent_cache: true
  cache_capacity: 4096
  rules:
    - domain_suffix: [example.com]
      server: system
route:
  rules:
    - ip_cidr: [192.0.2.0/24]
      port: [443]
      outbound: direct
''';
    final config = AdvancedConfig.parse(source, ConfigFormat.yaml);
    expect(config.overrides('dns', 'servers'), isTrue);
    expect(config.overrides('log', 'level'), isTrue);
    for (final format in ConfigFormat.values) {
      final roundTrip = AdvancedConfig.parse(config.render(format), format);
      expect(roundTrip, config);
    }
    final runtime = CoreRuntimeSettings(advanced: config);
    expect(CoreRuntimeSettings.fromJson(runtime.toJson()).advanced, config);
    final returned = config.fields;
    returned.clear();
    expect(config.overrides('dns'), isTrue);
    expect(const AdvancedConfig.empty().isEmpty, isTrue);
    expect(AdvancedConfig.parse('', ConfigFormat.yaml).isEmpty, isTrue);
    expect(AdvancedConfig.parse('# RainLink\n{}', ConfigFormat.yaml).isEmpty,
        isTrue);
    final legacy = const CoreRuntimeSettings().toJson()..remove('advanced');
    expect(CoreRuntimeSettings.fromJson(legacy).advanced.isEmpty, isTrue);
  });

  test('syntax errors and forbidden input cannot quote pasted credentials', () {
    for (final (source, format) in [
      ('log:\n  level: [fixture-secret', ConfigFormat.yaml),
      ('{"log": "fixture-secret"', ConfigFormat.json),
      ('{"log":{},"log":{"level":"fixture-secret"}}', ConfigFormat.json),
      ('log:\n  level: info\n  level: fixture-secret', ConfigFormat.yaml),
      ('log: &cyclic [*cyclic, fixture-secret]', ConfigFormat.yaml),
      ('[fixture-secret]', ConfigFormat.yaml),
      ('password: fixture-secret', ConfigFormat.yaml),
      ('outbounds: [{password: fixture-secret}]', ConfigFormat.yaml),
      ('log: {}\n---\npassword: fixture-secret', ConfigFormat.yaml),
    ]) {
      expect(
          () => AdvancedConfig.parse(source, format),
          throwsA(isA<SettingsException>().having((error) => error.toString(),
              'redacted diagnostic', isNot(contains('fixture-secret')))));
    }
  });

  test('bounded parser rejects expansion, deep nesting and oversized input',
      () {
    for (final source in [
      'log: {${List.filled(17000, 'a').join()}: true}',
      'log: ${List.filled(20, '[').join()}1${List.filled(20, ']').join()}',
      'dns: {servers: [${List.filled(2050, '1').join(',')}]}'
    ]) {
      expect(() => AdvancedConfig.parse(source, ConfigFormat.yaml),
          throwsA(isA<SettingsException>()));
    }
  });
}
