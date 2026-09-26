import 'package:flutter/material.dart';

import 'app_spacing.dart';

/// Convoze's design system: one seed color, algorithmically built into
/// accessible light/dark [ColorScheme]s, plus the shared type scale and
/// component styles every screen inherits from [Theme.of].
abstract final class AppTheme {
  /// The brand color the rest of the palette is derived from. A saturated
  /// teal, deliberately not the default Material demo seed (indigo).
  static const _seed = Color(0xFF0E8C82);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
      // Stays true to the seed's actual hue/chroma (unlike the "tonalSpot"
      // default every unmodified `flutter create` app ships with).
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    final textTheme = _textTheme(scheme);
    final radius = BorderRadius.circular(14);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: scheme.surfaceTint,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(
          alpha: brightness == Brightness.light ? 0.55 : 0.4,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.error, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
        labelStyle: textTheme.bodyMedium,
        hintStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    );
  }

  static TextTheme _textTheme(ColorScheme scheme) {
    TextStyle style(
      double size,
      FontWeight weight, {
      double? height,
      double? letterSpacing,
      Color? color,
    }) => TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      color: color ?? scheme.onSurface,
    );

    return TextTheme(
      headlineSmall: style(26, FontWeight.w700, height: 1.2, letterSpacing: -0.2),
      titleLarge: style(20, FontWeight.w700, height: 1.25),
      titleMedium: style(16, FontWeight.w600, height: 1.3),
      titleSmall: style(14, FontWeight.w600, height: 1.3),
      bodyLarge: style(16, FontWeight.w400, height: 1.4),
      bodyMedium: style(14, FontWeight.w400, height: 1.4, color: scheme.onSurfaceVariant),
      bodySmall: style(12.5, FontWeight.w400, height: 1.35, color: scheme.onSurfaceVariant),
      labelLarge: style(15, FontWeight.w600, height: 1.2),
      labelMedium: style(12.5, FontWeight.w600, height: 1.2, color: scheme.onSurfaceVariant),
      labelSmall: style(11, FontWeight.w600, height: 1.2, color: scheme.onSurfaceVariant),
    );
  }
}
