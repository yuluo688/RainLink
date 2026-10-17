import '../../design_system/widgets/rainlink_icon.dart';

enum AppDestination {
  overview('/overview', '概览', RainlinkGlyph.grid),
  nodes('/nodes', '节点', RainlinkGlyph.nodes),
  groups('/groups', '分组', RainlinkGlyph.folder),
  rules('/rules', '规则', RainlinkGlyph.rules),
  connections('/connections', '连接', RainlinkGlyph.connections),
  traffic('/traffic', '流量', RainlinkGlyph.chart),
  logs('/logs', '日志', RainlinkGlyph.terminal),
  settings('/settings', '设置', RainlinkGlyph.settings);

  const AppDestination(this.path, this.label, this.icon);

  final String path;
  final String label;
  final RainlinkGlyph icon;

  static AppDestination forPath(String path) {
    if (path == '/chain') return nodes;
    return values.firstWhere(
      (destination) => destination.path == path,
      orElse: () => overview,
    );
  }
}
