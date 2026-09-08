import 'dart:io';
import 'package:flutter/services.dart';

class ForegroundServiceManager {
  static const MethodChannel _channel =
      MethodChannel('com.p2p.call.client/foreground_service');

  static Future<void> startCallForeground(String peerId) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('startCallService', {'peerId': peerId});
    } catch (e) {
      // Ignored if platform doesn't support
    }
  }

  static Future<void> stopCallForeground() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stopCallService');
    } catch (e) {
      // Ignored
    }
  }
}
