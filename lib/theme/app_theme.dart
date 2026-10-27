import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xfff6f7f9);
  static const surface = Color(0xffffffff);
  static const subtle = Color(0xfff8fafb);
  static const border = Color(0xffe5e9ee);
  static const ink = Color(0xff202b3a);
  static const muted = Color(0xff6b7787);
  static const faint = Color(0xff8994a3);
  static const accent = Color(0xff167b68);
  static const accentSoft = Color(0xffedf6f2);
  static const warning = Color(0xffa56b18);
  static const danger = Color(0xffc04f54);
}

abstract final class AppTheme {
  static const fontFallback = [
    'PingFang SC',
    'Microsoft YaHei UI',
    'Noto Sans CJK SC',
    'sans-serif',
  ];

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      primary: AppColors.accent,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.muted,
      outline: AppColors.border,
      error: AppColors.danger,
    ),
    scaffoldBackgroundColor: AppColors.background,
    fontFamilyFallback: fontFallback,
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 13, height: 1.5),
      bodySmall: TextStyle(fontSize: 12, height: 1.5),
      titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ).apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.subtle,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      hintStyle: const TextStyle(fontSize: 12, color: AppColors.faint),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          fontFamilyFallback: fontFallback,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          fontFamilyFallback: fontFallback,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: AppColors.muted),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(fontSize: 12, color: Colors.white),
    ),
  );
}

BoxDecoration panelDecoration({Color color = AppColors.surface}) =>
    BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    );
