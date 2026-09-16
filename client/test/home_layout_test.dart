import 'dart:io';
import 'dart:ui' as ui;

import 'package:client/controllers/call_controller.dart';
import 'package:client/l10n/app_localizations.dart';
import 'package:client/models/call_state.dart';
import 'package:client/theme/app_theme.dart';
import 'package:client/ui/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'webrtc_service_test.dart' show FakeSignaling;

void main() {
  final boundary = GlobalKey();
  Future<CallController> mount(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    String language = 'zh',
    bool dark = true,
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    final session = CallController(signaling: FakeSignaling())
      ..ready = true
      ..userId = 'user_8a9f64c1'
      ..signalingStatus = SignalingStatus.connected;
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.getTheme(dark).copyWith(
            textTheme: AppTheme.getTheme(dark).textTheme.apply(
              fontFamily: 'PreviewUI',
              fontFamilyFallback: ['PreviewCJK', 'PreviewEmoji'],
            ),
          ),
          locale: Locale(language),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: HomePage(controller: session),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  setUpAll(() async {
    if (Platform.isWindows) {
      for (final entry in {
        'PreviewUI': 'C:/Windows/Fonts/segoeui.ttf',
        'PreviewCJK': 'C:/Windows/Fonts/msyh.ttc',
        'MaterialIcons': 'D:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        'PreviewEmoji': 'C:/Windows/Fonts/seguiemj.ttf',
      }.entries) {
        if (await File(entry.value).exists()) {
          final loader = FontLoader(entry.key)
            ..addFont(
              Future.value(
                ByteData.sublistView(await File(entry.value).readAsBytes()),
              ),
            );
          await loader.load();
        }
      }
    }
  });
  tearDown(() {});
  Future<void> finish(WidgetTester tester, CallController session) async {
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
    await tester.pump();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }

  for (final size in [
    const Size(320, 640),
    const Size(844, 390),
    const Size(1100, 900),
  ]) {
    for (final language in ['zh', 'en', 'fr']) {
      testWidgets('home fits $size $language at 200% text', (tester) async {
        final session = await mount(
          tester,
          size: size,
          language: language,
          scale: 2,
        );
        expect(tester.takeException(), isNull);
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -800),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await finish(tester, session);
      });
    }
  }
  testWidgets('dial action creates one call; hangup returns to home', (
    tester,
  ) async {
    final session = await mount(tester, language: 'en');
    await tester.enterText(find.byType(TextField), 'friend');
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Call'));
    await tester.tap(find.widgetWithText(FilledButton, 'Call'));
    await tester.pumpAndSettle();
    expect(session.rtc.currentPeerId, 'friend');
    expect(find.text('Calling'), findsOneWidget);
    await tester.tap(find.byTooltip('Hang up'));
    await tester.pumpAndSettle();
    expect(session.inCall, isFalse);
    await finish(tester, session);
  });
  testWidgets(
    'settings invalid input stays editable and incoming call takes priority',
    (tester) async {
      final session = await mount(tester, language: 'en');
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'https://bad');
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Apply & Save'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Apply & Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a valid ws:// or wss:// address.'),
        findsOneWidget,
      );
      session.signaling.onCallRequest!('friend', 'pilot', null, null);
      await tester.pumpAndSettle();
      expect(find.text('Incoming P2P Call'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester, session);
    },
  );
  for (final dark in [true, false]) {
    testWidgets('render implemented home ${dark ? 'dark' : 'light'}', (
      tester,
    ) async {
      final session = await mount(tester, dark: dark);
      expect(tester.takeException(), isNull);
      if (Platform.environment['SAVE_UI_PREVIEWS'] == '1') {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('../artifacts').create(recursive: true);
          await File('../artifacts/home-${dark ? 'dark' : 'light'}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await finish(tester, session);
    });
  }
}
