import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/call_state.dart';
import '../models/input_validation.dart';
import 'signaling_service.dart';

/// A call owns one generation of media resources. Late permission prompts,
/// SDP tasks and native callbacks cannot mutate a subsequent call.
class WebRTCService {
  WebRTCService({
    required this.signalingService,
    Future<bool> Function()? requestMicrophone,
    Future<MediaStream> Function()? openMicrophone,
    Future<RTCPeerConnection> Function(Map<String, dynamic>)? peerFactory,
    Future<void> Function(bool)? setSpeakerphone,
    this.ringTimeout = const Duration(seconds: 45),
  }) : _setSpeakerphone = setSpeakerphone ?? Helper.setSpeakerphoneOn,
       _requestMicrophone =
           requestMicrophone ??
           (() async => (await Permission.microphone.request()).isGranted),
       _openMicrophone =
           openMicrophone ??
           (() => navigator.mediaDevices.getUserMedia({
             'audio': {
               'echoCancellation': true,
               'noiseSuppression': true,
               'autoGainControl': true,
             },
             'video': false,
           })),
       _peerFactory =
           peerFactory ?? ((config) => createPeerConnection(config)) {
    _bindSignalingEvents();
  }

  final SignalingService signalingService;
  final Future<void> Function(bool) _setSpeakerphone;
  Future<void> _routeChange = Future.value();
  final Future<bool> Function() _requestMicrophone;
  final Future<MediaStream> Function() _openMicrophone;
  final Future<RTCPeerConnection> Function(Map<String, dynamic>) _peerFactory;
  final Duration ringTimeout;
  RTCPeerConnection? _peer;
  MediaStream? _stream;
  int _generation = 0;
  bool _disposed = false;
  bool _ending = false;
  bool _negotiating = false;
  bool _remoteDescriptionSet = false;
  bool _answerReceived = false;
  bool _isCaller = false;
  bool _muted = false;
  bool _speaker = false;
  bool _routingAudio = false;
  String? _peerId;
  CallStatus _status = CallStatus.idle;
  Timer? _timer;
  Timer? _disconnectTimer;
  Future<void> _cleanup = Future.value();
  final List<RTCIceCandidate> _candidates = [];
  final _statuses = StreamController<CallStatus>.broadcast();
  final _iceStates = StreamController<String>.broadcast();
  Stream<CallStatus> get callStatusStream => _statuses.stream;
  Stream<String> get iceStateStream => _iceStates.stream;
  CallStatus get callStatus => _status;
  bool get isMuted => _muted;
  bool get isSpeakerphoneOn => _speaker;
  bool get isCaller => _isCaller;
  String? get currentPeerId => _peerId;
  String currentIceState = 'Idle';
  String connectionType = 'transportUnknown';
  String remotePeerAvatar = 'pilot';
  String? remotePeerAvatarImage;
  void Function(String key)? onError;
  void Function(String key)? onNotice;
  List<String> stunServers = [
    'stun:170.106.195.109:3478',
    'stun:stun.l.google.com:19302',
  ];
  Map<String, dynamic>? _turn;
  DateTime? _turnExpiry;

  bool get _busy =>
      _ending ||
      _status == CallStatus.calling ||
      _status == CallStatus.incoming ||
      _status == CallStatus.connected;
  bool _current(int generation) =>
      !_disposed && !_ending && generation == _generation;
  void _setStatus(CallStatus value) {
    if (_disposed || _status == value) return;
    _status = value;
    _statuses.add(value);
  }

  void updateStunServer(String address) {
    if (!InputValidation.stunServer(address)) return;
    final server = address.startsWith('stun:') ? address : 'stun:$address';
    stunServers = [
      server,
      if (server != 'stun:stun.l.google.com:19302')
        'stun:stun.l.google.com:19302',
    ];
  }

  void setRemotePeerAvatar(String avatar, {String? image}) {
    if (_busy) return;
    remotePeerAvatar = avatar;
    remotePeerAvatarImage = image;
  }

  void _begin(String id, {required bool caller}) {
    _generation++;
    _peerId = id;
    _isCaller = caller;
    _negotiating = false;
    _answerReceived = false;
    _remoteDescriptionSet = false;
    _candidates.clear();
    _setStatus(caller ? CallStatus.calling : CallStatus.incoming);
    _armTimeout();
  }

