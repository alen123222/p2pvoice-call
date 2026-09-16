import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

import '../models/avatar_model.dart';
import '../models/call_state.dart';
import '../models/input_validation.dart';
import '../services/foreground_service.dart';
import '../services/signaling_service.dart';
import '../services/webrtc_service.dart';

/// Owns the app session. Widgets render state and send intents; no widget owns
/// socket callbacks, native notifications, or call-duration timers.
class CallController extends ChangeNotifier {
  CallController({SignalingService? signaling, WebRTCService? rtc})
    : signaling = signaling ?? SignalingService() {
    this.rtc = rtc ?? WebRTCService(signalingService: this.signaling);
    _bind();
  }

  final SignalingService signaling;
  late final WebRTCService rtc;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Stopwatch _duration = Stopwatch();
  Timer? _ticker;
  bool _disposed = false;
  bool ready = false;
  String userId = '';
  String avatarId = 'pilot';
  String? avatarImage;
  String serverUrl = 'ws://170.106.195.109:8080';
  String stunServer = '170.106.195.109:3478';
  String token = '';
  String? backgroundPath;
  List<PeerInfo> peers = [];
  SignalingStatus signalingStatus = SignalingStatus.disconnected;
  CallStatus callStatus = CallStatus.idle;
  void Function(String message, bool isError)? onFeedback;

  bool get inCall =>
      callStatus == CallStatus.calling ||
      callStatus == CallStatus.incoming ||
      callStatus == CallStatus.connected;
  bool get canCall => ready && signaling.isConnected && !inCall;
  String get duration {
    final seconds = _duration.elapsed.inSeconds;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  void notifyControlsChanged() => _emit();

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _feedback(String key, [bool error = true]) {
    if (!_disposed) onFeedback?.call(key, error);
  }

  void _bind() {
    _subscriptions.add(
      signaling.statusStream.listen((status) {
        signalingStatus = status;
        if (status != SignalingStatus.connected) peers = [];
        _emit();
      }),
    );
    _subscriptions.add(
      rtc.callStatusStream.listen((status) {
        callStatus = status;
        if (status == CallStatus.incoming) {
          ForegroundServiceManager.showIncomingCallNotification(
            rtc.currentPeerId ?? '',
          );
        } else {
          ForegroundServiceManager.cancelIncomingCallNotification();
        }
        if (status == CallStatus.connected && !_duration.isRunning) {
          _duration.start();
          _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _emit());
          ForegroundServiceManager.startCallForeground(rtc.currentPeerId ?? '');
        } else if (!inCall) {
          _ticker?.cancel();
          _duration
            ..stop()
            ..reset();
          ForegroundServiceManager.stopCallForeground();
        }
        _emit();
      }),
    );
    _subscriptions.add(rtc.iceStateStream.listen((_) => _emit()));
    rtc.onError = _feedback;
    rtc.onNotice = (key) => _feedback(key, false);
    signaling.onErrorOccurred = _feedback;
    signaling.onRegistered = (id, users) {
      userId = id;
      peers = users;
      _sortPeers();
      ForegroundServiceManager.startKeepAliveService();
    };
    signaling.onUserJoined = (peer) {
      peers = [...peers.where((p) => p.userId != peer.userId), peer];
      _sortPeers();
    };
    signaling.onUserLeft = (id) {
      peers = peers.where((p) => p.userId != id).toList();
      _emit();
    };
    signaling.onUserListUpdated = (users) {
      peers = users;
      _sortPeers();
    };
    ForegroundServiceManager.initialize(
      handleCallAction: (action, peerId) {
        if (peerId != rtc.currentPeerId || callStatus != CallStatus.incoming) {
          return;
        }
        if (action == 'answer') rtc.acceptCall();
        if (action == 'reject') rtc.rejectCall();
      },
    );
  }

