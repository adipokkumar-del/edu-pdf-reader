import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_colors.dart';

abstract final class AppTheme {
  static ThemeData get light {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.light);

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brown,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.brown,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: AppColors.textPrimary,
    );

    final textTheme = GoogleFonts.nunitoTextTheme(base.textTheme).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: textTheme,
      dividerColor: AppColors.divider,
      scrollbarTheme: ScrollbarThemeData(
        thumbColor:
            WidgetStateProperty.all(AppColors.brown.withValues(alpha: 0.35)),
        thickness: WidgetStateProperty.all(3),
        radius: const Radius.circular(3),
        crossAxisMargin: 2,
        thumbVisibility: WidgetStateProperty.all(false),
        trackVisibility: WidgetStateProperty.all(false),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.brownDark),
        titleTextStyle: GoogleFonts.lora(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: AppColors.brownDark,
        ),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.brown),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brown,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
