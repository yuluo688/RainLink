import 'package:flutter/material.dart';

import '../theme/rainlink_colors.dart';
import '../theme/rainlink_density.dart';
import '../widgets/surface_card.dart';

class DesktopCollectionLayout extends StatelessWidget {
  const DesktopCollectionLayout({
    required this.columns,
    required this.emptyState,
    this.columnFlexes,
    this.toolbar,
    this.expandContent = false,
    super.key,
  });

  final List<String> columns;
  final List<int>? columnFlexes;
  final Widget emptyState;
  final Widget? toolbar;
  final bool expandContent;

  @override
  Widget build(BuildContext context) {
    final colors = RainlinkColors.of(context);
    final density = RainlinkDensity.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (toolbar != null) ...[
          toolbar ?? const SizedBox.shrink(),
          SizedBox(height: density.toolbarGap),
        ],
        Flexible(
            fit: expandContent ? FlexFit.tight : FlexFit.loose,
            flex: expandContent ? 1 : 0,
            child: SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                  mainAxisSize:
                      expandContent ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    if (columns.isNotEmpty) ...[
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: density.tableHeaderPadding),
                        decoration: BoxDecoration(
                          color: colors.raised,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(11)),
                        ),
                        child: Row(children: [
                          for (var index = 0; index < columns.length; index++)
                            Expanded(
                              flex: columnFlexes?[index] ?? 1,
                              child: Text(columns[index],
                                  style: Theme.of(context).textTheme.bodySmall),
                            ),
                        ]),
                      ),
                      const Divider(),
                    ],
                    if (expandContent)
                      Expanded(child: emptyState)
                    else
                      emptyState,
                  ]),
            )),
      ],
    );
  }
}
