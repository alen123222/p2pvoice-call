import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/call_state.dart';
import '../models/input_validation.dart';

class PeerInfo {
  final String userId;
  final String avatar;

  /// Raw base64 image for a peer's custom avatar, or null for preset avatars.
  final String? avatarImage;

  PeerInfo({required this.userId, required this.avatar, this.avatarImage});

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
  SignalingService({
    this.heartbeatInterval = const Duration(seconds: 15),
    this.heartbeatTimeout = const Duration(seconds: 40),
    this.registrationTimeout = const Duration(seconds: 12),
  });
  final Duration heartbeatInterval;
  final Duration heartbeatTimeout;
  final Duration registrationTimeout;
  DateTime? _nextTurnRefresh;
  WebSocketChannel? _channel;
  int _generation = 0;
  bool _disposed = false;
  bool _connecting = false;
  Timer? _registrationTimer;
  DateTime? _lastPong;
  StreamSubscription<dynamic>? _channelSub;
  String? _serverUrl;
  String? _myUserId;
  String _myAvatar = 'pilot';
  String? _myAvatarImage;
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
  Function(
    String from,
    String avatar,
    String? avatarImage,
    Map<String, dynamic>? payload,
  )?
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
  String? get myAvatarImage => _myAvatarImage;
  String? get serverUrl => _serverUrl;

  /// Optional shared access token; when set, it is attached to registration.
  void setAuthToken(String? token) {
    _authToken = (token == null || token.trim().isEmpty) ? null : token.trim();
  }

  Future<void> connect(
    String url,
    String userId, {
    String avatar = 'pilot',
    String? avatarImage,
  }) async {
    if (_disposed) return;
    if (!InputValidation.signalingUrl(url) || !InputValidation.userId(userId)) {
      _statusController.add(SignalingStatus.error);
      onErrorOccurred?.call('Invalid server URL or user ID');
      return;
    }
    final generation = ++_generation;
    _serverUrl = url;
    _myUserId = userId;
    _myAvatar = avatar;
    _myAvatarImage = avatarImage;
    _isManualDisconnect = false;
    _reconnectTimer?.cancel();
    _isReconnecting = false;
    _connecting = true;
    _statusController.add(SignalingStatus.connecting);
    await _closeChannelOnly();
    if (_disposed || generation != _generation) return;
    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;
      // Observe ready immediately; a failed handshake must not produce an
      // unhandled Future error alongside the stream error.
      final ready = channel.ready.timeout(const Duration(seconds: 12));
      _channelSub = channel.stream.listen(
        (message) {
          if (!_disposed && generation == _generation) {
            _handleMessage(message.toString());
          }
        },
        onDone: () {
          if (!_disposed && generation == _generation) _scheduleReconnect();
        },
        onError: (Object error) {
          if (!_disposed && generation == _generation) _scheduleReconnect();
        },
        cancelOnError: true,
      );
      await ready;
      if (_disposed || generation != _generation || _isManualDisconnect) return;
      _registrationPending = true;
      _send({
        'type': 'register',
        'userId': _myUserId,
        'avatar': _myAvatar,
        if (_myAvatarImage?.isNotEmpty == true) 'avatarImage': _myAvatarImage,
        if (_authToken != null) 'token': _authToken,
      });
      _registrationTimer = Timer(registrationTimeout, () {
        if (!_disposed && generation == _generation && _registrationPending) {
          _scheduleReconnect();
        }
      });
    } catch (error) {
      if (!_disposed && generation == _generation) _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed || _isManualDisconnect || _isReconnecting) return;
    _generation++;
    unawaited(_closeChannelOnly());
    _isConnected = false;
    _connecting = false;
    _registrationPending = false;
    _registrationTimer?.cancel();
    _heartbeatTimer?.cancel();
    _isReconnecting = true;
    _statusController.add(SignalingStatus.reconnecting);

