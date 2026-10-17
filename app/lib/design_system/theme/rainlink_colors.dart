import 'package:flutter/material.dart';

@immutable
class RainlinkColors extends ThemeExtension<RainlinkColors> {
  const RainlinkColors({
    required this.background,
    required this.surface,
    required this.raised,
    required this.hover,
    required this.border,
    required this.text,
    required this.secondary,
    required this.muted,
    required this.primary,
    required this.primarySurface,
    required this.onPrimary,
    required this.warning,
    required this.error,
  });

  final Color background;
  final Color surface;
  final Color raised;
  final Color hover;
  final Color border;
  final Color text;
  final Color secondary;
  final Color muted;
  final Color primary;
  final Color primarySurface;
  final Color onPrimary;
  final Color warning;
  final Color error;

  static const dark = RainlinkColors(
    background: Color(0xFF0F1011),
    surface: Color(0xFF151617),
    raised: Color(0xFF1B1C1E),
    hover: Color(0xFF242528),
    border: Color(0xFF2B2D31),
    text: Color(0xFFF4F4F6),
    secondary: Color(0xFFC0C2C8),
    muted: Color(0xFF969AA3),
    primary: Color(0xFF8ADCBF),
    primarySurface: Color(0xFF1B2B25),
    onPrimary: Color(0xFF10241C),
    warning: Color(0xFFE8BC78),
    error: Color(0xFFF28B96),
  );

  static const light = RainlinkColors(
    background: Color(0xFFFAFAFA),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFF4F4F5),
    hover: Color(0xFFECECEE),
    border: Color(0xFFE4E4E7),
    text: Color(0xFF18191B),
    secondary: Color(0xFF55585F),
    muted: Color(0xFF696D75),
    primary: Color(0xFF08795C),
    primarySurface: Color(0xFFE7F5EE),
    onPrimary: Color(0xFFFFFFFF),
    warning: Color(0xFF955F0D),
    error: Color(0xFFBD354A),
  );

  static RainlinkColors of(BuildContext context) {
    return Theme.of(context).extension<RainlinkColors>() ?? dark;
  }

  @override
  RainlinkColors copyWith({
    Color? background,
    Color? surface,
    Color? raised,
    Color? hover,
    Color? border,
    Color? text,
    Color? secondary,
    Color? muted,
    Color? primary,
    Color? primarySurface,
    Color? onPrimary,
    Color? warning,
    Color? error,
  }) =>
      RainlinkColors(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        raised: raised ?? this.raised,
        hover: hover ?? this.hover,
        border: border ?? this.border,
        text: text ?? this.text,
        secondary: secondary ?? this.secondary,
        muted: muted ?? this.muted,
        primary: primary ?? this.primary,
        primarySurface: primarySurface ?? this.primarySurface,
        onPrimary: onPrimary ?? this.onPrimary,
        warning: warning ?? this.warning,
        error: error ?? this.error,
      );

  @override
  RainlinkColors lerp(RainlinkColors? other, double t) {
    if (other == null) return this;
    Color blend(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return RainlinkColors(
      background: blend(background, other.background),
      surface: blend(surface, other.surface),
      raised: blend(raised, other.raised),
      hover: blend(hover, other.hover),
      border: blend(border, other.border),
      text: blend(text, other.text),
      secondary: blend(secondary, other.secondary),
      muted: blend(muted, other.muted),
      primary: blend(primary, other.primary),
      primarySurface: blend(primarySurface, other.primarySurface),
      onPrimary: blend(onPrimary, other.onPrimary),
      warning: blend(warning, other.warning),
      error: blend(error, other.error),
    );
  }
}
