import '../../../design_system/widgets/rainlink_icon.dart';

enum SettingsSection {
  general('通用', RainlinkGlyph.settings),
  appearance('外观', RainlinkGlyph.sun),
  network('网络', RainlinkGlyph.globe),
  core('核心引擎', RainlinkGlyph.terminal),
  updates('更新', RainlinkGlyph.refresh),
  about('关于', RainlinkGlyph.rain);

  const SettingsSection(this.label, this.icon);
  final String label;
  final RainlinkGlyph icon;
}
