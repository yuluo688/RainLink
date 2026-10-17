/// A node's advertised region, used only for presentation.
/// This never changes subscription data or represents a measured exit country.
class NodeDisplayInfo {
  const NodeDisplayInfo._(this.name, this.regionCode, this.region, this.city);

  final String name;
  final String? regionCode;
  final String? region;
  final String? city;

  String? get location => region == null
      ? null
      : city == null || city == region
          ? region
          : '$region · $city';

  factory NodeDisplayInfo.fromName(String original) {
    final flag = _flags.firstMatch(original)?.group(0);
    final cleaned = original.replaceAll(_flags, '').trim();
    // Providers sometimes enclose a flag in brackets. Remove the empty wrapper
    // along with the flag, without changing the remaining node name.
    final name = flag == null
        ? cleaned
        : cleaned.replaceFirst(_emptyPrefix, '').trimLeft();
    final code = flag == null
        ? _regionFromName(name)
        : String.fromCharCodes(flag.runes.map((rune) => rune - 0x1F1E6 + 65));
    final region = _regions[code];
    String? city;
    if (region != null) {
      for (final entry in region.cities.entries) {
        if (_keywordIndex(name, entry.key) >= 0) {
          city = entry.value;
          break;
        }
      }
    }
    final label = region?.name ?? code;
    return NodeDisplayInfo._(
        name.isEmpty ? label ?? '未命名节点' : name, code, label, city);
  }
}

final _flags = RegExp(r'[\u{1F1E6}-\u{1F1FF}]{2}', unicode: true);
final _emptyPrefix = RegExp(r'^(?:\[\s*\]|【\s*】|\(\s*\)|（\s*）)\s*');

int _keywordIndex(String name, String keyword) {
  if (RegExp(r'^[\x00-\x7F]+$').hasMatch(keyword)) {
    return RegExp('\\b${RegExp.escape(keyword)}\\b', caseSensitive: false)
            .firstMatch(name)
            ?.start ??
        -1;
  }
  return name.indexOf(keyword);
}

String? _regionFromName(String name) {
  String? code;
  var first = name.length;
  var longest = 0;
  for (final entry in _regions.entries) {
    for (final keyword in [
      entry.key,
      entry.value.name,
      ...entry.value.aliases,
      ...entry.value.cities.keys,
    ]) {
      final index = _keywordIndex(name, keyword);
      if (index >= 0 &&
          (index < first || (index == first && keyword.length > longest))) {
        code = entry.key;
        first = index;
        longest = keyword.length;
      }
    }
  }
  return code;
}

class _Region {
  const _Region(this.name, this.aliases, [this.cities = const {}]);
  final String name;
  final List<String> aliases;
  final Map<String, String> cities;
}

const _regions = {
  'JP': _Region('日本', [
    'Japan'
  ], {
    '东京': '东京',
    'Tokyo': '东京',
    '大阪': '大阪',
    'Osaka': '大阪',
  }),
  'HK': _Region('中国香港', ['香港', 'Hong Kong']),
  'SG': _Region('新加坡', ['Singapore', '狮城']),
  'KR': _Region('韩国', ['Korea'], {'首尔': '首尔', 'Seoul': '首尔'}),
  'US': _Region('美国', [
    'United States',
    'USA'
  ], {
    '洛杉矶': '洛杉矶',
    'Los Angeles': '洛杉矶',
    '纽约': '纽约',
    'New York': '纽约',
  }),
  'TW': _Region('中国台湾', ['台湾', 'Taiwan'], {'台北': '台北', 'Taipei': '台北'}),
  'AU': _Region('澳大利亚', ['Australia', '澳洲'], {'悉尼': '悉尼', 'Sydney': '悉尼'}),
  'GB': _Region('英国', ['United Kingdom', 'UK'], {'伦敦': '伦敦', 'London': '伦敦'}),
  'DE': _Region('德国', ['Germany'], {'法兰克福': '法兰克福', 'Frankfurt': '法兰克福'}),
  'NL':
      _Region('荷兰', ['Netherlands'], {'阿姆斯特丹': '阿姆斯特丹', 'Amsterdam': '阿姆斯特丹'}),
  'FR': _Region('法国', ['France'], {'巴黎': '巴黎', 'Paris': '巴黎'}),
  'CA': _Region('加拿大', ['Canada'], {'多伦多': '多伦多', 'Toronto': '多伦多'}),
  'MO': _Region('中国澳门', ['澳门', 'Macao', 'Macau']),
  'CN': _Region('中国', ['China', '中国大陆']),
  'IN': _Region('印度', ['India']),
  'TR': _Region('土耳其', ['Turkey', 'Türkiye']),
  'RU': _Region('俄罗斯', ['Russia']),
};
