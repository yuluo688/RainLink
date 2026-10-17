import 'package:flutter/material.dart';

import '../theme/rainlink_colors.dart';
import '../theme/rainlink_density.dart';

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    required this.child,
    this.padding,
    this.color,
    this.borderColor,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final colors = RainlinkColors.of(context);
    return Container(
      padding:
          padding ?? EdgeInsets.all(RainlinkDensity.of(context).cardPadding),
      decoration: BoxDecoration(
        color: color ?? colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor ?? colors.border),
      ),
      child: child,
    );
  }
}
