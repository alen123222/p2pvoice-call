import 'package:flutter/material.dart';

// Names are persisted; keep these stable across upgrades.
enum AppThemeType { sakuraSmoke, cloudRiver, roseAmber, teaFluo }

final isDarkModeNotifier = ValueNotifier<bool>(true);
final currentThemeTypeNotifier = ValueNotifier<AppThemeType>(
  AppThemeType.teaFluo,
);

abstract final class AppTheme {
  static Color seedFor(AppThemeType type) => switch (type) {
    AppThemeType.sakuraSmoke => const Color(0xFFE84E8A),
    AppThemeType.cloudRiver => const Color(0xFF1692D0),
    AppThemeType.roseAmber => const Color(0xFFE07A28),
    AppThemeType.teaFluo => const Color(0xFF1EB57D),
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
        const Color(0xFFE84E8A),
        const Color(0xFFC04B76),
        const Color(0xFFF075AA),
        const Color(0xFF160A13),
        const Color(0xFF261220),
        const Color(0xFF33182A),
        const Color(0xFFFDF2F6),
        const Color(0xFFFFF7FA),
      ),
      AppThemeType.cloudRiver => (
        const Color(0xFF1692D0),
        const Color(0xFF2275A0),
        const Color(0xFF56B4E9),
        const Color(0xFF09131C),
        const Color(0xFF10202F),
        const Color(0xFF172D42),
        const Color(0xFFF0F6FC),
        const Color(0xFFF7FAFD),
      ),
      AppThemeType.roseAmber => (
        const Color(0xFFE07A28),
        const Color(0xFFAB5E22),
        const Color(0xFFF39C4B),
        const Color(0xFF181109),
        const Color(0xFF281C11),
        const Color(0xFF392718),
        const Color(0xFFFCF5EE),
        const Color(0xFFFFFBF7),
      ),
      AppThemeType.teaFluo => (
        const Color(0xFF1EB57D),
        const Color(0xFF228761),
        const Color(0xFF45D59E),
        const Color(0xFF091611),
        const Color(0xFF10241C),
        const Color(0xFF183327),
        const Color(0xFFEFF8F3),
        const Color(0xFFF6FAF8),
      ),
    };

    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: isDark ? Brightness.dark : Brightness.light,
    ).copyWith(
      primary: seed,
      secondary: secondary,
      tertiary: tertiary,
      surface: isDark ? darkSurface : lightSurface,
      surfaceContainer: isDark ? darkSurfaceContainer : lightSurface,
      surfaceContainerHigh: isDark ? darkSurfaceContainer : lightSurface,
      surfaceContainerHighest:
          isDark ? darkSurfaceContainer : const Color(0xFFE6EAE7),
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
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 54),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
