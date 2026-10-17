import 'package:flutter/material.dart';

import 'widgets/node_controls.dart';
import '../../../domain/nodes/proxy_node.dart';

class DesktopNodeToolbar extends StatelessWidget {
  const DesktopNodeToolbar({
    required this.controller,
    required this.onSearchChanged,
    required this.onClear,
    required this.nodes,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClear;
  final List<ProxyNode> nodes;

  @override
  Widget build(BuildContext context) {
    final search = NodeSearchField(
        controller: controller,
        onSearchChanged: onSearchChanged,
        onClear: onClear);
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 640) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            search,
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [const NodeGroupFilter(), NodeTools(nodes: nodes)],
            ),
          ],
        );
      }
      return Row(children: [
        const NodeGroupFilter(),
        const SizedBox(width: 24),
        Expanded(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: search)),
        const SizedBox(width: 24),
        NodeTools(nodes: nodes),
      ]);
    });
  }
}