    _reconnectAttempts = min(_reconnectAttempts + 1, 5);
    // Exponential backoff capped at 30 seconds.
    final delaySec = min(30, max(1, pow(2, _reconnectAttempts).toInt()));
    debugPrint(
      '[Signaling] Network switched or lost. Auto-reconnecting in $delaySec s '
      '(attempt $_reconnectAttempts)...',
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      _isReconnecting = false;
      if (!_isManualDisconnect && _serverUrl != null && _myUserId != null) {
        connect(
          _serverUrl!,
          _myUserId!,
          avatar: _myAvatar,
          avatarImage: _myAvatarImage,
        );
      }
    });
  }

  void updateProfile({
    String? newUserId,
    String? newAvatar,
    String? newAvatarImage,
  }) {
    if (newUserId != null && newUserId.trim().isNotEmpty) {
      _myUserId = newUserId.trim();
    }
    if (newAvatar != null) {
      _myAvatar = newAvatar;
      // null clears the image (e.g. switching back to a preset avatar).
      _myAvatarImage = newAvatarImage;
    }

    if (_isConnected) {
      _send({
        'type': 'register',
        'userId': _myUserId,
        'avatar': _myAvatar,
        if (_myAvatarImage != null && _myAvatarImage!.isNotEmpty)
          'avatarImage': _myAvatarImage,
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
    return _send({'type': 'call_request', 'to': targetUserId, 'payload': {}});
  }

  void sendCallAccept(String targetUserId) {
    _send({'type': 'call_accepted', 'to': targetUserId, 'payload': {}});
  }

  void sendCallReject(String targetUserId) {
    _send({'type': 'call_rejected', 'to': targetUserId, 'payload': {}});
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
    _send({'type': 'ice_candidate', 'to': targetUserId, 'payload': candidate});
  }

  void sendHangup(String targetUserId) {
    _send({'type': 'hangup', 'to': targetUserId, 'payload': {}});
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
        result.add(
          PeerInfo(
            userId: item['userId']?.toString() ?? '',
            avatar: item['avatar']?.toString() ?? 'pilot',
            avatarImage: item['avatarImage']?.toString(),
          ),
        );
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
      final avatarImage = data['avatarImage'] as String?;
      final payload = data['payload'] as Map<String, dynamic>?;

      switch (type) {
        case 'registered':
          _registrationTimer?.cancel();
          _connecting = false;
          _lastPong = DateTime.now();
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
          _lastPong = DateTime.now();
          break;

        case 'user_joined':
          onUserJoined?.call(
            PeerInfo(
              userId: data['userId']?.toString() ?? '',
              avatar: data['avatar']?.toString() ?? 'pilot',
              avatarImage: data['avatarImage']?.toString(),
            ),
          );
          break;

        case 'user_left':
          onUserLeft?.call(data['userId']?.toString() ?? '');
          break;

        case 'user_list':
          final list = _parsePeerList(data['users']);
          onUserListUpdated?.call(list);
          break;

        case 'call_request':
          onCallRequest?.call(from, avatar, avatarImage, payload);
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
          final turn = data['turn'] as Map<String, dynamic>?;
          final ttl = turn?['ttl'];
          _nextTurnRefresh = ttl is num
              ? DateTime.now().add(
                  Duration(seconds: max(1, (ttl * .8).floor())),
                )
              : null;
          onTurnConfig?.call(turn);
          break;

        case 'conflict':
          _stopRetrying();
          onErrorOccurred?.call('identityConflict');
          break;

        case 'error':
          final errMsg = data['message']?.toString() ?? 'Unknown error';
          if (_registrationPending) {
            _stopRetrying();
          }
          onErrorOccurred?.call(errMsg);
          break;
      }
    } catch (e) {
      debugPrint('[Signaling] Parse error: $e');
    }
  }

  void _stopRetrying() {
    _isManualDisconnect = true;
    _generation++;
    _connecting = false;
    _isConnected = false;
    _registrationPending = false;
    _isReconnecting = false;
    _registrationTimer?.cancel();
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    unawaited(_closeChannelOnly());
    _statusController.add(SignalingStatus.error);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (!_isConnected) return;
      if (_lastPong == null ||
          DateTime.now().difference(_lastPong!) > heartbeatTimeout) {
        _scheduleReconnect();
        return;
      }
      if (!_send({'type': 'ping'})) _scheduleReconnect();
      if (_nextTurnRefresh != null &&
          DateTime.now().isAfter(_nextTurnRefresh!)) {
        _nextTurnRefresh = DateTime.now().add(const Duration(minutes: 1));
        _send({'type': 'get_turn'});
      }
    });
  }

  void checkAndReconnect() {
    if (!_disposed &&
        !_connecting &&
        !_isReconnecting &&
        !_isConnected &&
        !_isManualDisconnect &&
        _serverUrl != null &&
        _myUserId != null) {
      connect(
        _serverUrl!,
        _myUserId!,
        avatar: _myAvatar,
        avatarImage: _myAvatarImage,
      );
    }
  }

  Future<void> _closeChannelOnly() async {
    _heartbeatTimer?.cancel();
    _registrationTimer?.cancel();
    final sub = _channelSub;
    final channel = _channel;
    _channelSub = null;
    _channel = null;
    _isConnected = false;
    try {
      await sub?.cancel();
    } catch (_) {}
    try {
      await channel?.sink.close().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> disconnect() async {
    _isManualDisconnect = true;
    _generation++;
    _connecting = false;
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
    if (_disposed) return;
    await disconnect();
    _disposed = true;
    await _statusController.close();
  }
}
