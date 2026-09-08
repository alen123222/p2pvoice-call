import 'dart:async';
import 'dart:convert';
import 'dart:math';
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
  String? _serverUrl;
  String? _myUserId;
  String _myAvatar = 'pilot';
  bool _isConnected = false;
  bool _isManualDisconnect = false;

  Timer? _reconnectTimer;
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
  Function(String from, String avatar, Map<String, dynamic>? payload)? onCallRequest;
  Function(String from)? onCallAccepted;
  Function(String from)? onCallRejected;
  Function(String from, String sdp)? onOfferReceived;
  Function(String from, String sdp)? onAnswerReceived;
  Function(String from, Map<String, dynamic> candidate)? onIceCandidateReceived;
  Function(String from)? onHangupReceived;
  Function(String target)? onUserOffline;
  Function(String error)? onErrorOccurred;

  bool get isConnected => _isConnected;
  String? get myUserId => _myUserId;
  String get myAvatar => _myAvatar;
  String? get serverUrl => _serverUrl;

  Future<void> connect(String url, String userId, {String avatar = 'pilot'}) async {
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

      _channel!.stream.listen(
        (message) {
          _handleMessage(message.toString());
        },
        onDone: () {
          _isConnected = false;
          print('[Signaling] WebSocket connection closed.');
          if (!_isManualDisconnect) {
            _scheduleReconnect();
          } else {
            _statusController.add(SignalingStatus.disconnected);
          }
        },
        onError: (err) {
          _isConnected = false;
          print('[Signaling] WebSocket error: $err');
          if (!_isManualDisconnect) {
            _scheduleReconnect();
          } else {
            _statusController.add(SignalingStatus.error);
            onErrorOccurred?.call('WebSocket error: $err');
          }
        },
        cancelOnError: true,
      );

      // Send registration message
      _send({
        'type': 'register',
        'userId': _myUserId,
        'avatar': _myAvatar,
      });

      _isConnected = true;
      _reconnectAttempts = 0;
      _isReconnecting = false;
      _statusController.add(SignalingStatus.connected);
    } catch (e) {
      _isConnected = false;
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
    final delaySec = min(5, max(1, (_reconnectAttempts * 1.5).toInt()));
    print('[Signaling] Network switched or lost. Auto-reconnecting in $delaySec s (Attempt $_reconnectAttempts)...');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySec), () async {
      _isReconnecting = false;
      if (!_isManualDisconnect && _serverUrl != null && _myUserId != null) {
        await connect(_serverUrl!, _myUserId!, avatar: _myAvatar);
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
      });
    }
  }

  void refreshUsers() {
    if (_isConnected) {
      _send({'type': 'get_users'});
    }
  }

  void sendCallRequest(String targetUserId) {
    _send({
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

  void _send(Map<String, dynamic> data) {
    if (_channel != null) {
      try {
        final jsonString = jsonEncode(data);
        _channel!.sink.add(jsonString);
      } catch (_) {}
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
          final online = _parsePeerList(data['onlineUsers']);
          onRegistered?.call(data['userId']?.toString() ?? '', online);
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
          onUserOffline?.call(data['target']?.toString() ?? '');
          break;

        case 'error':
          onErrorOccurred?.call(data['message']?.toString() ?? 'Unknown error');
          break;
      }
    } catch (e) {
      print('[Signaling] Parse error: $e');
    }
  }

  Future<void> _closeChannelOnly() async {
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _isConnected = false;
  }

  Future<void> disconnect() async {
    _isManualDisconnect = true;
    _reconnectTimer?.cancel();
    _isReconnecting = false;

    // Send unregister notice to server
    _send({'type': 'unregister'});

    await _closeChannelOnly();
    _statusController.add(SignalingStatus.disconnected);
  }

  void dispose() {
    disconnect();
    _statusController.close();
  }
}