  void _bindSignalingEvents() {
    signalingService.onTurnConfig = (config) {
      _turn = config;
      _turnExpiry = config?['ttl'] is num
          ? DateTime.now().add(
              Duration(seconds: (config!['ttl'] as num).toInt()),
            )
          : null;
    };
    signalingService.onCallRequest = (from, avatar, image, payload) {
      if (_disposed ||
          !InputValidation.userId(from) ||
          from == signalingService.myUserId) {
        return;
      }
      if (_busy) {
        // A retransmitted request must not reject the call already ringing.
        if (from != _peerId || _status != CallStatus.incoming) {
          signalingService.sendCallReject(from);
        }
        return;
      }
      remotePeerAvatar = avatar;
      remotePeerAvatarImage = image;
      _begin(from, caller: false);
    };
    signalingService.onCallAccepted = (from) {
      if (_disposed ||
          from != _peerId ||
          !_isCaller ||
          _status != CallStatus.calling ||
          _negotiating) {
        return;
      }
      _negotiating = true;
      _armTimeout();
      unawaited(_negotiate(_generation));
    };
    signalingService.onOfferReceived = (from, sdp) {
      // Only an explicitly accepted incoming call can acquire the microphone.
      if (_disposed ||
          from != _peerId ||
          _isCaller ||
          _status != CallStatus.calling ||
          _negotiating) {
        return;
      }
      _negotiating = true;
      unawaited(_negotiate(_generation, offer: sdp));
    };
    signalingService.onAnswerReceived = (from, sdp) {
      if (from != _peerId ||
          !_isCaller ||
          _status != CallStatus.calling ||
          _answerReceived ||
          _peer == null) {
        return;
      }
      _answerReceived = true;
      unawaited(_answer(_generation, sdp));
    };
    signalingService.onIceCandidateReceived = (from, data) {
      if (_disposed || _ending || from != _peerId || !_busy) return;
      final candidate = data['candidate'];
      final mid = data['sdpMid'];
      final index = data['sdpMLineIndex'];
      if (candidate is! String ||
          candidate.isEmpty ||
          (mid != null && mid is! String) ||
          (index != null && index is! int)) {
        return;
      }
      final value = RTCIceCandidate(candidate, mid as String?, index as int?);
      if (_remoteDescriptionSet && _peer != null) {
        unawaited(_addCandidate(_peer!, value));
      } else if (_candidates.length < 256) {
        _candidates.add(value);
      }
    };
    signalingService.onCallRejected = (from) {
      if (from == _peerId && _status == CallStatus.calling && _isCaller) {
        unawaited(_finish(notice: 'callRejected'));
      }
    };
    signalingService.onHangupReceived = (from) {
      if (from == _peerId && _busy) unawaited(_finish(notice: 'peerHangup'));
    };
    signalingService.onUserOffline = (target, _) {
      if (target == _peerId && _busy) unawaited(_finish(notice: 'peerOffline'));
    };
  }

  Map<String, dynamic> _config() {
    final servers = <Map<String, dynamic>>[
      {'urls': stunServers},
    ];
    final turn = _turn;
    if (turn != null &&
        (_turnExpiry?.isAfter(DateTime.now()) ?? false) &&
        turn['uris'] is List &&
        turn['username'] is String &&
        turn['credential'] is String) {
      servers.add({
        'urls': turn['uris'],
        'username': turn['username'],
        'credential': turn['credential'],
      });
    }
    return {
      'iceServers': servers,
      'sdpSemantics': 'unified-plan',
      'iceTransportPolicy': 'all',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    };
  }

  Future<void> startCall(String id) async {
    if (_disposed) return;
    if (_busy) {
      onError?.call('busy');
      return;
    }
    if (!InputValidation.userId(id) || id == signalingService.myUserId) {
      onError?.call('invalidId');
      return;
    }
    if (!signalingService.isConnected) {
      onError?.call('notConnected');
      return;
    }
    _begin(id, caller: true);
    if (!signalingService.sendCallRequest(id)) {
      await _finish(error: 'notConnected');
    }
  }

