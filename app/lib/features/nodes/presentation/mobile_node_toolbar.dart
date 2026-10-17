import 'package:flutter/material.dart';

import 'widgets/node_controls.dart';
import '../../../domain/nodes/proxy_node.dart';

class MobileNodeToolbar extends StatelessWidget {
  const MobileNodeToolbar({
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
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NodeSearchField(
              controller: controller,
              onSearchChanged: onSearchChanged,
              onClear: onClear),
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
