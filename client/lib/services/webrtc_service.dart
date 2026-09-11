import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/call_state.dart';
import 'signaling_service.dart';

/// Thrown when the microphone permission is not granted.
class _MicPermissionException implements Exception {
  const _MicPermissionException();
}

class WebRTCService {
  final SignalingService signalingService;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  String? _currentPeerId;
  bool _isCaller = false;
  bool _isMuted = false;
  bool _isSpeakerphoneOn = false;

  CallStatus _callStatus = CallStatus.idle;

  // ICE Candidates queue to prevent premature candidate dropping
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  bool _isRemoteDescriptionSet = false;

  // Serializes cleanup so a rapid hangup + redial cannot race.
  Future<void> _cleanupFuture = Future.value();
  Timer? _ringTimer;

  final StreamController<CallStatus> _callStatusController =
      StreamController<CallStatus>.broadcast();
  Stream<CallStatus> get callStatusStream => _callStatusController.stream;

  final StreamController<String> _iceStateController =
      StreamController<String>.broadcast();
  Stream<String> get iceStateStream => _iceStateController.stream;

  String _currentIceState = 'Idle';
  String get currentIceState => _currentIceState;

  String _connectionType = 'Unknown';
  String get connectionType => _connectionType;

  /// UI feedback callbacks. The argument is a localization key resolved by the
  /// UI layer, so this service stays free of BuildContext / l10n deps.
  Function(String key)? onError;
  Function(String key)? onNotice;

  // STUN servers require no secret. The user-configured server is prepended.
  List<String> stunServers = [
    'stun:170.106.195.109:3478',
    'stun:stun.l.google.com:19302',
  ];

  // TURN credentials are fetched from the signaling server (TURN REST API) so
  // no shared secret is embedded in the client binary.
  Map<String, dynamic>? _turnConfig;

  String _remotePeerAvatar = 'pilot';
  String get remotePeerAvatar => _remotePeerAvatar;

  String? _remotePeerAvatarImage;
  String? get remotePeerAvatarImage => _remotePeerAvatarImage;

  WebRTCService({required this.signalingService}) {
    _bindSignalingEvents();
  }

  bool get isMuted => _isMuted;
  bool get isSpeakerphoneOn => _isSpeakerphoneOn;
  String? get currentPeerId => _currentPeerId;
  bool get isCaller => _isCaller;

  void updateStunServer(String stunAddress) {
    final cleaned = stunAddress.trim();
    if (cleaned.isEmpty) return;
    final formatted = cleaned.startsWith('stun:') ? cleaned : 'stun:$cleaned';
    if (!stunServers.contains(formatted)) {
      stunServers.insert(0, formatted);
    }
  }

  void setRemotePeerAvatar(String avatar) {
    _remotePeerAvatar = avatar;
  }

  void _setCallStatus(CallStatus status) {
    _callStatus = status;
    _callStatusController.add(status);
  }

  void _bindSignalingEvents() {
    signalingService.onTurnConfig = (config) {
      if (config != null && config.isNotEmpty && config['username'] != null) {
        _turnConfig = config;
      } else {
        _turnConfig = null;
      }
    };

    signalingService.onCallRequest = (from, avatar, avatarImage, payload) {
      // Auto-decline when already busy in another call.
      if (_callStatus == CallStatus.calling ||
          _callStatus == CallStatus.connected ||
          _callStatus == CallStatus.incoming) {
        signalingService.sendCallReject(from);
        return;
      }
      _currentPeerId = from;
      _remotePeerAvatar = avatar;
      _remotePeerAvatarImage = avatarImage;
      _isCaller = false;
      _setCallStatus(CallStatus.incoming);
    };

    signalingService.onCallAccepted = (from) async {
      if (_currentPeerId == from &&
          _isCaller &&
          _callStatus == CallStatus.calling) {
        _armRingTimer(); // reset timeout while connecting
        await _createAndSendOffer(from);
      }
    };

    signalingService.onCallRejected = (from) {
      if (_currentPeerId == from) {
        _cancelRingTimer();
        _cleanupCall();
        onNotice?.call('callRejected');
        _setCallStatus(CallStatus.idle);
      }
    };

    signalingService.onOfferReceived = (from, sdp) async {
      _currentPeerId = from;
      _isCaller = false;
      await _handleRemoteOffer(from, sdp);
    };

    signalingService.onAnswerReceived = (from, sdp) async {
      if (_currentPeerId == from) {
        await _handleRemoteAnswer(sdp);
      }
    };

    signalingService.onIceCandidateReceived = (from, candidateMap) async {
      if (_currentPeerId == from) {
        await _handleRemoteCandidate(candidateMap);
      }
    };

    signalingService.onHangupReceived = (from) async {
      if (_currentPeerId == from) {
        _cancelRingTimer();
        await _cleanupCall();
        onNotice?.call('peerHangup');
        _setCallStatus(CallStatus.ended);
      }
    };

    signalingService.onUserOffline = (target, message) async {
      if (_currentPeerId == target) {
        _cancelRingTimer();
        await _cleanupCall();
        onNotice?.call('peerOffline');
        _setCallStatus(CallStatus.ended);
      }
    };
  }

