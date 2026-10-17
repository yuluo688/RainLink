import 'package:flutter/material.dart';

import '../widgets/page_heading.dart';
import '../theme/rainlink_density.dart';

class DesktopPageFrame extends StatelessWidget {
  const DesktopPageFrame({
    required this.title,
    required this.description,
    required this.child,
    this.actions = const [],
    this.leading,
    this.scrollable = true,
    this.padding,
    super.key,
  });

  final String title;
  final String description;
  final Widget child;
  final List<Widget> actions;
  final Widget? leading;
  final bool scrollable;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final density = RainlinkDensity.of(context);
          final heading = PageHeading(
              title: title, description: description, leading: leading);
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact) ...[
                heading,
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ] else
                Row(
                  children: [
                    Expanded(child: heading),
                    if (actions.isNotEmpty)
                      Wrap(spacing: 8, runSpacing: 8, children: actions),
                  ],
                ),
              SizedBox(height: density.sectionGap),
              if (scrollable) child else Expanded(child: child),
            ],
          );
          final contentPadding =
              padding ?? density.desktopPagePadding(narrow: compact);
          return scrollable
              ? SingleChildScrollView(padding: contentPadding, child: content)
              : Padding(padding: contentPadding, child: content);
        },
      );
}
