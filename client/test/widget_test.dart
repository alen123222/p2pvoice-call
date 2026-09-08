import 'package:flutter_test/flutter_test.dart';
import 'package:client/main.dart';

void main() {
  testWidgets('P2P App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const P2PVoiceApp());
    expect(find.text('P2P 语音直通'), findsOneWidget);
  });
}