  Map<String, dynamic> _createIceServersConfig() {
    final List<Map<String, dynamic>> iceServers = [
      {'urls': stunServers},
    ];

    final turn = _turnConfig;
    if (turn != null &&
        turn['username'] != null &&
        turn['credential'] != null &&
        turn['uris'] is List) {
      iceServers.add({
        'urls': (turn['uris'] as List).cast<String>(),
        'username': turn['username'],
        'credential': turn['credential'],
      });
    }

    return {
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
      'iceTransportPolicy': 'all',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    };
  }

  Future<void> startCall(String targetUserId) async {
    if (!signalingService.isConnected) {
      onError?.call('notConnected');
      return;
    }
    _currentPeerId = targetUserId;
    _isCaller = true;
    _setCallStatus(CallStatus.calling);
    _armRingTimer();
    signalingService.sendCallRequest(targetUserId);
  }

  Future<void> acceptCall() async {
    if (_currentPeerId == null) return;
    _setCallStatus(CallStatus.calling);
    signalingService.sendCallAccept(_currentPeerId!);
  }

  Future<void> rejectCall() async {
    if (_currentPeerId != null) {
      signalingService.sendCallReject(_currentPeerId!);
    }
    _cancelRingTimer();
    await _cleanupCall();
    _setCallStatus(CallStatus.idle);
  }

  void _armRingTimer() {
    _cancelRingTimer();
    _ringTimer = Timer(const Duration(seconds: 45), () {
      if (_callStatus == CallStatus.calling) {
        if (_currentPeerId != null) {
          signalingService.sendHangup(_currentPeerId!);
        }
        _cleanupCall();
        onNotice?.call('noAnswer');
        _setCallStatus(CallStatus.idle);
      }
    });
  }

  void _cancelRingTimer() {
    _ringTimer?.cancel();
    _ringTimer = null;
  }

