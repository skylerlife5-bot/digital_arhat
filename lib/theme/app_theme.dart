import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData get darkTheme {
    const radius = 14.0;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accentGold,
      brightness: Brightness.dark,
      primary: AppColors.accentGold,
      secondary: AppColors.accentGold,
      surface: AppColors.cardSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      dividerColor: AppColors.divider,
      cardTheme: CardThemeData(
        color: AppColors.cardSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: AppColors.divider),
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.primaryText,
        surfaceTintColor: AppColors.background,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentGold,
          foregroundColor: AppColors.ctaTextDark,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryText,
          side: const BorderSide(color: AppColors.divider),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardSurface,
        hintStyle: const TextStyle(color: AppColors.secondaryText),
        labelStyle: const TextStyle(color: AppColors.secondaryText),
        prefixIconColor: AppColors.accentGold,
        suffixIconColor: AppColors.secondaryText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: AppColors.accentGold, width: 1),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.background,
        selectedItemColor: AppColors.accentGold,
        unselectedItemColor: AppColors.secondaryText,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.cardSurface,
        selectedColor: AppColors.softOverlayGold,
        disabledColor: AppColors.cardSurface,
        side: const BorderSide(color: AppColors.divider),
        labelStyle: const TextStyle(color: AppColors.primaryText),
        secondaryLabelStyle: const TextStyle(color: AppColors.primaryText),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
      ),
    );
  }
}
