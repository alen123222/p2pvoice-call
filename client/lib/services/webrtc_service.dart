import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/call_state.dart';
import 'signaling_service.dart';

class WebRTCService {
  final SignalingService signalingService;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  String? _currentPeerId;
  bool _isCaller = false;
  bool _isMuted = false;
  bool _isSpeakerphoneOn = false;

  // ICE Candidates queue to prevent premature candidate dropping
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  bool _isRemoteDescriptionSet = false;

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

  // STUN & TURN Configuration
  List<String> stunServers = [
    'stun:170.106.195.109:3478',
    'stun:stun.l.google.com:19302',
  ];

  String turnServer = '170.106.195.109:3478';
  String turnUsername = 'p2puser';
  String turnPassword = 'p2psecret2026';

  WebRTCService({required this.signalingService}) {
    _bindSignalingEvents();
  }

  bool get isMuted => _isMuted;
  bool get isSpeakerphoneOn => _isSpeakerphoneOn;
  String? get currentPeerId => _currentPeerId;
  bool get isCaller => _isCaller;
  MediaStream? get remoteStream => _remoteStream;

  void updateStunServer(String stunAddress) {
    final cleaned = stunAddress.trim();
    if (cleaned.isNotEmpty) {
      final formatted = cleaned.startsWith('stun:') ? cleaned : 'stun:$cleaned';
      if (!stunServers.contains(formatted)) {
        stunServers.insert(0, formatted);
      }
    }
  }

  String _remotePeerAvatar = 'pilot';
  String get remotePeerAvatar => _remotePeerAvatar;

  void setRemotePeerAvatar(String avatar) {
    _remotePeerAvatar = avatar;
  }

  void _bindSignalingEvents() {
    signalingService.onCallRequest = (from, avatar, payload) {
      _currentPeerId = from;
      _remotePeerAvatar = avatar;
      _isCaller = false;
      _callStatusController.add(CallStatus.incoming);
    };

    signalingService.onCallAccepted = (from) async {
      if (_currentPeerId == from && _isCaller) {
        // Callee accepted call, create WebRTC Offer
        await _createAndSendOffer(from);
      }
    };

    signalingService.onCallRejected = (from) {
      if (_currentPeerId == from) {
        _cleanupCall();
        _callStatusController.add(CallStatus.idle);
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

    signalingService.onHangupReceived = (from) {
      if (_currentPeerId == from) {
        _cleanupCall();
        _callStatusController.add(CallStatus.ended);
      }
    };

    signalingService.onUserOffline = (target) {
      if (_currentPeerId == target) {
        _cleanupCall();
        _callStatusController.add(CallStatus.ended);
      }
    };
  }

  Map<String, dynamic> _createIceServersConfig() {
    final List<Map<String, dynamic>> iceServers = [
      {
        'urls': stunServers,
      },
    ];

    // Add private TURN relay fallback (End-to-End Encrypted via DTLS-SRTP)
    if (turnServer.isNotEmpty) {
      iceServers.add({
        'urls': [
          'turn:$turnServer?transport=udp',
          'turn:$turnServer?transport=tcp',
        ],
        'username': turnUsername,
        'credential': turnPassword,
      });
    }

    return {
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
      'iceTransportPolicy': 'all', // Tests all candidates: host (IPv6/LAN), srflx (STUN), relay (TURN)
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    };
  }

  Future<void> startCall(String targetUserId) async {
    _currentPeerId = targetUserId;
    _isCaller = true;
    _callStatusController.add(CallStatus.calling);

    // Send call request to callee
    signalingService.sendCallRequest(targetUserId);
  }

  Future<void> acceptCall() async {
    if (_currentPeerId == null) return;
    _callStatusController.add(CallStatus.calling);
    signalingService.sendCallAccept(_currentPeerId!);
  }

  void rejectCall() {
    if (_currentPeerId != null) {
      signalingService.sendCallReject(_currentPeerId!);
      _cleanupCall();
      _callStatusController.add(CallStatus.idle);
    }
  }

  Future<void> _createAndSendOffer(String targetUserId) async {
    await _initPeerConnection();

    final RTCSessionDescription offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 0,
    });
    await _peerConnection!.setLocalDescription(offer);

    signalingService.sendOffer(targetUserId, offer.sdp ?? '');
  }

  Future<void> _handleRemoteOffer(String from, String sdp) async {
    await _initPeerConnection();

    final description = RTCSessionDescription(sdp, 'offer');
    await _peerConnection!.setRemoteDescription(description);

    // Drain any candidates that arrived while initializing
    await _drainPendingCandidates();

    final RTCSessionDescription answer = await _peerConnection!.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 0,
    });
    await _peerConnection!.setLocalDescription(answer);

    signalingService.sendAnswer(from, answer.sdp ?? '');
  }

  Future<void> _handleRemoteAnswer(String sdp) async {
    if (_peerConnection == null) return;
    final description = RTCSessionDescription(sdp, 'answer');
    await _peerConnection!.setRemoteDescription(description);

    // Drain any candidates that arrived while establishing
    await _drainPendingCandidates();
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
      // Queue candidate until remote description is set to avoid rejection
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

    // 1. Capture local audio stream with Opus, Echo Cancellation, and Noise Suppression
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

    // 2. Create RTCPeerConnection
    final configuration = _createIceServersConfig();
    _peerConnection = await createPeerConnection(configuration);

    // 3. Add local audio tracks
    _localStream!.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    // 4. Handle remote audio stream
    _peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.track.kind == 'audio') {
        _remoteStream = event.streams[0];
      }
    };

    // 5. ICE candidate gathering
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

    // 6. Monitor ICE Connection State & Active Candidate Pair
    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      _currentIceState =
          state.toString().replaceAll('RTCIceConnectionState.', '');
      _iceStateController.add(_currentIceState);

      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _connectionType = 'P2P 直连已建立 (UDP/SRTP)';
        _detectConnectionType();
        _callStatusController.add(CallStatus.connected);
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
        audioTracks[0].enabled = !_isMuted;
      }
    }
  }

  Future<void> toggleSpeakerphone() async {
    _isSpeakerphoneOn = !_isSpeakerphoneOn;
    await Helper.setSpeakerphoneOn(_isSpeakerphoneOn);
  }

  void hangup() {
    if (_currentPeerId != null) {
      signalingService.sendHangup(_currentPeerId!);
    }
    _cleanupCall();
    _callStatusController.add(CallStatus.idle);
  }

  Future<void> _cleanupCall() async {
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

    _remoteStream = null;
    _isMuted = false;
    _currentIceState = 'Idle';
    _connectionType = 'Unknown';
    _isCaller = false;
  }

  void dispose() {
    _cleanupCall();
    _callStatusController.close();
    _iceStateController.close();
  }
}
