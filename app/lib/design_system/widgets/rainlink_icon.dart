import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Native SVG exports from RainLink's Figma icon components.
enum RainlinkGlyph {
  grid('grid'),
  nodes('nodes'),
  profile('profile'),
  rules('rules'),
  connections('connections'),
  chart('chart'),
  terminal('terminal'),
  settings('settings'),
  search('search'),
  chevronRight('chevron_right'),
  chevronDown('chevron_down'),
  plus('plus'),
  check('check'),
  close('close'),
  star('star'),
  power('power'),
  download('download'),
  upload('upload'),
  speed('speed'),
  globe('globe'),
  shield('shield'),
  bell('bell'),
  sun('sun'),
  moon('moon'),
  refresh('refresh'),
  qr('qr'),
  link('link'),
  copy('copy'),
  more('more'),
  clock('clock'),
  folder('folder'),
  arrowRight('arrow_right'),
  laptop('laptop'),
  wifi('wifi'),
  rain('rain'),
  back('back');

  const RainlinkGlyph(this._fileName);
  final String _fileName;

  String get assetPath => 'assets/icons/$_fileName.svg';
}

class RainlinkIcon extends StatelessWidget {
  const RainlinkIcon(this.glyph,
      {this.size, this.color, this.semanticLabel, super.key});

  final RainlinkGlyph glyph;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final dimension = size ?? theme.size ?? 20;
    final foreground = color ?? theme.color ?? const Color(0xFFC0C2C8);
    final opacity = theme.opacity ?? 1;
    return SvgPicture.asset(
      glyph.assetPath,
      width: dimension,
      height: dimension,
      colorFilter: ColorFilter.mode(
        foreground.withValues(alpha: foreground.a * opacity),
        BlendMode.srcIn,
      ),
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}
