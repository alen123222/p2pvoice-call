import 'package:client/models/input_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('identity rules match server protocol', () {
    for (final id in ['user_123', 'a.b-c', 'ABC']) {
      expect(InputValidation.userId(id), isTrue);
    }
    for (final id in ['', 'a b', '用户', 'x' * 65]) {
      expect(InputValidation.userId(id), isFalse);
    }
  });
  test('network settings reject invalid protocols and credentials in URLs', () {
    expect(InputValidation.signalingUrl('wss://example.com/signal'), isTrue);
    for (final url in [
      'https://example.com',
      'ws://',
      'ws://user:pass@example.com',
      'ws://example.com/#token',
    ]) {
      expect(InputValidation.signalingUrl(url), isFalse);
    }
    expect(InputValidation.stunServer('stun:example.com:3478'), isTrue);
    expect(InputValidation.stunServer('example.com:3478'), isTrue);
    expect(InputValidation.stunServer('https://example.com'), isFalse);
  });
}
