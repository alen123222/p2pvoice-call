import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/call_state.dart';

class PeerInfo {
  final String userId;
  final String avatar;

  PeerInfo({required this.userId, required this.avatar});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PeerInfo &&
          runtimeType == other.runtimeType &&
          userId == other.userId;

  @override
  int get hashCode => userId.hashCode;
}

class SignalingService {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSub;
  String? _serverUrl;
  String? _myUserId;
  String _myAvatar = 'pilot';
  String? _authToken;
  bool _isConnected = false;
  bool _registrationPending = false;
  bool _isManualDisconnect = false;

  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int _reconnectAttempts = 0;
  bool _isReconnecting = false;

  final StreamController<SignalingStatus> _statusController =
      StreamController<SignalingStatus>.broadcast();
  Stream<SignalingStatus> get statusStream => _statusController.stream;

  // Callbacks
  Function(String myId, List<PeerInfo> onlineUsers)? onRegistered;
  Function(PeerInfo user)? onUserJoined;
  Function(String userId)? onUserLeft;
  Function(List<PeerInfo> users)? onUserListUpdated;
  Function(String from, String avatar, Map<String, dynamic>? payload)?
      onCallRequest;
  Function(String from)? onCallAccepted;
  Function(String from)? onCallRejected;
  Function(String from, String sdp)? onOfferReceived;
  Function(String from, String sdp)? onAnswerReceived;
  Function(String from, Map<String, dynamic> candidate)? onIceCandidateReceived;
  Function(String from)? onHangupReceived;
  Function(String target, String message)? onUserOffline;
  Function(Map<String, dynamic>? config)? onTurnConfig;
  Function(String error)? onErrorOccurred;

  bool get isConnected => _isConnected;
  String? get myUserId => _myUserId;
  String get myAvatar => _myAvatar;
  String? get serverUrl => _serverUrl;

  /// Optional shared access token; when set, it is attached to registration.
  void setAuthToken(String? token) {
    _authToken = (token == null || token.trim().isEmpty) ? null : token.trim();
  }

  Future<void> connect(
    String url,
    String userId, {
    String avatar = 'pilot',
  }) async {
    _serverUrl = url;
    _myUserId = userId;
    _myAvatar = avatar;
    _isManualDisconnect = false;
    _reconnectTimer?.cancel();

    _statusController.add(SignalingStatus.connecting);

    await _closeChannelOnly();

    try {
      final uri = Uri.parse(url);
      _channel = WebSocketChannel.connect(uri);

      _channelSub = _channel!.stream.listen(
        (message) {
          _handleMessage(message.toString());
        },
        onDone: () {
          _isConnected = false;
          debugPrint('[Signaling] WebSocket connection closed.');
          if (!_isManualDisconnect) {
            _scheduleReconnect();
          } else {
            _statusController.add(SignalingStatus.disconnected);
          }
        },
        onError: (err) {
          _isConnected = false;
          debugPrint('[Signaling] WebSocket error: $err');
          if (!_isManualDisconnect) {
            _scheduleReconnect();
          } else {
            _statusController.add(SignalingStatus.error);
            onErrorOccurred?.call('WebSocket error: $err');
          }
        },
        cancelOnError: true,
      );

      // Send registration message; 'connected' status is only emitted once the
      // server acknowledges with 'registered'.
      _registrationPending = true;
      final sent = _send({
        'type': 'register',
        'userId': _myUserId,
        'avatar': _myAvatar,
        if (_authToken != null) 'token': _authToken,
      });
      if (!sent) {
        _registrationPending = false;
        throw StateError('Failed to send registration message');
      }
    } catch (e) {
      _isConnected = false;
      _registrationPending = false;
      if (!_isManualDisconnect) {
        _scheduleReconnect();
      } else {
        _statusController.add(SignalingStatus.error);
        onErrorOccurred?.call('Connection failed: $e');
      }
    }
  }

