import 'package:flutter/material.dart';

/// 四大东方国色专属主题类型
enum AppThemeType {
  sakuraSmoke, // 1. 柔樱粉 & 白烟色
  cloudRiver,  // 2. 缃云黄 & 晴川蓝
  roseAmber,   // 3. 玫瑰紫 & 琥珀金
  teaFluo,     // 4. 茶绿 & 荧光蓝
}

final ValueNotifier<bool> isDarkModeNotifier = ValueNotifier<bool>(true);
final ValueNotifier<AppThemeType> currentThemeTypeNotifier =
    ValueNotifier<AppThemeType>(AppThemeType.teaFluo);

/// 主题配色包 (Theme Color Package)
class ThemeColorPack {
  final String id;
  final String name;
  final Color primary;
  final Color secondary;
  final LinearGradient gradient;
  final LinearGradient buttonGradient;
  final Color darkBgStart;
  final Color darkBgEnd;
  final Color lightBgStart;
  final Color lightBgEnd;
  final Color darkTextPrimary;
  final Color lightTextPrimary;
  final Color darkGlassTint;
  final Color lightGlassTint;
  final Color darkGlassBorder;
  final Color lightGlassBorder;

  const ThemeColorPack({
    required this.id,
    required this.name,
    required this.primary,
    required this.secondary,
    required this.gradient,
    required this.buttonGradient,
    required this.darkBgStart,
    required this.darkBgEnd,
    required this.lightBgStart,
    required this.lightBgEnd,
    required this.darkTextPrimary,
    required this.lightTextPrimary,
    required this.darkGlassTint,
    required this.lightGlassTint,
    required this.darkGlassBorder,
    required this.lightGlassBorder,
  });
}

class AppTheme {
  // ==========================================
  // 四大国色专属主题定义
  // ==========================================

