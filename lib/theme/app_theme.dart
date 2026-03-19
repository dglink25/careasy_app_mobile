// lib/theme/app_theme.dart
import 'package:flutter/material.dart';
import '../utils/constants.dart';

class AppTheme {
  // ─── Thème clair ───────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: AppConstants.primaryRed,
      colorScheme: ColorScheme.light(
        primary: AppConstants.primaryRed,
        secondary: AppConstants.primaryRed,
        surface: Colors.white,
        background: const Color(0xFFF8F9FA),
      ),
      scaffoldBackgroundColor: const Color(0xFFF8F9FA),
      cardColor: Colors.white,
      dividerColor: Colors.grey[200],
      appBarTheme: const AppBarTheme(
        backgroundColor: AppConstants.primaryRed,
        foregroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppConstants.primaryRed,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: AppConstants.lightGrey,
        contentPadding: const EdgeInsets.all(16),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Color(0xFF1A1A1A)),
        bodyMedium: TextStyle(color: Color(0xFF333333)),
        bodySmall: TextStyle(color: Color(0xFF666666)),
        titleLarge: TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.w600),
      ),
      iconTheme: const IconThemeData(color: Color(0xFF333333)),
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith(
          (states) => states.contains(MaterialState.selected)
              ? AppConstants.primaryRed
              : Colors.grey,
        ),
        trackColor: MaterialStateProperty.resolveWith(
          (states) => states.contains(MaterialState.selected)
              ? AppConstants.primaryRed.withOpacity(0.4)
              : Colors.grey.withOpacity(0.3),
        ),
      ),
    );
  }

  // ─── Thème sombre ──────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: AppConstants.primaryRed,
      colorScheme: ColorScheme.dark(
        primary: AppConstants.primaryRed,
        secondary: AppConstants.primaryRed,
        surface: const Color(0xFF1E1E2E),
        background: const Color(0xFF0F0F1A),
      ),
      scaffoldBackgroundColor: const Color(0xFF0F0F1A),
      cardColor: const Color(0xFF1E1E2E),
      dividerColor: Colors.white12,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppConstants.primaryRed,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: const Color(0xFF2A2A3E),
        contentPadding: const EdgeInsets.all(16),
        hintStyle: const TextStyle(color: Colors.white38),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Color(0xFFCCCCCC)),
        bodySmall: TextStyle(color: Color(0xFF999999)),
        titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
      iconTheme: const IconThemeData(color: Colors.white70),
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith(
          (states) => states.contains(MaterialState.selected)
              ? AppConstants.primaryRed
              : Colors.grey,
        ),
        trackColor: MaterialStateProperty.resolveWith(
          (states) => states.contains(MaterialState.selected)
              ? AppConstants.primaryRed.withOpacity(0.4)
              : Colors.white12,
        ),
      ),
    );
  }
}