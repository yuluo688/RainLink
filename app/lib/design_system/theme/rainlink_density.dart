import 'package:flutter/material.dart';

import '../../domain/preferences/device_settings.dart';

/// Explicit spacing tokens keep density independent of font size, navigation
/// breakpoints and Material's automatic platform-specific density reduction.
class RainlinkDensity extends ThemeExtension<RainlinkDensity> {
  const RainlinkDensity(this.density);
  final AppDensity density;

  static RainlinkDensity of(BuildContext context) =>
      Theme.of(context).extension<RainlinkDensity>() ??
      const RainlinkDensity(AppDensity.compact);

  bool get compact => density == AppDensity.compact;
  double get rowHeight => compact ? 56 : 64;
  double get rowPadding => compact ? 6 : 10;
  double get nodePadding => compact ? 4 : 8;
  double get logPadding => compact ? 12 : 16;
  double get settingsPadding => compact ? 10 : 14;
  double get listGap => compact ? 8 : 12;
  double get sectionGap => compact ? 12 : 16;
  double get toolbarGap => compact ? 16 : 20;
  double get cardPadding => compact ? 24 : 28;
  double get controlHeight => compact ? 40 : 44;
  double get segmentHeight => compact ? 36 : 40;
  double get controlHorizontalPadding => compact ? 16 : 20;
  double get controlVerticalPadding => compact ? 10 : 12;
  double get inputVerticalPadding => compact ? 14 : 16;
  double get tableHeaderPadding => compact ? 10 : 14;

  EdgeInsets desktopPagePadding({required bool narrow}) => EdgeInsets.symmetric(
      horizontal: narrow ? (compact ? 20 : 24) : (compact ? 36 : 40),
      vertical: compact ? 24 : 28);
  EdgeInsets get mobilePagePadding =>
      EdgeInsets.fromLTRB(20, compact ? 12 : 16, 20, compact ? 16 : 20);

  @override
  RainlinkDensity copyWith({AppDensity? density}) =>
      RainlinkDensity(density ?? this.density);

  @override
  RainlinkDensity lerp(covariant RainlinkDensity? other, double t) =>
      other == null || t < .5 ? this : other;
}