  // 1. 柔樱白烟 (Sakura & White Smoke)
  static const ThemeColorPack sakuraSmokePack = ThemeColorPack(
    id: 'sakuraSmoke',
    name: '柔樱 · 白烟',
    primary: Color(0xFFF8B5D0), // 柔樱粉
    secondary: Color(0xFFF5F5F5), // 白烟色
    gradient: LinearGradient(
      colors: [Color(0xFFF8B5D0), Color(0xFFF5F5F5)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    buttonGradient: LinearGradient(
      colors: [Color(0xFFF472B6), Color(0xFFF8B5D0), Color(0xFFFDA4AF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    darkBgStart: Color(0xFF180E14),
    darkBgEnd: Color(0xFF0F0B10),
    lightBgStart: Color(0xFFFFF0F5),
    lightBgEnd: Color(0xFFF5F5F5),
    darkTextPrimary: Color(0xFFFFF1F5),
    lightTextPrimary: Color(0xFF4A1528),
    darkGlassTint: Color(0x3B2D1220),
    lightGlassTint: Color(0xD8FFFFFF),
    darkGlassBorder: Color(0x55F8B5D0),
    lightGlassBorder: Color(0x75F8B5D0),
  );

  // 2. 缃云晴川 (Cloud Yellow & River Blue)
  static const ThemeColorPack cloudRiverPack = ThemeColorPack(
    id: 'cloudRiver',
    name: '缃云 · 晴川',
    primary: Color(0xFFF4DC84), // 缃云黄
    secondary: Color(0xFF79BEDF), // 晴川蓝
    gradient: LinearGradient(
      colors: [Color(0xFFF4DC84), Color(0xFF79BEDF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    buttonGradient: LinearGradient(
      colors: [Color(0xFF38BDF8), Color(0xFF79BEDF), Color(0xFFF4DC84)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    darkBgStart: Color(0xFF0B141F),
    darkBgEnd: Color(0xFF060D15),
    lightBgStart: Color(0xFFF0F9FF),
    lightBgEnd: Color(0xFFFEF9C3),
    darkTextPrimary: Color(0xFFF0F9FF),
    lightTextPrimary: Color(0xFF0C4A6E),
    darkGlassTint: Color(0x3B102336),
    lightGlassTint: Color(0xD8FFFFFF),
    darkGlassBorder: Color(0x5579BEDF),
    lightGlassBorder: Color(0x7579BEDF),
  );

  // 3. 玫瑰琥珀 (Rose Purple & Amber Gold)
  static const ThemeColorPack roseAmberPack = ThemeColorPack(
    id: 'roseAmber',
    name: '玫瑰 · 琥珀',
    primary: Color(0xFF66023C), // 玫瑰紫
    secondary: Color(0xFFFFBF00), // 琥珀金
    gradient: LinearGradient(
      colors: [Color(0xFF66023C), Color(0xFFFFBF00)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    buttonGradient: LinearGradient(
      colors: [Color(0xFF831843), Color(0xFFB45309), Color(0xFFFFBF00)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    darkBgStart: Color(0xFF190410),
    darkBgEnd: Color(0xFF0B0108),
    lightBgStart: Color(0xFFFFFBEB),
    lightBgEnd: Color(0xFFFDF2F8),
    darkTextPrimary: Color(0xFFFEF3C7),
    lightTextPrimary: Color(0xFF500724),
    darkGlassTint: Color(0x3B34061F),
    lightGlassTint: Color(0xD8FFFFFF),
    darkGlassBorder: Color(0x55FFBF00),
    lightGlassBorder: Color(0x75B45309),
  );

  // 4. 茶绿荧蓝 (Tea Green & Fluorescent Blue)
  static const ThemeColorPack teaFluoPack = ThemeColorPack(
    id: 'teaFluo',
    name: '茶绿 · 荧蓝',
    primary: Color(0xFFD3FFAF), // 茶绿
    secondary: Color(0xFF05A5FA), // 荧光蓝
    gradient: LinearGradient(
      colors: [Color(0xFFD3FFAF), Color(0xFF05A5FA)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    buttonGradient: LinearGradient(
      colors: [Color(0xFF05A5FA), Color(0xFF0284C7), Color(0xFF10B981)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    darkBgStart: Color(0xFF04181A),
    darkBgEnd: Color(0xFF020E10),
    lightBgStart: Color(0xFFF0FDF4),
    lightBgEnd: Color(0xFFF0F9FF),
    darkTextPrimary: Color(0xFFF0FDF4),
    lightTextPrimary: Color(0xFF064E3B),
    darkGlassTint: Color(0x3B06292B),
    lightGlassTint: Color(0xD8FFFFFF),
    darkGlassBorder: Color(0x5505A5FA),
    lightGlassBorder: Color(0x7505A5FA),
  );

  /// 根据主题枚举获取色彩包
  static ThemeColorPack getPack(AppThemeType type) {
    switch (type) {
      case AppThemeType.sakuraSmoke:
        return sakuraSmokePack;
      case AppThemeType.cloudRiver:
        return cloudRiverPack;
      case AppThemeType.roseAmber:
        return roseAmberPack;
      case AppThemeType.teaFluo:
        return teaFluoPack;
    }
  }

  // 语义通用色彩 (Shared Semantics)
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color callGreen = Color(0xFF10B981);

  // 兼容老代码的静态别名
  static const Color sakuraPink = Color(0xFFF8B5D0);
  static const Color whiteSmoke = Color(0xFFF5F5F5);
  static const Color cloudYellow = Color(0xFFF4DC84);
  static const Color riverBlue = Color(0xFF79BEDF);
  static const Color rosePurple = Color(0xFF66023C);
  static const Color amberGold = Color(0xFFFFBF00);
  static const Color teaGreen = Color(0xFFD3FFAF);
  static const Color fluoBlue = Color(0xFF05A5FA);

  static const Color darkBg = Color(0xFF0B141F);
  static const Color darkCard = Color(0xFF101B2B);
  static const Color darkBorder = Color(0xFF1E293B);
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkAccent = Color(0xFF79BEDF);

  static const Color lightBg = Color(0xFFF0F9FF);
  static const Color lightCard = Colors.white;
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightTextPrimary = Color(0xFF0C4A6E);
  static const Color lightTextSecondary = Color(0xFF64748B);
  static const Color lightAccent = Color(0xFF0284C7);

  static const Color skyBg = lightBg;
  static const Color skyCard = lightCard;
  static const Color skyBorder = lightBorder;
  static const Color skyTextPrimary = lightTextPrimary;
  static const Color skyTextSecondary = lightTextSecondary;
  static const Color skyAccent = lightAccent;
  static const Color skyButton = fluoBlue;
  static const Color primaryButtonDark = fluoBlue;

  static final LinearGradient sakuraSmokeGradient = sakuraSmokePack.gradient;
  static final LinearGradient cloudRiverGradient = cloudRiverPack.gradient;
  static final LinearGradient roseAmberGradient = roseAmberPack.gradient;
  static final LinearGradient teaFluoGradient = teaFluoPack.gradient;
  static final LinearGradient dialButtonGradient = cloudRiverPack.buttonGradient;
  static const LinearGradient peerCallGradient = LinearGradient(
    colors: [Color(0xFF05A5FA), Color(0xFF79BEDF)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static ThemeData getTheme(bool isDark, {AppThemeType themeType = AppThemeType.cloudRiver}) {
    final pack = getPack(themeType);
    if (isDark) {
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: pack.darkBgEnd,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        colorScheme: ColorScheme.dark(
          primary: pack.secondary,
          secondary: pack.primary,
          surface: pack.darkBgStart,
          onSurface: pack.darkTextPrimary,
          error: danger,
        ),
      );
    } else {
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: pack.lightBgStart,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: pack.lightTextPrimary,
          elevation: 0,
        ),
        colorScheme: ColorScheme.light(
          primary: pack.secondary,
          secondary: pack.primary,
          surface: pack.lightBgEnd,
          onSurface: pack.lightTextPrimary,
          error: danger,
        ),
      );
    }
  }
}