  void _scheduleReconnect() {
    if (_isManualDisconnect || _isReconnecting) return;
    _isReconnecting = true;
    _statusController.add(SignalingStatus.reconnecting);

    _reconnectAttempts++;
    // Exponential backoff capped at 30 seconds.
    final delaySec = min(30, max(1, pow(2, _reconnectAttempts).toInt()));
    debugPrint(
        '[Signaling] Network switched or lost. Auto-reconnecting in $delaySec s '
        '(attempt $_reconnectAttempts)...');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      _isReconnecting = false;
      if (!_isManualDisconnect && _serverUrl != null && _myUserId != null) {
        connect(_serverUrl!, _myUserId!, avatar: _myAvatar);
      }
    });
  }

  void updateProfile({String? newUserId, String? newAvatar}) {
    if (newUserId != null && newUserId.trim().isNotEmpty) {
      _myUserId = newUserId.trim();
    }
    if (newAvatar != null) {
      _myAvatar = newAvatar;
    }

    if (_isConnected) {
      _send({
        'type': 'register',
        'userId': _myUserId,
        'avatar': _myAvatar,
        if (_authToken != null) 'token': _authToken,
      });
    }
  }

  void refreshUsers() {
    if (_isConnected) {
      _send({'type': 'get_users'});
    }
  }

  bool sendCallRequest(String targetUserId) {
    if (!_isConnected) return false;
    return _send({
      'type': 'call_request',
      'to': targetUserId,
      'payload': {},
    });
  }

  void sendCallAccept(String targetUserId) {
    _send({
      'type': 'call_accepted',
      'to': targetUserId,
      'payload': {},
    });
  }

  void sendCallReject(String targetUserId) {
    _send({
      'type': 'call_rejected',
      'to': targetUserId,
      'payload': {},
    });
  }

  void sendOffer(String targetUserId, String sdp) {
    _send({
      'type': 'offer',
      'to': targetUserId,
      'payload': {'sdp': sdp},
    });
  }

  void sendAnswer(String targetUserId, String sdp) {
    _send({
      'type': 'answer',
      'to': targetUserId,
      'payload': {'sdp': sdp},
    });
  }

  void sendIceCandidate(String targetUserId, Map<String, dynamic> candidate) {
    _send({
      'type': 'ice_candidate',
      'to': targetUserId,
      'payload': candidate,
    });
  }

  void sendHangup(String targetUserId) {
    _send({
      'type': 'hangup',
      'to': targetUserId,
      'payload': {},
    });
  }

  bool _send(Map<String, dynamic> data) {
    final channel = _channel;
    if (channel == null) return false;
    try {
      final jsonString = jsonEncode(data);
      channel.sink.add(jsonString);
      return true;
    } catch (e) {
      debugPrint('[Signaling] Failed to send message: $e');
      return false;
    }
  }

  List<PeerInfo> _parsePeerList(dynamic rawList) {
    if (rawList is! List) return [];
    final List<PeerInfo> result = [];
    for (final item in rawList) {
      if (item is Map) {
        result.add(PeerInfo(
          userId: item['userId']?.toString() ?? '',
          avatar: item['avatar']?.toString() ?? 'pilot',
        ));
      } else if (item is String) {
        result.add(PeerInfo(userId: item, avatar: 'pilot'));
      }
    }
    return result;
  }

  void _handleMessage(String message) {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      final type = data['type'] as String?;
      final from = data['from'] as String? ?? '';
      final avatar = data['avatar'] as String? ?? 'pilot';
      final payload = data['payload'] as Map<String, dynamic>?;

      switch (type) {
        case 'registered':
          _registrationPending = false;
          _isConnected = true;
          _reconnectAttempts = 0;
          _isReconnecting = false;
          _statusController.add(SignalingStatus.connected);
          _startHeartbeat();
          final online = _parsePeerList(data['onlineUsers']);
          onRegistered?.call(data['userId']?.toString() ?? '', online);
          // Request time-limited TURN credentials (TURN REST API).
          _send({'type': 'get_turn'});
          break;

        case 'pong':
          // Keep-alive heartbeat acknowledged by signaling server
          break;

        case 'user_joined':
          onUserJoined?.call(PeerInfo(
            userId: data['userId']?.toString() ?? '',
            avatar: data['avatar']?.toString() ?? 'pilot',
          ));
          break;

        case 'user_left':
          onUserLeft?.call(data['userId']?.toString() ?? '');
          break;

        case 'user_list':
          final list = _parsePeerList(data['users']);
          onUserListUpdated?.call(list);
          break;

        case 'call_request':
          onCallRequest?.call(from, avatar, payload);
          break;

        case 'call_accepted':
          onCallAccepted?.call(from);
          break;

        case 'call_rejected':
          onCallRejected?.call(from);
          break;

        case 'offer':
          if (payload != null && payload['sdp'] != null) {
            onOfferReceived?.call(from, payload['sdp'].toString());
          }
          break;

        case 'answer':
          if (payload != null && payload['sdp'] != null) {
            onAnswerReceived?.call(from, payload['sdp'].toString());
          }
          break;

        case 'ice_candidate':
          if (payload != null) {
            onIceCandidateReceived?.call(from, payload);
          }
          break;

        case 'hangup':
          onHangupReceived?.call(from);
          break;

        case 'user_offline':
          onUserOffline?.call(
            data['target']?.toString() ?? '',
            data['message']?.toString() ?? '',
          );
          break;

        case 'turn_config':
          onTurnConfig?.call(data['turn'] as Map<String, dynamic>?);
          break;

        case 'error':
          final errMsg = data['message']?.toString() ?? 'Unknown error';
          if (_registrationPending) {
            _registrationPending = false;
            _isConnected = false;
            _statusController.add(SignalingStatus.error);
          }
          onErrorOccurred?.call(errMsg);
          break;
      }
    } catch (e) {
      debugPrint('[Signaling] Parse error: $e');
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (_isConnected) {
        final sent = _send({'type': 'ping'});
        if (!sent) {
          _scheduleReconnect();
        }
      } else if (!_isManualDisconnect && _serverUrl != null && _myUserId != null) {
        checkAndReconnect();
      }
    });
  }

  void checkAndReconnect() {
    if (!_isConnected &&
        !_isManualDisconnect &&
        _serverUrl != null &&
        _myUserId != null) {
      connect(_serverUrl!, _myUserId!, avatar: _myAvatar);
    }
  }

  Future<void> _closeChannelOnly() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _channelSub?.cancel();
    _channelSub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _isConnected = false;
  }

  Future<void> disconnect() async {
    _isManualDisconnect = true;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _isReconnecting = false;

    // Send unregister notice to server
    _send({'type': 'unregister'});

    await _closeChannelOnly();
    _statusController.add(SignalingStatus.disconnected);
  }

  Future<void> dispose() async {
    await disconnect();
    await _statusController.close();
  }
}
