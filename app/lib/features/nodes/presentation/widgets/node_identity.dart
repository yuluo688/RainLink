import 'package:flutter/material.dart';

import '../../../../design_system/theme/rainlink_colors.dart';
import '../../../../design_system/widgets/rainlink_icon.dart';
import '../../../../domain/nodes/proxy_node.dart';
import '../../../../application/nodes/node_display_info.dart';

/// The 28 px region tile and two-line node label from Figma's node row.
class NodeIdentity extends StatelessWidget {
  const NodeIdentity(
      {required this.node, this.showProtocol = false, super.key});

  final ProxyNode node;
  final bool showProtocol;

  @override
  Widget build(BuildContext context) {
    final colors = RainlinkColors.of(context);
    final text = Theme.of(context).textTheme;
    final info = NodeDisplayInfo.fromName(node.name);
    final sourceInfo = NodeDisplayInfo.fromName(node.sourceName);
    final regionCode = info.regionCode ?? sourceInfo.regionCode;
    final region = info.region ?? sourceInfo.region;
    final location = info.location ?? sourceInfo.location;
    final endpoint = node.server.contains(':')
        ? '[${node.server}]:${node.port}'
        : '${node.server}:${node.port}';
    return Row(children: [
      Tooltip(
          message: region == null ? '未标注地区' : '节点标注地区：$region',
          child: Container(
            key: ValueKey('node-region-${node.id}'),
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: colors.raised, borderRadius: BorderRadius.circular(9)),
            child: regionCode == null
                ? RainlinkIcon(RainlinkGlyph.globe,
                    size: 16, color: colors.secondary)
                : Text(regionCode,
                    style: text.labelMedium?.copyWith(
                        fontSize: 11,
                        height: 16 / 11,
                        color: colors.secondary,
                        fontWeight: FontWeight.w600,
                        fontVariations: const [FontVariation('wght', 600)])),
          )),
      const SizedBox(width: 12),
      Expanded(
          child: Tooltip(
              message:
                  '${node.name}${node.hasAlias ? '\n原名：${node.sourceName}' : ''}\n$endpoint',
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(info.name,
                        key: ValueKey('node-name-${node.id}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelLarge?.copyWith(
                            fontSize: 14, height: 20 / 14, color: colors.text)),
                    const SizedBox(height: 2),
                    Text(
                        showProtocol
                            ? '${node.protocol.label} · ${location ?? endpoint}'
                            : location ?? endpoint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall
                            ?.copyWith(fontSize: 11, height: 16 / 11)),
                  ]))),
    ]);
  }
}
