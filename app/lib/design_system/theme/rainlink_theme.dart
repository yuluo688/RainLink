import 'package:flutter/material.dart';

import '../widgets/rainlink_icon.dart';
import '../../domain/preferences/device_settings.dart';
import 'rainlink_colors.dart';
import 'rainlink_density.dart';

ThemeData buildRainlinkTheme(Brightness brightness,
    {AppDensity density = AppDensity.compact}) {
  final spacing = RainlinkDensity(density);
  final colors = brightness == Brightness.dark
      ? RainlinkColors.dark
      : RainlinkColors.light;
  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(8)),
  );
  // Noto Sans SC defaults to wght=100. Explicit axes also apply to Chinese
  // fallback glyphs, which do not reliably inherit the Latin font's weight.
  const regular = [FontVariation('wght', 400)];
  const medium = [FontVariation('wght', 500)];
  const semibold = [FontVariation('wght', 600)];
  final scheme = ColorScheme.fromSeed(
    seedColor: colors.primary,
    brightness: brightness,
  ).copyWith(
    primary: colors.primary,
    onPrimary: colors.onPrimary,
    primaryContainer: colors.primarySurface,
    onPrimaryContainer: colors.primary,
    surface: colors.surface,
    onSurface: colors.text,
    onSurfaceVariant: colors.secondary,
    outline: colors.border,
    outlineVariant: colors.border,
    error: colors.error,
  );

  return ThemeData(
    useMaterial3: true,
    // Desktop's automatic compact density silently reduces 40 px controls to
    // 32 px. Keep the dimensions exported from Figma on every platform.
    visualDensity: VisualDensity.standard,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.background,
    canvasColor: colors.surface,
    fontFamily: 'Inter',
    fontFamilyFallback: const [
      'Noto Sans SC',
      'Microsoft YaHei UI',
      'PingFang SC',
      'sans-serif',
    ],
    textTheme: TextTheme(
      headlineMedium: TextStyle(
        fontSize: 26,
        height: 36 / 26,
        fontWeight: FontWeight.w600,
        fontVariations: semibold,
        color: colors.text,
      ),
      titleLarge: TextStyle(
          fontSize: 20,
          height: 29 / 20,
          fontWeight: FontWeight.w600,
          fontVariations: semibold,
          color: colors.text),
      titleMedium: TextStyle(
          fontSize: 16,
          height: 23 / 16,
          fontWeight: FontWeight.w600,
          fontVariations: semibold,
          color: colors.text),
      bodyLarge: TextStyle(
          fontSize: 14,
          height: 20 / 14,
          fontVariations: regular,
          color: colors.text),
      bodyMedium: TextStyle(
          fontSize: 14,
          height: 20 / 14,
          fontVariations: regular,
          color: colors.secondary),
      bodySmall: TextStyle(
          fontSize: 12,
          height: 17 / 12,
          fontVariations: regular,
          color: colors.muted),
      labelLarge: const TextStyle(
          fontSize: 13,
          height: 19 / 13,
          fontWeight: FontWeight.w500,
          fontVariations: medium),
      labelMedium: const TextStyle(
          fontSize: 12,
          height: 17 / 12,
          fontWeight: FontWeight.w500,
          fontVariations: medium),
    ),
    extensions: [colors, spacing],
    dividerTheme:
        DividerThemeData(color: colors.border, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: colors.secondary, size: 20),
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const RainlinkIcon(RainlinkGlyph.back),
      closeButtonIconBuilder: (_) => const RainlinkIcon(RainlinkGlyph.close),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: Size(100, spacing.controlHeight),
        padding: EdgeInsets.symmetric(
            horizontal: spacing.controlHorizontalPadding,
            vertical: spacing.controlVerticalPadding),
        shape: shape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.secondary,
        minimumSize: Size(80, spacing.controlHeight),
        padding: spacing.compact
            ? null
            : EdgeInsets.symmetric(
                horizontal: spacing.controlHorizontalPadding,
                vertical: spacing.controlVerticalPadding),
        side: BorderSide(color: colors.border),
        shape: shape,
      ).copyWith(
        iconColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? colors.text.withValues(alpha: .38)
                : colors.secondary),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: Size(44, spacing.controlHeight),
        shape: shape,
      ),
    ),
    dialogTheme: DialogTheme(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.border),
      ),
      titleTextStyle: TextStyle(
          fontFamily: 'Noto Sans SC',
          fontSize: 20,
          height: 1.45,
          fontWeight: FontWeight.w600,
          fontVariations: semibold,
          color: colors.text),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.border)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      isDense: true,
      errorMaxLines: 3,
      contentPadding: EdgeInsets.symmetric(
          horizontal: 14, vertical: spacing.inputVerticalPadding),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colors.border),
      ),
    ),
    tooltipTheme:
        const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surface,
      indicatorColor: colors.primarySurface,
      height: 56,
      indicatorShape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          size: 20,
          color: states.contains(WidgetState.selected)
              ? colors.primary
              : colors.muted)),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
          fontFamily: 'Noto Sans SC',
          fontSize: 11,
          fontWeight: FontWeight.w500,
          fontVariations: medium,
          color: states.contains(WidgetState.selected)
              ? colors.primary
              : colors.muted)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.raised,
      contentTextStyle: TextStyle(color: colors.text),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