  Future<void> acceptCall() async {
    if (_disposed ||
        _ending ||
        _status != CallStatus.incoming ||
        _peerId == null) {
      return;
    }
    _setStatus(CallStatus.calling);
    _armTimeout();
    signalingService.sendCallAccept(_peerId!);
  }

  Future<void> rejectCall() async {
    if (_status != CallStatus.incoming || _ending) return;
    signalingService.sendCallReject(_peerId!);
    await _finish();
  }

  Future<void> hangup() => _finish(sendHangup: true);
  void _armTimeout() {
    _timer?.cancel();
    final generation = _generation;
    _timer = Timer(ringTimeout, () {
      if (_current(generation) && _status != CallStatus.connected) {
        unawaited(_finish(sendHangup: true, notice: 'noAnswer'));
      }
    });
  }

  Future<void> _negotiate(int generation, {String? offer}) async {
    try {
      await _cleanup;
      if (!_current(generation)) return;
      final allowed = await _requestMicrophone();
      if (!_current(generation)) return;
      if (!allowed) {
        await _finish(sendHangup: true, error: 'micDenied');
        return;
      }
      final stream = await _openMicrophone();
      if (!_current(generation)) {
        await _release(null, stream);
        return;
      }
      _stream = stream;
      final peer = await _peerFactory(_config());
      if (!_current(generation)) {
        await _release(peer, null);
        return;
      }
      _peer = peer;
      peer.onIceCandidate = (candidate) {
        if (!_current(generation) || candidate.candidate?.isNotEmpty != true) {
          return;
        }
        signalingService.sendIceCandidate(_peerId!, {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      };
      peer.onIceConnectionState = (state) =>
          _iceChanged(generation, peer, state);
      for (final track in stream.getTracks()) {
        await peer.addTrack(track, stream);
        if (!_current(generation)) return;
      }
      if (offer != null) {
        await peer.setRemoteDescription(RTCSessionDescription(offer, 'offer'));
        if (!_current(generation)) return;
        await _drain(generation, peer);
      }
      if (!_current(generation)) return;
      final description = offer == null
          ? await peer.createOffer({
              'offerToReceiveAudio': 1,
              'offerToReceiveVideo': 0,
            })
          : await peer.createAnswer({
              'offerToReceiveAudio': 1,
              'offerToReceiveVideo': 0,
            });
      if (!_current(generation)) return;
      await peer.setLocalDescription(description);
      if (!_current(generation)) return;
      if (offer == null) {
        signalingService.sendOffer(_peerId!, description.sdp!);
      } else {
        signalingService.sendAnswer(_peerId!, description.sdp!);
      }
    } catch (error) {
      if (_current(generation)) {
        debugPrint('[WebRTC] Negotiation failed: $error');
        await _finish(sendHangup: true, error: 'callFailed');
      }
    }
  }

  Future<void> _answer(int generation, String sdp) async {
    final peer = _peer;
    if (peer == null) return;
    try {
      await peer.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
      if (_current(generation)) await _drain(generation, peer);
    } catch (_) {
      if (_current(generation)) {
        await _finish(sendHangup: true, error: 'callFailed');
      }
    }
  }

  Future<void> _drain(int generation, RTCPeerConnection peer) async {
    _remoteDescriptionSet = true;
    final pending = List<RTCIceCandidate>.of(_candidates);
    _candidates.clear();
    for (final candidate in pending) {
      if (!_current(generation)) return;
      await _addCandidate(peer, candidate);
    }
  }

  Future<void> _addCandidate(
    RTCPeerConnection peer,
    RTCIceCandidate candidate,
  ) async {
    try {
      await peer.addCandidate(candidate);
    } catch (error) {
      debugPrint('[WebRTC] ICE candidate rejected: $error');
    }
  }

  void _iceChanged(
    int generation,
    RTCPeerConnection peer,
    RTCIceConnectionState state,
  ) {
    if (!_current(generation)) return;
    currentIceState = state.name;
    _iceStates.add(currentIceState);
    if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
        state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
      _timer?.cancel();
      _disconnectTimer?.cancel();
      _setStatus(CallStatus.connected);
      unawaited(_detectTransport(generation, peer));
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
      unawaited(_finish(sendHangup: true, error: 'callFailed'));
    } else if (state ==
        RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
      _disconnectTimer?.cancel();
      _disconnectTimer = Timer(const Duration(seconds: 12), () {
        if (_current(generation)) {
          unawaited(_finish(sendHangup: true, error: 'callFailed'));
        }
      });
    }
  }

  Future<void> _detectTransport(int generation, RTCPeerConnection peer) async {
    try {
      final stats = await peer.getStats();
      if (!_current(generation)) return;
      final byId = {for (final report in stats) report.id: report};
      final selected = stats.where(
        (r) =>
            r.type == 'transport' &&
            r.values['selectedCandidatePairId'] != null,
      );
      final selectedId = selected.isEmpty
          ? null
          : selected.first.values['selectedCandidatePairId'];
      for (final report in stats) {
        if (report.type != 'candidate-pair' ||
            report.values['state'] != 'succeeded') {
          continue;
        }
        if (selectedId != null
            ? report.id != selectedId
            : report.values['nominated'] != true &&
                  report.values['selected'] != true) {
          continue;
        }
        final local =
            byId[report.values['localCandidateId']]?.values['candidateType'];
        final remote =
            byId[report.values['remoteCandidateId']]?.values['candidateType'];
        connectionType = local == 'relay' || remote == 'relay'
            ? 'transportRelay'
            : 'transportDirect';
        _iceStates.add(currentIceState);
        break;
      }
    } catch (_) {
      /* Transport classification is optional; never guess direct. */
    }
  }

  Future<void> toggleMute() async {
    if (_status != CallStatus.connected || _stream == null) return;
    _muted = !_muted;
    for (final track in _stream!.getAudioTracks()) {
      track.enabled = !_muted;
    }
  }

  Future<void> toggleSpeakerphone() async {
    if (_status != CallStatus.connected || _routingAudio) return;
    final generation = _generation;
    _routingAudio = true;
    try {
      _routeChange = _setSpeakerphone(!_speaker);
      await _routeChange;
      if (_current(generation)) _speaker = !_speaker;
    } catch (_) {
      if (_current(generation)) onError?.call('audioRouteFailed');
    } finally {
      _routingAudio = false;
    }
  }

  Future<void> _finish({
    bool sendHangup = false,
    String? notice,
    String? error,
  }) async {
    if (_ending || _disposed || !_busy) return;
    _ending = true;
    _generation++;
    _timer?.cancel();
    _disconnectTimer?.cancel();
    if (sendHangup && _peerId != null) signalingService.sendHangup(_peerId!);
    final peer = _peer;
    final stream = _stream;
    _peer = null;
    _stream = null;
    _peerId = null;
    _candidates.clear();
    _remoteDescriptionSet = false;
    final resetRoute = _speaker || _routingAudio;
    _cleanup = () async {
      if (resetRoute) {
        try {
          await _routeChange;
        } catch (_) {}
        try {
          await _setSpeakerphone(false);
        } catch (_) {}
      }
      await _release(peer, stream);
    }();
    await _cleanup;
    _muted = false;
    _speaker = false;
    currentIceState = 'Idle';
    connectionType = 'transportUnknown';
    _ending = false;
    _setStatus(CallStatus.idle);
    if (!_disposed) {
      if (notice != null) onNotice?.call(notice);
      if (error != null) onError?.call(error);
    }
  }

  Future<void> _release(RTCPeerConnection? peer, MediaStream? stream) async {
    if (peer != null) {
      peer.onIceCandidate = null;
      peer.onIceConnectionState = null;
      try {
        await peer.close();
      } catch (_) {}
      try {
        await peer.dispose();
      } catch (_) {}
    }
    if (stream != null) {
      for (final track in stream.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      try {
        await stream.dispose();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await _finish(sendHangup: true);
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _disconnectTimer?.cancel();
    signalingService.onCallRequest = null;
    signalingService.onCallAccepted = null;
    signalingService.onOfferReceived = null;
    signalingService.onAnswerReceived = null;
    signalingService.onIceCandidateReceived = null;
    signalingService.onHangupReceived = null;
    signalingService.onCallRejected = null;
    signalingService.onUserOffline = null;
    signalingService.onTurnConfig = null;
    await _cleanup;
    await _statuses.close();
    await _iceStates.close();
  }
}
