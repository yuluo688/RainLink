import 'package:flutter/material.dart';

import '../widgets/surface_card.dart';
import '../theme/rainlink_density.dart';

class MobileCollectionLayout extends StatelessWidget {
  const MobileCollectionLayout({
    required this.emptyState,
    this.toolbar,
    this.expandContent = false,
    this.framed = true,
    super.key,
  });

  final Widget emptyState;
  final Widget? toolbar;
  final bool expandContent;
  final bool framed;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (toolbar != null) ...[
            toolbar ?? const SizedBox.shrink(),
            SizedBox(height: RainlinkDensity.of(context).toolbarGap),
          ],
          if (expandContent)
            Expanded(
                child: framed
                    ? SurfaceCard(padding: EdgeInsets.zero, child: emptyState)
                    : emptyState)
          else if (framed)
            SurfaceCard(padding: EdgeInsets.zero, child: emptyState)
          else
            emptyState,
        ],
      );
}
