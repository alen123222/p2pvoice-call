import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n/app_localizations.dart';
import 'models/avatar_model.dart';
import 'theme/app_theme.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  // Restore persisted preferences before the first frame
  final prefs = await SharedPreferences.getInstance();
  languageCodeNotifier.value = prefs.getString('language_code') ?? 'auto';
  isDarkModeNotifier.value = prefs.getBool('is_dark_mode') ?? true;

  await AvatarManager.init();

  final savedTheme = prefs.getString('theme_type');
  if (savedTheme != null) {
    try {
      currentThemeTypeNotifier.value = AppThemeType.values.firstWhere(
        (e) => e.name == savedTheme,
        orElse: () => AppThemeType.teaFluo,
      );
    } catch (_) {}
  }

  runApp(const P2PVoiceApp());
}

class P2PVoiceApp extends StatelessWidget {
  const P2PVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDark, _) {
        return ValueListenableBuilder<AppThemeType>(
          valueListenable: currentThemeTypeNotifier,
          builder: (context, themeType, _) {
            return ValueListenableBuilder<String>(
              valueListenable: languageCodeNotifier,
              builder: (context, languageCode, _) {
                return MaterialApp(
                  title: 'P2P Voice Call',
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.getTheme(false, themeType: themeType),
                  darkTheme: AppTheme.getTheme(true, themeType: themeType),
                  themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
                  locale: resolveLocale(languageCode),
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates: const [
                    AppLocalizations.delegate,
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  home: const HomePage(),
                );
              },
            );
          },
        );
      },
    );
  }
}
