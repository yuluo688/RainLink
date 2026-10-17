import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'runtime_settings.dart';

enum ConfigFormat { yaml, json }

/// An immutable patch. The host owns the field allowlist and
/// validates the merged configuration with the bundled core before use.
class AdvancedConfig {
  const AdvancedConfig.empty() : canonicalJson = '{}';
  const AdvancedConfig._(this.canonicalJson);

  static const maxBytes = 16384;
  static const maxDepth = 12;
  static const maxValues = 2048;
  final String canonicalJson;
  bool get isEmpty => canonicalJson == '{}';

  factory AdvancedConfig.parse(String source, ConfigFormat format) {
    if (utf8.encode(source).length > maxBytes) {
      throw const SettingsException('高级配置不能超过 16 KB');
    }
    if (source.trim().isEmpty) return const AdvancedConfig.empty();
    if (format == ConfigFormat.json) {
      try {
        jsonDecode(source);
      } on FormatException catch (error) {
        final before = source.substring(0, error.offset ?? 0);
        throw SettingsException(
            '第 ${'\n'.allMatches(before).length + 1} 行：JSON 语法无效');
      }
    }
    try {
      // The YAML parser also rejects duplicate JSON keys. Its diagnostics are
      // never displayed verbatim, since they can quote pasted credentials.
      final document = loadYamlDocument(source);
      final visited = <YamlNode>{};
      var count = 0;
      Object? plain(YamlNode node, int depth) {
        if (depth > maxDepth || ++count > maxValues || !visited.add(node)) {
          throw const SettingsException('配置过于复杂，或包含重复的 YAML 引用');
        }
        if (node is YamlMap) {
          final result = <String, Object?>{};
          for (final entry in node.nodes.entries) {
            final key = entry.key;
            if (key is! YamlScalar || key.value is! String) {
              throw const SettingsException('配置字段名必须为文字');
            }
            result[key.value as String] = plain(entry.value, depth + 1);
          }
          return result;
        }
        if (node is YamlList) {
          return [for (final child in node.nodes) plain(child, depth + 1)];
        }
        final value = node.value;
        if (value is String || value is bool || value is int || value == null) {
          return value;
        }
        throw const SettingsException('配置仅支持对象、列表、文字、整数和布尔值');
      }

      final value = plain(document.contents, 0);
      if (value is! Map<String, Object?>) {
        throw const SettingsException('配置最外层必须为对象');
      }
      if (value.keys
          .any((key) => !const ['log', 'dns', 'route'].contains(key))) {
        throw const SettingsException(
            '仅可覆盖 log、dns 和 route；节点、认证、监听和控制接口由 RainLink 管理');
      }
      final canonical = jsonEncode(value);
      if (utf8.encode(canonical).length > maxBytes) {
        throw const SettingsException('展开后的配置不能超过 16 KB');
      }
      return AdvancedConfig._(canonical);
    } on YamlException catch (error) {
      final start = error.span?.start;
      throw SettingsException(start == null
          ? 'YAML 语法无效，请检查缩进与字段'
          : '第 ${start.line + 1} 行，第 ${start.column + 1} 列：语法无效或字段重复');
    }
  }

  Map<String, Object?> get fields =>
      jsonDecode(canonicalJson) as Map<String, Object?>;

  bool overrides(String section, [String? field]) {
    final value = fields[section];
    bool hasValue(Object? item) => switch (item) {
          Map<Object?, Object?> map => map.values.any(hasValue),
          List<Object?> list => list.isNotEmpty,
          String text => text.isNotEmpty,
          _ => item != null,
        };
    return value is Map && hasValue(field == null ? value : value[field]);
  }

  String render(ConfigFormat format) {
    final value = fields;
    if (format == ConfigFormat.json) {
      return const JsonEncoder.withIndent('  ').convert(value);
    }
    if (value.isEmpty) return '# RainLink 高级配置\n{}';
    // JSON scalar quoting is valid YAML and avoids ambiguous domain/IP values.
    String yaml(Object? item, int indent) {
      final pad = ' ' * indent;
      if (item is Map<String, Object?> && item.isNotEmpty) {
        return item.entries.map((entry) {
          final child = entry.value;
          final key = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(entry.key)
              ? entry.key
              : jsonEncode(entry.key);
          return child is Map && child.isNotEmpty ||
                  child is List && child.isNotEmpty
              ? '$pad$key:\n${yaml(child, indent + 2)}'
              : '$pad$key: ${jsonEncode(child)}';
        }).join('\n');
      }
      if (item is List && item.isNotEmpty) {
        return item
            .map((child) => child is Map && child.isNotEmpty ||
                    child is List && child.isNotEmpty
                ? '$pad-\n${yaml(child, indent + 2)}'
                : '$pad- ${jsonEncode(child)}')
            .join('\n');
      }
      return '$pad${jsonEncode(item)}';
    }

    return '# RainLink 高级配置\n${yaml(value, 0)}';
  }

  @override
  bool operator ==(Object other) =>
      other is AdvancedConfig && other.canonicalJson == canonicalJson;
  @override
  int get hashCode => canonicalJson.hashCode;
}
