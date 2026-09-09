import 'package:flutter/material.dart';

final ValueNotifier<bool> isDarkModeNotifier = ValueNotifier<bool>(true);

class AppTheme {
  // Dark Theme Palette
  static const Color darkBg = Color(0xFF0F172A); // Slate 900
  static const Color darkCard = Color(0xFF1E293B); // Slate 800
  static const Color darkBorder = Color(0xFF334155); // Slate 700
  static const Color darkTextPrimary = Colors.white;
  static const Color darkTextSecondary = Color(0xFF94A3B8); // Slate 400
  static const Color darkAccent = Color(0xFF38BDF8); // Sky 400

  // Sky Blue Light Theme Palette
  static const Color skyBg = Color(0xFFF0F9FF); // Sky 50
  static const Color skyCard = Colors.white;
  static const Color skyBorder = Color(0xFFBAE6FD); // Sky 200
  static const Color skyTextPrimary = Color(0xFF0C4A6E); // Sky 900
  static const Color skyTextSecondary = Color(0xFF0369A1); // Sky 700
  static const Color skyAccent = Color(0xFF0284C7); // Sky 600
  static const Color skyButton = Color(0xFF0284C7);

  // Shared semantic tokens (identical in both themes)
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color primaryButtonDark = Color(0xFF2563EB);
  static const Color callGreen = Color(0xFF059669);

  static ThemeData getTheme(bool isDark) {
    if (isDark) {
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: darkBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: darkCard,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardColor: darkCard,
        colorScheme: const ColorScheme.dark(
          primary: darkAccent,
          surface: darkCard,
          onSurface: darkTextPrimary,
          error: danger,
        ),
      );
    } else {
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: skyBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: skyCard,
          foregroundColor: skyTextPrimary,
          elevation: 0.5,
          iconTheme: IconThemeData(color: skyTextPrimary),
        ),
        cardColor: skyCard,
        colorScheme: const ColorScheme.light(
          primary: skyAccent,
          surface: skyCard,
          onSurface: skyTextPrimary,
          error: danger,
        ),
      );
    }
  }
}
