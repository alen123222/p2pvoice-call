import 'dart:async';

import 'package:client/models/call_state.dart';
import 'package:client/services/signaling_service.dart';
import 'package:client/services/webrtc_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class FakeSignaling extends SignalingService {
  final sent = <String>[];
  @override
  bool get isConnected => true;
  @override
  String get myUserId => 'me';
  @override
  bool sendCallRequest(String id) {
    sent.add('call:$id');
    return true;
  }

  @override
  void sendCallAccept(String id) {
    sent.add('accept:$id');
  }

  @override
  void sendCallReject(String id) {
    sent.add('reject:$id');
  }

  @override
  void sendHangup(String id) {
    sent.add('hangup:$id');
  }

  @override
  void sendOffer(String id, String sdp) {
    sent.add('offer:$id');
  }

  @override
  void sendAnswer(String id, String sdp) {
    sent.add('answer:$id');
  }
}

class FakeMedia extends Fake implements MediaStream {
  bool disposed = false;
  @override
  List<MediaStreamTrack> getTracks() => [];
  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class FakePeer extends Fake implements RTCPeerConnection {
  final candidates = <RTCIceCandidate>[];
  bool closed = false;
  void Function(RTCIceConnectionState)? iceChanged;
  @override
  set onIceCandidate(void Function(RTCIceCandidate candidate)? callback) {}
  @override
  set onIceConnectionState(
    void Function(RTCIceConnectionState state)? callback,
  ) {
    iceChanged = callback;
  }

  @override
  Future<List<StatsReport>> getStats([MediaStreamTrack? track]) async => [];
  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {}
  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {}
  @override
  Future<RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async => RTCSessionDescription('offer', 'offer');
  @override
  Future<RTCSessionDescription> createAnswer([
    Map<String, dynamic>? constraints,
  ]) async => RTCSessionDescription('answer', 'answer');
  @override
  Future<void> addCandidate(RTCIceCandidate candidate) async {
    candidates.add(candidate);
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<void> dispose() async {}
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeSignaling signaling;
  late WebRTCService rtc;
  late FakePeer peer;
  late FakeMedia media;
  var permissionRequests = 0;
  setUp(() {
    signaling = FakeSignaling();
    peer = FakePeer();
    media = FakeMedia();
    permissionRequests = 0;
    rtc = WebRTCService(
      signalingService: signaling,
      requestMicrophone: () async {
        permissionRequests++;
        return true;
      },
      openMicrophone: () async => media,
      peerFactory: (_) async => peer,
    );
  });
  tearDown(() async {
    await rtc.dispose();
    await signaling.dispose();
  });

  test('connected is emitted once and hangup resets speaker', () async {
    await rtc.dispose();
    final routes = <bool>[];
    rtc = WebRTCService(
      signalingService: signaling,
      requestMicrophone: () async => true,
      openMicrophone: () async => media,
      peerFactory: (_) async => peer,
      setSpeakerphone: (value) async {
        routes.add(value);
      },
    );
    final states = <CallStatus>[];
    final sub = rtc.callStatusStream.listen(states.add);
    await rtc.startCall('friend');
    signaling.onCallAccepted!('friend');
    await flush();
    peer.iceChanged!(RTCIceConnectionState.RTCIceConnectionStateConnected);
    peer.iceChanged!(RTCIceConnectionState.RTCIceConnectionStateCompleted);
    await flush();
    await rtc.toggleSpeakerphone();
    await rtc.hangup();
    await flush();
    expect(states.where((state) => state == CallStatus.connected).length, 1);
    expect(routes, [true, false]);
    expect(rtc.isSpeakerphoneOn, isFalse);
    await sub.cancel();
  });

  test(
    'unsolicited and unaccepted offers never request microphone access',
    () async {
      signaling.onOfferReceived!('stranger', 'sdp');
      signaling.onCallRequest!('friend', 'pilot', null, null);
      signaling.onOfferReceived!('friend', 'sdp');
      await flush();
      expect(permissionRequests, 0);
      expect(rtc.callStatus, CallStatus.incoming);
    },
  );
  test('accepted call preserves ICE received before offer', () async {
    signaling.onCallRequest!('friend', 'pilot', null, null);
    signaling.onIceCandidateReceived!('friend', {
      'candidate': 'early',
      'sdpMid': '0',
      'sdpMLineIndex': 0,
    });
    await rtc.acceptCall();
    signaling.onOfferReceived!('stranger', 'sdp');
    signaling.onOfferReceived!('friend', 'sdp');
    await flush();
    expect(peer.candidates.single.candidate, 'early');
    expect(signaling.sent, ['accept:friend', 'answer:friend']);
  });
  test(
    'rapid dial and repeated accept cannot start duplicate negotiations',
    () async {
      await rtc.startCall('friend');
      await rtc.startCall('other');
      signaling.onCallAccepted!('friend');
      signaling.onCallAccepted!('friend');
      await flush();
      expect(permissionRequests, 1);
      expect(signaling.sent.where((s) => s.startsWith('call:')), [
        'call:friend',
      ]);
      expect(signaling.sent.where((s) => s.startsWith('offer:')), [
        'offer:friend',
      ]);
    },
  );
  test(
    'hangup while awaiting permission cannot acquire audio or affect redial',
    () async {
      await rtc.dispose();
      final permission = Completer<bool>();
      var captures = 0;
      rtc = WebRTCService(
        signalingService: signaling,
        requestMicrophone: () => permission.future,
        openMicrophone: () async {
          captures++;
          return media;
        },
        peerFactory: (_) async => peer,
      );
      await rtc.startCall('friend');
      signaling.onCallAccepted!('friend');
      await flush();
      await rtc.hangup();
      await rtc.startCall('other');
      permission.complete(true);
      await flush();
      expect(captures, 0);
      expect(rtc.currentPeerId, 'other');
      expect(rtc.callStatus, CallStatus.calling);
    },
  );
  test('late acquired media is released after hangup', () async {
    await rtc.dispose();
    final acquired = Completer<MediaStream>();
    rtc = WebRTCService(
      signalingService: signaling,
      requestMicrophone: () async => true,
      openMicrophone: () => acquired.future,
      peerFactory: (_) async => peer,
    );
    await rtc.startCall('friend');
    signaling.onCallAccepted!('friend');
    await flush();
    await rtc.hangup();
    acquired.complete(media);
    await flush();
    expect(media.disposed, isTrue);
    expect(rtc.callStatus, CallStatus.idle);
    expect(signaling.sent, isNot(contains('offer:friend')));
  });
  test(
    'incoming ring expires without an offer and ignores late accept',
    () async {
      await rtc.dispose();
      rtc = WebRTCService(
        signalingService: signaling,
        ringTimeout: const Duration(milliseconds: 5),
      );
      signaling.onCallRequest!('friend', 'pilot', null, null);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(rtc.callStatus, CallStatus.idle);
      await rtc.acceptCall();
      expect(signaling.sent, ['hangup:friend']);
    },
  );
  test('permission denial notifies peer and restores idle state', () async {
    await rtc.dispose();
    rtc = WebRTCService(
      signalingService: signaling,
      requestMicrophone: () async => false,
    );
    String? error;
    rtc.onError = (key) => error = key;
    await rtc.startCall('friend');
    signaling.onCallAccepted!('friend');
    await flush();
    expect(error, 'micDenied');
    expect(rtc.callStatus, CallStatus.idle);
    expect(signaling.sent, contains('hangup:friend'));
  });
}
