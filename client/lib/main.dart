import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'ui/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const P2PVoiceApp());
}

class P2PVoiceApp extends StatelessWidget {
  const P2PVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDark, _) {
        return MaterialApp(
          title: 'P2P 语音通话',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.getTheme(false),
          darkTheme: AppTheme.getTheme(true),
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          home: const HomePage(),
        );
      },
    );
  }
}
