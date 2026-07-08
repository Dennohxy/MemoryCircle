import 'package:flutter/material.dart';

/// Omoide no Wa design tokens: warm photo surfaces, navy trust,
/// and sun-to-magenta memory accents.
abstract final class AppColors {
  static const sun = Color(0xFFFFC857);
  static const orange = Color(0xFFFF8A3D);
  static const coral = Color(0xFFFF5E7D);
  static const magenta = Color(0xFFD94DBB);
  static const violet = Color(0xFF7A5AF8);
  static const navy = Color(0xFF0F1B3D);
  static const gray = Color(0xFF6B7280);

  static const ivory = Color(0xFFF8F7F4);
  static const paper = Color(0xFFFFFDF6);
  static const parchment = Color(0xFFFFF4DC);
  static const deepGreen = navy;
  static const forest = Color(0xFF172A5A);
  static const ink = navy;
  static const softInk = gray;
  static const rust = coral;
  static const gold = sun;
  static const outline = Color(0xFFE5E1D8);
  static const success = Color(0xFF2F8F6B);
  static const attention = orange;

  /// Dim viewing-room backdrop behind the flip album.
  static const backdrop = Color(0xFF090F24);

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
