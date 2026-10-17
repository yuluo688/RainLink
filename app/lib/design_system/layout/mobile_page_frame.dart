import 'package:flutter/material.dart';

import '../widgets/page_heading.dart';
import '../widgets/rainlink_icon.dart';
import '../theme/rainlink_density.dart';

class MobilePageFrame extends StatelessWidget {
  const MobilePageFrame({
    required this.title,
    required this.description,
    required this.child,
    this.actions = const [],
    this.leading,
    this.showNavigationButton = true,
    this.scrollable = true,
    this.padding,
    super.key,
  });

  final String title;
  final String description;
  final Widget child;
  final List<Widget> actions;
  final Widget? leading;
  final bool showNavigationButton;
  final bool scrollable;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final density = RainlinkDensity.of(context);
    const minInlineActionWidth = 360.0;
    const maxInlineActionTextScale = 1.2;
    final inlineAction = actions.length == 1 &&
        MediaQuery.sizeOf(context).width >= minInlineActionWidth &&
        MediaQuery.textScalerOf(context).scale(14) <=
            14 * maxInlineActionTextScale;
    final heading =
        PageHeading(title: title, description: description, leading: leading);
    final scaffold = Scaffold.maybeOf(context);
    final showNavigation =
        showNavigationButton && leading == null && scaffold?.hasDrawer == true;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (inlineAction || showNavigation)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: heading),
            if (inlineAction) ...[
              const SizedBox(width: 12),
              actions.single,
            ],
            if (showNavigation) ...[
              const SizedBox(width: 4),
              IconButton(
                  tooltip: '打开导航',
                  onPressed: scaffold?.openDrawer,
                  icon: const RainlinkIcon(RainlinkGlyph.grid, size: 20)),
            ],
          ])
        else
          heading,
        if (actions.isNotEmpty && !inlineAction) ...[
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
        SizedBox(height: density.sectionGap),
        if (scrollable) child else Expanded(child: child),
      ],
    );
    final contentPadding = padding ?? density.mobilePagePadding;
    return scrollable
        ? SingleChildScrollView(padding: contentPadding, child: content)
        : Padding(padding: contentPadding, child: content);
  }
}
