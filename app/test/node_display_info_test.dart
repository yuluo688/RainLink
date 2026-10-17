import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/nodes/node_display_info.dart';

void main() {
  test('separates flag prefixes without changing the source name', () {
    const source = '🇯🇵AWS日本01 | 电信移动联通推荐';
    final info = NodeDisplayInfo.fromName(source);
    expect(info.name, 'AWS日本01 | 电信移动联通推荐');
    expect(info.regionCode, 'JP');
    expect(info.location, '日本');
  });

  test('supports enclosed, spaced and trailing flags', () {
    expect(NodeDisplayInfo.fromName('【🇭🇰】香港 01').name, '香港 01');
    expect(NodeDisplayInfo.fromName('[🇯🇵] 东京 01').location, '日本 · 东京');
    expect(NodeDisplayInfo.fromName('东京 · 樱花 🇯🇵').name, '东京 · 樱花');
    expect(NodeDisplayInfo.fromName('🇯🇵').name, '日本');
  });

  test('explicit flag wins over other regions mentioned in a name', () {
    final info = NodeDisplayInfo.fromName('🇸🇬日本中转');
    expect(info.regionCode, 'SG');
    expect(info.location, '新加坡');
    expect(info.city, isNull);
  });

  test('uses explicit country and city labels with or without flags', () {
    for (final (name, code, location) in [
      ('东京 · 樱花', 'JP', '日本 · 东京'),
      ('中国香港 01', 'HK', '中国香港'),
      ('中国台湾 台北', 'TW', '中国台湾 · 台北'),
      ('中国大陆 01', 'CN', '中国'),
      ('🇺🇸Los Angeles 01', 'US', '美国 · 洛杉矶'),
      ('sg - Singapore', 'SG', '新加坡'),
      ('UK London 01', 'GB', '英国 · 伦敦'),
      ('🇳🇿Auckland', 'NZ', 'NZ'),
    ]) {
      final info = NodeDisplayInfo.fromName(name);
      expect(info.regionCode, code, reason: name);
      expect(info.location, location, reason: name);
    }
  });

  test('keeps ordinary names and does not guess from partial country codes',
      () {
    for (final name in ['自建 HTTP', 'business gateway', '🚀 高速入口', '主节点 01']) {
      final info = NodeDisplayInfo.fromName(name);
      expect(info.name, name);
      expect(info.regionCode, isNull);
      expect(info.location, isNull);
    }
  });
}
