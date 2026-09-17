import 'package:flutter/material.dart';

// Names are persisted; keep these stable across upgrades.
enum AppThemeType { sakuraSmoke, cloudRiver, roseAmber, teaFluo }

final isDarkModeNotifier = ValueNotifier<bool>(true);
final currentThemeTypeNotifier = ValueNotifier<AppThemeType>(
  AppThemeType.teaFluo,
);

abstract final class AppTheme {
  static Color seedFor(AppThemeType type) => switch (type) {
    AppThemeType.sakuraSmoke => const Color(0xFFFF2D78),
    AppThemeType.cloudRiver => const Color(0xFF00A3FF),
    AppThemeType.roseAmber => const Color(0xFFFF8800),
    AppThemeType.teaFluo => const Color(0xFF00E599),
  };

  static ThemeData getTheme(
    bool isDark, {
    AppThemeType themeType = AppThemeType.teaFluo,
  }) {
    final (
      seed,
      secondary,
      tertiary,
      darkScaffold,
      darkSurface,
      darkSurfaceContainer,
      lightScaffold,
      lightSurface,
    ) = switch (themeType) {
      AppThemeType.sakuraSmoke => (
        const Color(0xFFFF2D78),
        const Color(0xFFFA4D8C),
        const Color(0xFFFF6EA7),
        const Color(0xFF160813),
        const Color(0xFF251021),
        const Color(0xFF351730),
        const Color(0xFFFFF0F5),
        const Color(0xFFFFF7FA),
      ),
      AppThemeType.cloudRiver => (
        const Color(0xFF00A3FF),
        const Color(0xFF0284C7),
        const Color(0xFF38BDF8),
        const Color(0xFF071320),
        const Color(0xFF0E2034),
        const Color(0xFF162F4D),
        const Color(0xFFF0F7FF),
        const Color(0xFFF8FBFF),
      ),
      AppThemeType.roseAmber => (
        const Color(0xFFFF8800),
        const Color(0xFFF59E0B),
        const Color(0xFFFBBF24),
        const Color(0xFF180E06),
        const Color(0xFF29180C),
        const Color(0xFF3D2413),
        const Color(0xFFFFF8F0),
        const Color(0xFFFFFDF8),
      ),
      AppThemeType.teaFluo => (
        const Color(0xFF00E599),
        const Color(0xFF10B981),
        const Color(0xFF34D399),
        const Color(0xFF06160F),
        const Color(0xFF0D241A),
        const Color(0xFF143526),
        const Color(0xFFF0FDF5),
        const Color(0xFFF8FEFA),
      ),
    };

    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: isDark ? Brightness.dark : Brightness.light,
    ).copyWith(
      primary: seed,
      onPrimary: (themeType == AppThemeType.teaFluo && isDark)
          ? const Color(0xFF032213)
          : Colors.white,
      primaryContainer: isDark
          ? seed.withValues(alpha: 0.24)
          : seed.withValues(alpha: 0.14),
      onPrimaryContainer: isDark ? seed : seed,
      secondary: secondary,
      tertiary: tertiary,
      surface: isDark ? darkSurface : lightSurface,
      onSurface: isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827),
      onSurfaceVariant: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF4B5563),
      surfaceContainer: isDark ? darkSurfaceContainer : lightSurface,
      surfaceContainerHigh: isDark ? darkSurfaceContainer : lightSurface,
      surfaceContainerHighest:
          isDark ? darkSurfaceContainer : const Color(0xFFECEFF1),
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    return base.copyWith(
      scaffoldBackgroundColor: isDark ? darkScaffold : lightScaffold,
      textTheme: base.textTheme.copyWith(
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -.8,
          height: 1.25,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 20,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.5),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.45)
            : Colors.white.withValues(alpha: 0.7),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: scheme.primary,
            width: 1.8,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: (themeType == AppThemeType.teaFluo && isDark)
              ? const Color(0xFF032213)
              : Colors.white,
          minimumSize: const Size(48, 54),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          side: BorderSide(
            color: scheme.primary.withValues(alpha: isDark ? 0.35 : 0.45),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
