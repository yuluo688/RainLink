import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/rainlink_colors.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({this.size = 40, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = RainlinkColors.of(context);
    return SvgPicture(
      SvgAssetLoader('assets/brand/mark.svg',
          colorMapper: _BrandColors(colors.primarySurface, colors.primary)),
      width: size,
      height: size,
      excludeFromSemantics: true,
    );
  }
}

// Keep Figma's original paths and remap only its two color tokens for light mode.
class _BrandColors extends ColorMapper {
  const _BrandColors(this.background, this.foreground);
  final Color background;
  final Color foreground;

  @override
  Color substitute(
          String? id, String elementName, String attributeName, Color color) =>
      switch (color) {
        const Color(0xFF1B2B25) => background,
        const Color(0xFF8ADCBF) => foreground,
        _ => color,
      };

  @override
  bool operator ==(Object other) =>
      other is _BrandColors &&
      other.background == background &&
      other.foreground == foreground;

  @override
  int get hashCode => Object.hash(background, foreground);
}