  Future<void> _createAndSendOffer(String targetUserId) async {
    try {
      await _initPeerConnection();
      final RTCSessionDescription offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });
      await _peerConnection!.setLocalDescription(offer);
      signalingService.sendOffer(targetUserId, offer.sdp ?? '');
    } catch (e) {
      _handleCallFailure(e);
    }
  }

  Future<void> _handleRemoteOffer(String from, String sdp) async {
    try {
      await _initPeerConnection();
      final description = RTCSessionDescription(sdp, 'offer');
      await _peerConnection!.setRemoteDescription(description);
      await _drainPendingCandidates();

      final RTCSessionDescription answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });
      await _peerConnection!.setLocalDescription(answer);
      signalingService.sendAnswer(from, answer.sdp ?? '');
    } catch (e) {
      _handleCallFailure(e);
    }
  }

  Future<void> _handleRemoteAnswer(String sdp) async {
    try {
      if (_peerConnection == null) return;
      final description = RTCSessionDescription(sdp, 'answer');
      await _peerConnection!.setRemoteDescription(description);
      await _drainPendingCandidates();
    } catch (e) {
      _handleCallFailure(e);
    }
  }

  void _handleCallFailure(Object e) {
    debugPrint('[WebRTC] Call failure: $e');
    _cancelRingTimer();
    if (_currentPeerId != null) {
      signalingService.sendHangup(_currentPeerId!);
    }
    _cleanupCall();
    if (e is _MicPermissionException) {
      onError?.call('micDenied');
    } else {
      onError?.call('callFailed');
    }
    _setCallStatus(CallStatus.idle);
  }

  Future<void> _handleRemoteCandidate(Map<String, dynamic> candidateMap) async {
    final candStr = candidateMap['candidate'];
    if (candStr == null || candStr.toString().trim().isEmpty) return;

    final candidate = RTCIceCandidate(
      candStr,
      candidateMap['sdpMid'],
      candidateMap['sdpMLineIndex'],
    );

    if (_peerConnection != null && _isRemoteDescriptionSet) {
      try {
        await _peerConnection!.addCandidate(candidate);
      } catch (_) {}
    } else {
      _pendingRemoteCandidates.add(candidate);
    }
  }

  Future<void> _drainPendingCandidates() async {
    _isRemoteDescriptionSet = true;
    if (_peerConnection != null && _pendingRemoteCandidates.isNotEmpty) {
      for (final candidate in _pendingRemoteCandidates) {
        try {
          await _peerConnection!.addCandidate(candidate);
        } catch (_) {}
      }
      _pendingRemoteCandidates.clear();
    }
  }

  Future<void> _initPeerConnection() async {
    await _cleanupCall();

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      throw const _MicPermissionException();
    }

    // Capture local audio with Opus, echo cancellation and noise suppression.
    final Map<String, dynamic> mediaConstraints = {
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        'highpassFilter': true,
      },
      'video': false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);

    final configuration = _createIceServersConfig();
    _peerConnection = await createPeerConnection(configuration);

    _localStream!.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    // flutter_webrtc plays remote audio tracks automatically.
    _peerConnection!.onTrack = (RTCTrackEvent event) {};

    _peerConnection!.onIceCandidate = (RTCIceCandidate? candidate) {
      if (candidate != null &&
          candidate.candidate != null &&
          candidate.candidate!.isNotEmpty &&
          _currentPeerId != null) {
        signalingService.sendIceCandidate(_currentPeerId!, {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      _currentIceState =
          state.toString().replaceAll('RTCIceConnectionState.', '');
      _iceStateController.add(_currentIceState);

      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _connectionType = 'P2P 直连已建立 (UDP/SRTP)';
        _detectConnectionType();
        _cancelRingTimer();
        _setCallStatus(CallStatus.connected);
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _connectionType = '直连穿透打洞失败 (可检查网络或TURN中继)';
      } else if (state ==
          RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _connectionType = '网络连接已中断';
      }
    };
  }

  Future<void> _detectConnectionType() async {
    if (_peerConnection == null) return;
    try {
      final stats = await _peerConnection!.getStats();
      for (final report in stats) {
        if (report.type == 'candidate-pair' &&
            report.values['state'] == 'succeeded') {
          final localCandId = report.values['localCandidateId'];
          for (final r in stats) {
            if (r.id == localCandId) {
              final candType = r.values['candidateType'];
              if (candType == 'host') {
                _connectionType = 'P2P 纯公网/IPv6直连 (零中转)';
              } else if (candType == 'srflx') {
                _connectionType = 'P2P NAT打洞直连 (STUN/UDP)';
              } else if (candType == 'relay') {
                _connectionType = '硅谷私有端到端加密穿透 (SRTP)';
              }
              _iceStateController.add(_currentIceState);
              break;
            }
          }
          break;
        }
      }
    } catch (_) {}
  }

  Future<void> toggleMute() async {
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        _isMuted = !_isMuted;
        for (final track in audioTracks) {
          track.enabled = !_isMuted;
        }
      }
    }
  }

  Future<void> toggleSpeakerphone() async {
    _isSpeakerphoneOn = !_isSpeakerphoneOn;
    await Helper.setSpeakerphoneOn(_isSpeakerphoneOn);
  }

  Future<void> hangup() async {
    _cancelRingTimer();
    if (_currentPeerId != null) {
      signalingService.sendHangup(_currentPeerId!);
    }
    await _cleanupCall();
    _setCallStatus(CallStatus.idle);
  }

  Future<void> _cleanupCall() {
    _cleanupFuture = _cleanupFuture.then((_) => _doCleanup());
    return _cleanupFuture;
  }

  Future<void> _doCleanup() async {
    _isRemoteDescriptionSet = false;
    _pendingRemoteCandidates.clear();

    try {
      _localStream?.getTracks().forEach((track) {
        track.stop();
      });
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;

    try {
      await _peerConnection?.close();
      await _peerConnection?.dispose();
    } catch (_) {}
    _peerConnection = null;

    _isMuted = false;
    _currentIceState = 'Idle';
    _connectionType = 'Unknown';
  }

  Future<void> dispose() async {
    _cancelRingTimer();
    await _cleanupCall();
    await _callStatusController.close();
    await _iceStateController.close();
  }
}
