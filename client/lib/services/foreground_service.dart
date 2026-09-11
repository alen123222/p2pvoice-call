import 'dart:io';
import 'package:flutter/services.dart';

class ForegroundServiceManager {
  static const MethodChannel _channel =
      MethodChannel('com.p2p.call.client/foreground_service');

  static Function(String action, String peerId)? onCallAction;

  /// Initializes MethodChannel listener for incoming notification actions (Answer / Reject).
  static void initialize({Function(String action, String peerId)? handleCallAction}) {
    if (!Platform.isAndroid) return;
    onCallAction = handleCallAction;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onCallAction') {
        final action = call.arguments['action'] as String? ?? '';
        final peerId = call.arguments['peerId'] as String? ?? '';
        onCallAction?.call(action, peerId);
      }
    });

    _checkInitialAction();
  }

  static Future<void> _checkInitialAction() async {
    if (!Platform.isAndroid) return;
    try {
      final initialAction =
          await _channel.invokeMapMethod<String, dynamic>('getInitialCallAction');
      if (initialAction != null) {
        final action = initialAction['action'] as String? ?? '';
        final peerId = initialAction['peerId'] as String? ?? '';
        if (action.isNotEmpty) {
          onCallAction?.call(action, peerId);
        }
      }
    } catch (_) {}
  }

  /// Starts the quiet background keep-alive service.
  static Future<void> startKeepAliveService() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('startKeepAliveService');
    } catch (_) {}
  }

  /// Promotes to microphone foreground service while in call.
  static Future<void> startCallForeground(String peerId) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('startCallService', {'peerId': peerId});
    } catch (_) {}
  }

  /// Reverts to keep-alive background service when call ends.
  static Future<void> stopCallForeground() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stopCallService');
    } catch (_) {}
  }

  /// Shows the high-priority heads-up notification with ringtone, vibration, and Answer/Reject buttons.
  static Future<void> showIncomingCallNotification(String peerId) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('showIncomingCall', {'peerId': peerId});
    } catch (_) {}
  }

  /// Cancels the incoming call notification.
  static Future<void> cancelIncomingCallNotification() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('cancelIncomingCall');
    } catch (_) {}
  }

  /// Stops all services completely.
  static Future<void> stopAllServices() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stopAllServices');
    } catch (_) {}
  }
}
