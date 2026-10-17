import 'package:flutter/material.dart';
import '../../../domain/nodes/proxy_node.dart';
import '../../../domain/chains/proxy_chain.dart';
import '../../../design_system/widgets/rainlink_icon.dart';
import '../../../design_system/theme/rainlink_density.dart';
import '../../nodes/presentation/widgets/node_identity.dart';

Future<String?> showChainNodePicker(BuildContext context,
        {required List<ProxyNode> nodes,
        required List<String> hopIds,
        int? replaceIndex}) =>
    showDialog<String>(
        context: context,
        builder: (_) => _ChainNodePicker(
            nodes: nodes, hopIds: hopIds, replaceIndex: replaceIndex));

class _ChainNodePicker extends StatefulWidget {
  const _ChainNodePicker(
      {required this.nodes, required this.hopIds, this.replaceIndex});
  final List<ProxyNode> nodes;
  final List<String> hopIds;
  final int? replaceIndex;
  @override
  State<_ChainNodePicker> createState() => _ChainNodePickerState();
}

class _ChainNodePickerState extends State<_ChainNodePicker> {
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String? _unavailable(ProxyNode node) {
    final ids = [...widget.hopIds];
    final index = widget.replaceIndex;
    if (ids.contains(node.id) && (index == null || ids[index] != node.id)) {
      return '已在链中';
    }
    if (index == null) {
      ids.add(node.id);
    } else {
      ids[index] = node.id;
    }
    final byId = {for (final item in widget.nodes) item.id: item};
    return chainCompatibilityIssue(ids.map((id) => byId[id]?.protocol));
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final nodes = widget.nodes
        .where((node) =>
            !node.hidden &&
            '${node.name} ${node.sourceName} ${node.protocol.label} ${node.server}'
                .toLowerCase()
                .contains(query))
        .toList();
    return AlertDialog(
        title: Row(children: [
          Expanded(child: Text(widget.replaceIndex == null ? '添加跳点' : '更换节点')),
          IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.pop(context),
              icon: const RainlinkIcon(RainlinkGlyph.close, size: 18))
        ]),
        content: SizedBox(
            width: 480,
            height: MediaQuery.sizeOf(context).height.clamp(280, 660) - 220,
            child: Column(children: [
              TextField(
                  controller: _search,
                  autofocus: true,
                  key: const ValueKey('chain-node-search'),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      hintText: '搜索名称、协议或服务器',
                      prefixIcon: Padding(
                          padding: EdgeInsets.all(12),
                          child:
                              RainlinkIcon(RainlinkGlyph.search, size: 18)))),
              const SizedBox(height: 12),
              Expanded(
                  child: nodes.isEmpty
                      ? const Center(child: Text('没有匹配的节点'))
                      : ListView.builder(
                          itemCount: nodes.length,
                          itemBuilder: (context, index) {
                            final node = nodes[index];
                            final reason = _unavailable(node);
                            return Tooltip(
                                message: reason ?? '选择 ${node.name}',
                                child: ListTile(
                                    key: ValueKey('chain-pick-${node.id}'),
                                    enabled: reason == null,
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: RainlinkDensity.of(context)
                                            .nodePadding),
                                    title: NodeIdentity(
                                        node: node, showProtocol: true),
                                    subtitle: reason == null
                                        ? null
                                        : Text(reason,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall),
                                    trailing: reason == null
                                        ? const RainlinkIcon(RainlinkGlyph.plus,
                                            size: 16)
                                        : null,
                                    onTap: reason == null
                                        ? () => Navigator.pop(context, node.id)
                                        : null));
                          }))
            ])));
  }
}
