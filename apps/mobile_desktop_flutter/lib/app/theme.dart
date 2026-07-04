import 'package:flutter/material.dart';

/// Memory Circle design tokens: warm paper surfaces, deep green primary,
/// ink text, and soft rust/gold accents.
abstract final class AppColors {
  static const ivory = Color(0xFFF7F2E7);
  static const paper = Color(0xFFFFFDF6);
  static const parchment = Color(0xFFFDF6E7);
  static const deepGreen = Color(0xFF386641);
  static const forest = Color(0xFF2A4A32);
  static const ink = Color(0xFF262419);
  static const softInk = Color(0xFF6E6857);
  static const rust = Color(0xFFB85C38);
  static const gold = Color(0xFFC9A227);
  static const outline = Color(0xFFE6DEC9);
  static const success = Color(0xFF3E7C4F);
  static const attention = Color(0xFFB07D1F);

  /// Dim viewing-room backdrop behind the flip album.
  static const backdrop = Color(0xFF2E2B24);

  /// Light text colors used on the [backdrop].
  static const onBackdrop = Color(0xFFF3EDDF);
  static const onBackdropFaded = Color(0xFFBDB5A2);
}

/// Spacing steps used across screens.
abstract final class Insets {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.deepGreen).copyWith(
    primary: AppColors.deepGreen,
    onPrimary: Colors.white,
    secondary: AppColors.rust,
    onSecondary: Colors.white,
    tertiary: AppColors.gold,
    surface: AppColors.paper,
    onSurface: AppColors.ink,
    error: const Color(0xFF9C3A2E),
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final text = base.textTheme;

  TextStyle? serif(TextStyle? style) => style?.copyWith(
        fontFamily: 'Georgia',
        fontFamilyFallback: const ['Times New Roman', 'serif'],
      );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.ivory,
    textTheme: text
        .copyWith(
          displaySmall: serif(text.displaySmall),
          headlineMedium: serif(text.headlineMedium),
          headlineSmall: serif(text.headlineSmall),
          titleLarge: serif(text.titleLarge),
        )
        .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
    dividerColor: AppColors.outline,
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Shared input decoration so text fields look consistent without relying on
/// version-specific input theme types.
InputDecoration appInput(
  String label, {
  String? hint,
  String? helper,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    helperMaxLines: 2,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: Colors.white,
    border: border(AppColors.outline),
    enabledBorder: border(AppColors.outline),
    focusedBorder: border(AppColors.deepGreen, 1.6),
  );
}
