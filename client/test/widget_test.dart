import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/l10n/app_localizations.dart';
import 'package:client/models/avatar_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AppLocalizations resolves each supported language', () {
    expect(AppLocalizations(const Locale('en')).headerTitle, 'P2P Direct Voice');
    expect(AppLocalizations(const Locale('zh')).headerTitle, 'P2P 语音直通');
    expect(AppLocalizations(const Locale('fr')).headerTitle, 'Voix directe P2P');
  });

  test('AppLocalizations falls back to English for unsupported languages', () {
    expect(AppLocalizations(const Locale('de')).headerTitle, 'P2P Direct Voice');
    expect(AppLocalizations(const Locale('en')).avatarName('pilot'), 'Pilot');
    expect(AppLocalizations(const Locale('zh')).avatarName('pilot'), '领航员');
  });

  test('AvatarManager returns a fallback avatar for unknown ids', () {
    // Identity card (isMe) falls back to the first preset.
    expect(AvatarManager.getById('missing', isMe: true).id, 'pilot');
    // Remote peers get a stable hash-mapped preset (never throws).
    final remote = AvatarManager.getById('missing', isMe: false);
    expect(AvatarManager.defaultPresets.map((a) => a.id), contains(remote.id));
  });

  testWidgets('App localizes content through the MaterialApp', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) =>
              Text(AppLocalizations.of(context)!.headerTitle),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('P2P 语音直通'), findsOneWidget);
  });
}