  void _sortPeers() {
    peers =
        peers.where((p) => p.userId.isNotEmpty && p.userId != userId).toList()
          ..sort((a, b) => a.userId.compareTo(b.userId));
    _emit();
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    userId = prefs.getString('user_id') ?? '';
    if (!InputValidation.userId(userId)) {
      final random = Random.secure();
      userId =
          'user_${List.generate(6, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
      await prefs.setString('user_id', userId);
    }
    avatarId = prefs.getString('user_avatar') ?? 'pilot';
    final avatar = AvatarManager.getById(avatarId, isMe: true);
    avatarImage = avatar.imagePath == null
        ? null
        : await AvatarManager.imageToBase64(avatar.imagePath!);
    serverUrl = prefs.getString('server_url') ?? serverUrl;
    stunServer = prefs.getString('stun_server') ?? stunServer;
    token = prefs.getString('access_token') ?? '';
    backgroundPath = prefs.getString('background_path');
    if (backgroundPath != null && !await File(backgroundPath!).exists()) {
      backgroundPath = null;
    }
    if (_disposed) return;
    rtc.updateStunServer(stunServer);
    signaling.setAuthToken(token);
    ready = true;
    _emit();
    unawaited(ForegroundServiceManager.prepareNotifications());
    await reconnect();
  }

  Future<void> reconnect() async {
    if (_disposed || !ready) return;
    if (!InputValidation.signalingUrl(serverUrl)) {
      _feedback('invalidServer');
      return;
    }
    await signaling.connect(
      serverUrl,
      userId,
      avatar: avatarId,
      avatarImage: avatarImage,
    );
  }

  void resume() {
    if (!ready || _disposed) return;
    signaling.checkAndReconnect();
    signaling.refreshUsers();
  }

  Future<void> call(String target) async {
    target = target.trim();
    if (!InputValidation.userId(target)) {
      _feedback('invalidId');
      return;
    }
    if (target == userId) {
      _feedback('errorSelfCall');
      return;
    }
    if (!canCall) {
      _feedback(inCall ? 'busy' : 'notConnected');
      return;
    }
    PeerInfo? peer;
    for (final item in peers) {
      if (item.userId == target) peer = item;
    }
    rtc.setRemotePeerAvatar(peer?.avatar ?? 'pilot', image: peer?.avatarImage);
    await rtc.startCall(target);
  }

  Future<void> saveNetwork(String url, String stun, String accessToken) async {
    if (inCall) return;
    final prefs = await SharedPreferences.getInstance();
    if (_disposed || inCall) return;
    serverUrl = url.trim();
    stunServer = stun.trim();
    token = accessToken.trim();
    await prefs.setString('server_url', serverUrl);
    await prefs.setString('stun_server', stunServer);
    await prefs.setString('access_token', token);
    rtc.updateStunServer(stunServer);
    signaling.setAuthToken(token);
    if (!_disposed && !inCall) await reconnect();
  }

  Future<void> updateIdentity(String id, String avatar) async {
    if (inCall || !InputValidation.userId(id)) return;
    final prefs = await SharedPreferences.getInstance();
    final item = AvatarManager.getById(avatar, isMe: true);
    final image = item.imagePath == null
        ? null
        : await AvatarManager.imageToBase64(item.imagePath!);
    if (_disposed || inCall) return;
    userId = id;
    avatarId = avatar;
    avatarImage = image;
    await prefs.setString('user_id', id);
    await prefs.setString('user_avatar', avatar);
    signaling.updateProfile(
      newUserId: id,
      newAvatar: avatar,
      newAvatarImage: image,
    );
    _emit();
  }

  Future<void> setBackground(String? path) async {
    final previous = backgroundPath;
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove('background_path');
    } else {
      await prefs.setString('background_path', path);
    }
    backgroundPath = path;
    _emit();
    if (previous != null && previous != path) {
      // Delete only files this app created inside its documents directory.
      final directory = await getApplicationDocumentsDirectory();
      final file = File(previous);
      final parent = file.absolute.parent.path;
      final name = file.uri.pathSegments.last;
      if (parent == directory.absolute.path && name.startsWith('custom_bg_')) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    onFeedback = null;
    _ticker?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    ForegroundServiceManager.onCallAction = null;
    ForegroundServiceManager.stopAllServices();
    unawaited(_shutdown());
    super.dispose();
  }

  Future<void> _shutdown() async {
    await rtc.dispose();
    await signaling.dispose();
  }
}
