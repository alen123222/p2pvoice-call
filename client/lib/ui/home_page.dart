import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../models/avatar_model.dart';
import '../models/call_state.dart';
import '../services/foreground_service.dart';
import '../services/signaling_service.dart';
import '../services/webrtc_service.dart';
import '../theme/app_theme.dart';
import 'widgets/avatar_circle.dart';
import 'widgets/glass_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final SignalingService _signalingService;
  late final WebRTCService _webrtcService;

  final TextEditingController _targetIdController = TextEditingController();
  final TextEditingController _serverUrlController =
      TextEditingController(text: 'ws://170.106.195.109:8080');
  final TextEditingController _stunServerController =
      TextEditingController(text: '170.106.195.109:3478');

  String _myUserId = '';
  String _myAvatar = 'pilot';
  String? _myAvatarImageBase64;
  SignalingStatus _signalingStatus = SignalingStatus.disconnected;
  CallStatus _callStatus = CallStatus.idle;
  List<PeerInfo> _onlinePeers = [];
  String _iceState = 'Idle';
  String? _backgroundPath;
  bool _copiedJustNow = false;

  Timer? _callDurationTimer;
  int _callSeconds = 0;

  StreamSubscription? _signalingSub;
  StreamSubscription? _callStatusSub;
  StreamSubscription? _iceStateSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _targetIdController.addListener(() {
      if (mounted) setState(() {});
    });
    _initServices();
    _requestPermissions();
    _loadPreferences();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _signalingService.checkAndReconnect();
      if (_signalingService.isConnected) {
        _signalingService.refreshUsers();
      }
    }
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.microphone,
      Permission.bluetoothConnect,
      Permission.notification,
    ].request();
    // Keep alive in background so online state is preserved
    ForegroundServiceManager.startKeepAliveService();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString('user_id');
    final savedAvatar = prefs.getString('user_avatar');
    final savedServer = prefs.getString('server_url');
    final savedStun = prefs.getString('stun_server');
    final savedToken = prefs.getString('access_token');
    final savedBackground = prefs.getString('background_path');
    final isDark = prefs.getBool('is_dark_mode') ?? true;

    isDarkModeNotifier.value = isDark;

    if (savedId != null && savedId.isNotEmpty) {
      _myUserId = savedId;
    } else {
      _myUserId = 'user_${DateTime.now().millisecondsSinceEpoch % 9000 + 1000}';
      await prefs.setString('user_id', _myUserId);
    }

    if (savedAvatar != null && savedAvatar.isNotEmpty) {
      _myAvatar = savedAvatar;
    }

    // Pre-compute the base64 payload for a custom photo avatar so it can be
    // shared with other devices via the signaling server.
    final meAvatar = AvatarManager.getById(_myAvatar, isMe: true);
    if (meAvatar.imagePath != null && meAvatar.imagePath!.isNotEmpty) {
      _myAvatarImageBase64 = await AvatarManager.imageToBase64(meAvatar.imagePath!);
    }

    if (savedServer != null && savedServer.isNotEmpty) {
      _serverUrlController.text = savedServer;
    }
    if (savedStun != null && savedStun.isNotEmpty) {
      _stunServerController.text = savedStun;
      _webrtcService.updateStunServer(savedStun);
    }
    if (savedToken != null && savedToken.isNotEmpty) {
      _signalingService.setAuthToken(savedToken);
    }
    if (savedBackground != null && savedBackground.isNotEmpty) {
      final file = File(savedBackground);
      if (file.existsSync()) {
        _backgroundPath = savedBackground;
      } else {
        await prefs.remove('background_path');
        _backgroundPath = null;
      }
    }

    if (mounted) setState(() {});
    _connectSignaling();
  }

  void _initServices() {
    _signalingService = SignalingService();
    _webrtcService = WebRTCService(signalingService: _signalingService);

    ForegroundServiceManager.initialize(
      handleCallAction: (action, peerId) {
        if (action == 'answer') {
          _webrtcService.acceptCall();
        } else if (action == 'reject') {
          _webrtcService.rejectCall();
        }
      },
    );

    // Listen to signaling status
    _signalingSub = _signalingService.statusStream.listen((status) {
      if (mounted) {
        setState(() => _signalingStatus = status);
      }
    });

    // Listen to call status
    _callStatusSub = _webrtcService.callStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          _callStatus = status;
          if (status == CallStatus.incoming) {
            final caller = _webrtcService.currentPeerId ?? '未知呼叫';
            ForegroundServiceManager.showIncomingCallNotification(caller);
          } else if (status == CallStatus.connected) {
            _startCallTimer();
            ForegroundServiceManager.cancelIncomingCallNotification();
            ForegroundServiceManager.startCallForeground(
                _webrtcService.currentPeerId ?? _l10n().unknownUser);
          } else if (status == CallStatus.ended || status == CallStatus.idle) {
            _stopCallTimer();
            ForegroundServiceManager.cancelIncomingCallNotification();
            ForegroundServiceManager.stopCallForeground();
          }
        });
      }
    });

    // Listen to ICE state
    _iceStateSub = _webrtcService.iceStateStream.listen((state) {
      if (mounted) {
        setState(() => _iceState = state);
      }
    });

    // Feedback from the WebRTC layer, keyed for localization.
    _webrtcService.onError = (key) {
      if (mounted) _showSnack(_l10n().t(key));
    };
    _webrtcService.onNotice = (key) {
      if (mounted) _showSnack(_l10n().t(key));
    };

    // User list events
    _signalingService.onRegistered = (myId, users) {
      if (mounted) {
        setState(() {
          _myUserId = myId;
          _onlinePeers = users;
        });
      }
      ForegroundServiceManager.startKeepAliveService();
    };

    _signalingService.onUserJoined = (user) {
      if (mounted) {
        setState(() {
          _onlinePeers.removeWhere((p) => p.userId == user.userId);
          _onlinePeers.add(user);
        });
      }
    };

    _signalingService.onUserLeft = (userId) {
      if (mounted) {
        setState(() {
          _onlinePeers.removeWhere((p) => p.userId == userId);
        });
      }
    };

    _signalingService.onUserListUpdated = (users) {
      if (mounted) {
        setState(() {
          _onlinePeers = users;
        });
      }
    };

    _signalingService.onErrorOccurred = (err) {
      if (mounted) _showSnack(err);
    };
  }

  AppLocalizations _l10n() => AppLocalizations.of(context)!;

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _connectSignaling() async {
    final url = _serverUrlController.text.trim();
    if (url.isNotEmpty && _myUserId.isNotEmpty) {
      await _signalingService.connect(url, _myUserId,
          avatar: _myAvatar, avatarImage: _myAvatarImageBase64);
    }
  }

  void _startCallTimer() {
    _stopCallTimer();
    _callSeconds = 0;
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _callSeconds++);
      }
    });
  }

  void _stopCallTimer() {
    _callDurationTimer?.cancel();
    _callDurationTimer = null;
    _callSeconds = 0;
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _makeCall(String targetId, {String? targetAvatar}) async {
    final l10n = _l10n();
    final target = targetId.trim();
    if (target.isEmpty) {
      _showSnack(l10n.errorEmptyTarget);
      return;
    }
    if (target == _myUserId) {
      _showSnack(l10n.errorSelfCall);
      return;
    }
    if (!_signalingService.isConnected) {
      _showSnack(l10n.errorNotConnected);
      return;
    }

    if (targetAvatar != null) {
      _webrtcService.setRemotePeerAvatar(targetAvatar);
    }

    await _webrtcService.startCall(target);
  }

  // ----- Background image handling -----
  Future<void> _pickBackground({StateSetter? setDialogState}) async {
    final l10n = _l10n();
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 90,
      );
      if (file == null) return;

      final ext = file.path.contains('.')
          ? file.path.substring(file.path.lastIndexOf('.'))
          : '.jpg';
      final dir = await getApplicationDocumentsDirectory();

      // Delete old background file on disk to avoid stale / orphan files
      if (_backgroundPath != null) {
        final oldFile = File(_backgroundPath!);
        if (oldFile.existsSync()) {
          try {
            await oldFile.delete();
          } catch (_) {}
        }
        await FileImage(oldFile).evict();
      }

      // Unique timestamp prevents Flutter's ImageCache key collision
      final dest = File(
          '${dir.path}/custom_bg_${DateTime.now().millisecondsSinceEpoch}$ext');
      await File(file.path).copy(dest.path);
      await FileImage(dest).evict();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('background_path', dest.path);
      if (mounted) {
        setState(() => _backgroundPath = dest.path);
        setDialogState?.call(() {});
        _showSnack(l10n.backgroundSaved);
      }
    } catch (e) {
      debugPrint('[Background] Failed to set background: $e');
      if (mounted) _showSnack(l10n.backgroundError);
    }
  }

  Future<void> _resetBackground({StateSetter? setDialogState}) async {
    final l10n = _l10n();
    if (_backgroundPath != null) {
      final oldFile = File(_backgroundPath!);
      if (oldFile.existsSync()) {
        try {
          await oldFile.delete();
        } catch (_) {}
      }
      await FileImage(oldFile).evict();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('background_path');
    if (mounted) {
      setState(() => _backgroundPath = null);
      setDialogState?.call(() {});
      _showSnack(l10n.backgroundReset);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _signalingSub?.cancel();
    _callStatusSub?.cancel();
    _iceStateSub?.cancel();
    _stopCallTimer();
    ForegroundServiceManager.cancelIncomingCallNotification();
    ForegroundServiceManager.stopCallForeground();
    _webrtcService.dispose();
    _signalingService.dispose();
    _targetIdController.dispose();
    _serverUrlController.dispose();
    _stunServerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDark, _) {
        return ValueListenableBuilder<AppThemeType>(
          valueListenable: currentThemeTypeNotifier,
          builder: (context, themeType, _) {
            final pack = AppTheme.getPack(themeType);
            final l10n = AppLocalizations.of(context)!;

            return Scaffold(
              backgroundColor:
                  isDark ? pack.darkBgEnd : pack.lightBgStart,
              extendBodyBehindAppBar: true,
              extendBody: true,
              resizeToAvoidBottomInset: false,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                systemOverlayStyle: SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness:
                      isDark ? Brightness.light : Brightness.dark,
                  systemNavigationBarColor: Colors.transparent,
                  systemNavigationBarDividerColor: Colors.transparent,
                  systemNavigationBarIconBrightness:
                      isDark ? Brightness.light : Brightness.dark,
                  systemNavigationBarContrastEnforced: false,
                ),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        gradient: pack.gradient,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: pack.primary.withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.phone_in_talk_rounded,
                        color: isDark ? pack.darkBgStart : Colors.white,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      l10n.headerTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        letterSpacing: 0.3,
                        color: isDark
                            ? pack.darkTextPrimary
                            : pack.lightTextPrimary,
                      ),
                    ),
                  ],
                ),
                actions: [
                  _buildSignalingStatusPill(isDark, pack),
                  IconButton(
                    icon: Icon(
                      isDark
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                      color: isDark ? pack.primary : pack.secondary,
                      size: 21,
                    ),
                    tooltip: isDark
                        ? l10n.tooltipLightTheme
                        : l10n.tooltipDarkTheme,
                    onPressed: () async {
                      final newMode = !isDark;
                      isDarkModeNotifier.value = newMode;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('is_dark_mode', newMode);
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.settings_rounded,
                      color: isDark
                          ? pack.darkTextPrimary.withValues(alpha: 0.7)
                          : pack.lightTextPrimary.withValues(alpha: 0.7),
                      size: 21,
                    ),
                    tooltip: l10n.tooltipSettings,
                    onPressed: () => _showSettingsDialog(isDark, pack),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              body: Stack(
                children: [
                  // 1. 当前主题的双色专属弥散背景
                  _buildAmbientBackground(isDark, pack),

                  // 2. 自定义背景图片 (裁剪充满，无留白)
                  if (_backgroundPath != null &&
                      File(_backgroundPath!).existsSync()) ...[
                    Positioned.fill(
                      child: Image.file(
                        File(_backgroundPath!),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (context, error, stack) =>
                            const SizedBox(),
                      ),
                    ),
                    Positioned.fill(
                      child: Container(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.50)
                            : Colors.white.withValues(alpha: 0.40),
                      ),
                    ),
                  ],

                  // 3. 全新重构的前台主界面 (清晰分区)
                  SafeArea(
                    bottom: false,
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        16,
                        8,
                        16,
                        MediaQuery.of(context).padding.bottom + 24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 卡片 1：个人身份与设备卡片
                          _buildMyIdentityCard(isDark, pack),
                          const SizedBox(height: 16),

                          // 卡片 2：主卡片 - 当前在线设备列表 (Hero Card)
                          _buildOnlineUsersHeroCard(isDark, pack),
                          const SizedBox(height: 16),

                          // 卡片 3：快速拨号与 P2P 呼叫控制台 (副卡片)
                          _buildDialCard(isDark, pack),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),

                  // 4. 呼叫全屏弹层
                  if (_callStatus == CallStatus.incoming)
                    _buildIncomingCallOverlay(),
                  if (_callStatus == CallStatus.calling ||
                      _callStatus == CallStatus.connected)
                    _buildActiveCallOverlay(),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 当前主题专属双色氛围背景 (结合当前所选主题的两个配色)
  Widget _buildAmbientBackground(bool isDark, ThemeColorPack pack) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [pack.darkBgStart, pack.darkBgEnd]
                  : [pack.lightBgStart, pack.lightBgEnd],
            ),
          ),
          child: Stack(
            children: [
              // 配色一 (Primary) 光晕球
              Positioned(
                top: -50,
                right: -40,
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        pack.primary.withValues(alpha: isDark ? 0.32 : 0.35),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // 配色二 (Secondary) 光晕球
              Positioned(
                top: 240,
                left: -70,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        pack.secondary.withValues(alpha: isDark ? 0.28 : 0.30),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // 底部混合光晕
              Positioned(
                bottom: -50,
                right: -50,
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        pack.primary.withValues(alpha: isDark ? 0.20 : 0.25),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 信令与在线状态胶囊
  Widget _buildSignalingStatusPill(bool isDark, ThemeColorPack pack) {
    final l10n = _l10n();
    Color color;
    String text;
    IconData? icon;

    switch (_signalingStatus) {
      case SignalingStatus.connected:
        color = AppTheme.success;
        text = l10n.statusOnline;
        break;
      case SignalingStatus.connecting:
        color = AppTheme.warning;
        text = l10n.statusConnecting;
        break;
      case SignalingStatus.reconnecting:
        color = const Color(0xFFF97316);
        text = l10n.statusReconnecting;
        icon = Icons.sync_rounded;
        break;
      case SignalingStatus.error:
      case SignalingStatus.disconnected:
        color = AppTheme.danger;
        text = l10n.statusOffline;
        break;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 12, color: color)
          else
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.6),
                    blurRadius: 5,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 卡片 1：个人身份与设备卡片 (半透明毛玻璃)
  /// Builds the avatar shown for a remote peer. If the peer shared a custom
  /// photo (base64), it is rendered directly; otherwise fall back to the
  /// stable preset mapping.
  AvatarItem _buildPeerAvatar(String avatarId, String? avatarImage, String peerSeed) {
    if (avatarImage != null && avatarImage.isNotEmpty) {
      return AvatarItem(
        id: avatarId,
        name: '自定义',
        emoji: '🖼️',
        imageBase64: avatarImage,
        gradient: const [Color(0xFF0284C7), Color(0xFF38BDF8)],
      );
    }
    return AvatarManager.getById(avatarId, isMe: false, peerSeed: peerSeed);
  }

  Widget _buildMyIdentityCard(bool isDark, ThemeColorPack pack) {
    final l10n = _l10n();
    final avatarItem = AvatarManager.getById(_myAvatar, isMe: true);

    return GlassCard(
      isDark: isDark,
      borderRadius: 22,
      blurSigma: 20,
      backgroundColor: isDark ? pack.darkGlassTint : pack.lightGlassTint,
      borderGradient: pack.gradient,
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Row(
            children: [
              // 头像与编辑按钮 (带主题双色渐变环)
              GestureDetector(
                onTap: () => _showAvatarPicker(isDark, pack),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: pack.gradient,
                        boxShadow: [
                          BoxShadow(
                            color: pack.primary.withValues(alpha: 0.35),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: AvatarCircle(avatar: avatarItem, size: 54),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3.5),
                        decoration: BoxDecoration(
                          gradient: pack.buttonGradient,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? pack.darkBgStart : Colors.white,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.edit_rounded,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),

              // 用户 ID 与身份信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          l10n.myUserIdLabel,
                          style: TextStyle(
                            color: isDark
                                ? pack.darkTextPrimary.withValues(alpha: 0.7)
                                : pack.lightTextPrimary.withValues(alpha: 0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: pack.primary.withValues(alpha: 0.20),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: pack.primary.withValues(alpha: 0.45),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            l10n.avatarName(_myAvatar),
                            style: TextStyle(
                              color: isDark ? pack.primary : const Color(0xFF0F172A),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      _myUserId.isEmpty ? l10n.loading : _myUserId,
                      style: TextStyle(
                        color: isDark
                            ? pack.darkTextPrimary
                            : pack.lightTextPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),

              // 操作按钮组：一键复制与编辑 ID
              IconButton(
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Icon(
                    _copiedJustNow
                        ? Icons.check_circle_rounded
                        : Icons.copy_rounded,
                    key: ValueKey(_copiedJustNow),
                    color: _copiedJustNow ? AppTheme.success : pack.secondary,
                    size: 20,
                  ),
                ),
                tooltip: l10n.tooltipCopy,
                onPressed: () {
                  if (_myUserId.isNotEmpty) {
                    Clipboard.setData(ClipboardData(text: _myUserId));
                    setState(() => _copiedJustNow = true);
                    _showSnack(l10n.toastCopied);
                    Future.delayed(const Duration(seconds: 2), () {
                      if (mounted) setState(() => _copiedJustNow = false);
                    });
                  }
                },
              ),
              IconButton(
                icon: Icon(
                  Icons.edit_note_rounded,
                  color: isDark
                      ? pack.darkTextPrimary.withValues(alpha: 0.7)
                      : pack.lightTextPrimary.withValues(alpha: 0.7),
                  size: 22,
                ),
                tooltip: l10n.tooltipEdit,
                onPressed: () => _showEditUserIdDialog(isDark, pack),
              ),
            ],
          ),

          const SizedBox(height: 12),
          // 优雅内嵌的加密直连微安全标签 (取代原本粗暴杂乱的绿横幅)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 13,
                  color: isDark ? pack.primary : pack.secondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.secureNotice,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark
                          ? pack.darkTextPrimary.withValues(alpha: 0.65)
                          : pack.lightTextPrimary.withValues(alpha: 0.65),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 根据主题获取发起呼叫主卡片专属流光渐变 (完全复刻参考图的极致流光质感)
  /// 根据主题获取主卡片专属流光渐变 (完全复刻参考图的极致流光质感)
  LinearGradient _getHeroCardGradient(ThemeColorPack pack) {
    switch (pack.id) {
      case 'teaFluo':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF008EFF), // 晴空亮蓝
            Color(0xFF00BDEB), // 荧光水蓝
            Color(0xFF1BE5B2), // 鲜活茶绿/薄荷青
          ],
          stops: [0.0, 0.48, 1.0],
        );
      case 'cloudRiver':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0284C7),
            Color(0xFF38BDF8),
            Color(0xFF7DD3FC),
          ],
          stops: [0.0, 0.55, 1.0],
        );
      case 'sakuraSmoke':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFDB2777),
            Color(0xFFF472B6),
            Color(0xFFFDA4AF),
          ],
          stops: [0.0, 0.55, 1.0],
        );
      case 'roseAmber':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF831843),
            Color(0xFFB45309),
            Color(0xFFF59E0B),
          ],
          stops: [0.0, 0.55, 1.0],
        );
      default:
        return pack.gradient;
    }
  }

  /// 主按钮专属高亮渐变
  LinearGradient _getDialButtonGradient(ThemeColorPack pack) {
    switch (pack.id) {
      case 'teaFluo':
        return const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFF00E5A3),
            Color(0xFF00C48C),
            Color(0xFF00AA76),
          ],
        );
      case 'cloudRiver':
        return const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFF0284C7),
            Color(0xFF0EA5E9),
            Color(0xFF38BDF8),
          ],
        );
      case 'sakuraSmoke':
        return const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFFDB2777),
            Color(0xFFF43F5E),
            Color(0xFFFB7185),
          ],
        );
      case 'roseAmber':
        return const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFFBE185D),
            Color(0xFFD97706),
            Color(0xFFF59E0B),
          ],
        );
      default:
        return pack.buttonGradient;
    }
  }

  /// 主卡片：当前在线设备聚合列表 (拥有 3D 拟物图标、流光大跑道渐变、声波线与直连通话按钮)
  Widget _buildOnlineUsersHeroCard(bool isDark, ThemeColorPack pack) {
    final l10n = _l10n();
    final cardGradient = _getHeroCardGradient(pack);
    final buttonGradient = _getDialButtonGradient(pack);
    final isTeaFluo = pack.id == 'teaFluo';

    return Container(
      decoration: BoxDecoration(
        gradient: cardGradient,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.50),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isTeaFluo ? const Color(0xFF008EFF) : pack.primary)
                .withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // 右下角半透明声波装饰线
            Positioned(
              right: -10,
              bottom: 6,
              child: IgnorePointer(
                child: CustomPaint(
                  size: const Size(190, 56),
                  painter: _AudioWaveformPainter(),
                ),
              ),
            ),

            // 主内容
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 顶部标题栏：3D 拟物设备雷达图标 + 标题副标题 + 在线数量胶囊 + 刷新按钮
                  Row(
                    children: [
                      // 3D 拟物渐变圆角图标
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isTeaFluo
                                ? const [Color(0xFF85FFDD), Color(0xFF00B7E5)]
                                : [pack.primary, pack.secondary],
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.85),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.devices_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                      const SizedBox(width: 13),

                      // 标题与副标题
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.onlineDevices,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _onlinePeers.isEmpty
                                  ? '等待其他设备上线并接入直连...'
                                  : '已发现 ${_onlinePeers.length} 台在线设备 · 点击直连',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.88),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w400,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),

                      // 右侧：在线数量药丸徽章
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.45),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF10E5A7),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${_onlinePeers.length}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),

                      // 刷新按钮
                      GestureDetector(
                        onTap: () => _signalingService.refreshUsers(),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.22),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.45),
                              width: 1.0,
                            ),
                          ),
                          child: const Icon(
                            Icons.refresh_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 2. 内容区域：空状态 或 在线设备卡片列表
                  if (_onlinePeers.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 24, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                          width: 1.0,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.sensors_off_rounded,
                            size: 34,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.noPeers,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            l10n.noPeersHint,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Column(
                      children: _onlinePeers.map((peer) {
                        final peerAvatar = _buildPeerAvatar(
                            peer.avatar, peer.avatarImage, peer.userId);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              AvatarCircle(
                                avatar: peerAvatar,
                                size: 44,
                                showOnlineDot: true,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      peer.userId,
                                      style: const TextStyle(
                                        color: Color(0xFF0F172A),
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${peerAvatar.name} · 点击开始直连',
                                      style: const TextStyle(
                                        color: Color(0xFF64748B),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),

                              // 直连通话流光小胶囊按钮
                              Container(
                                height: 38,
                                decoration: BoxDecoration(
                                  gradient: buttonGradient,
                                  borderRadius: BorderRadius.circular(19),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (isTeaFluo
                                              ? const Color(0xFF00C48C)
                                              : pack.primary)
                                          .withValues(alpha: 0.40),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(19),
                                    onTap: () => _makeCall(
                                      peer.userId,
                                      targetAvatar: peer.avatar,
                                    ),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 14),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.phone_in_talk_rounded,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                          SizedBox(width: 5),
                                          Text(
                                            '通话',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 副卡片：发起 P2P 呼叫控制台 (优雅毛玻璃卡片风格)
  Widget _buildDialCard(bool isDark, ThemeColorPack pack) {
    final l10n = _l10n();
    return GlassCard(
      isDark: isDark,
      borderRadius: 24,
      blurSigma: 20,
      backgroundColor: isDark ? pack.darkGlassTint : pack.lightGlassTint,
      borderGradient: pack.gradient,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：标题行
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      gradient: pack.gradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.dialpad_rounded,
                      color: isDark ? pack.darkBgStart : Colors.white,
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.dialTitle,
                        style: TextStyle(
                          color: isDark
                              ? pack.darkTextPrimary
                              : pack.lightTextPrimary,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '输入目标 ID 快速发起直连呼叫',
                        style: TextStyle(
                          color: isDark
                              ? pack.darkTextPrimary.withValues(alpha: 0.55)
                              : pack.lightTextPrimary.withValues(alpha: 0.55),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: pack.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: pack.primary.withValues(alpha: 0.35),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.shield_rounded,
                      size: 12,
                      color: isDark ? pack.primary : const Color(0xFF0F172A),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'WebRTC E2EE',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: isDark ? pack.primary : const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 跑道型白底/半透明输入框 (九宫格拨号点阵 + 粘贴)
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.28)
                  : Colors.white.withValues(alpha: 0.90),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: isDark
                    ? pack.primary.withValues(alpha: 0.25)
                    : pack.primary.withValues(alpha: 0.40),
                width: 1.1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  Icons.apps_rounded,
                  color: isDark ? pack.primary : pack.secondary,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _targetIdController,
                    style: TextStyle(
                      color: isDark
                          ? pack.darkTextPrimary
                          : const Color(0xFF1E293B),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: '请输入对方的用户 ID',
                      hintStyle: TextStyle(
                        color: isDark
                            ? pack.darkTextPrimary.withValues(alpha: 0.45)
                            : const Color(0xFF94A3B8),
                        fontSize: 14,
                        fontWeight: FontWeight.normal,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (_targetIdController.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _targetIdController.clear();
                      setState(() {});
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.cancel_rounded,
                        size: 18,
                        color:
                            isDark ? Colors.white54 : const Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                GestureDetector(
                  onTap: () async {
                    final data =
                        await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null && data!.text!.isNotEmpty) {
                      _targetIdController.text = data.text!.trim();
                      setState(() {});
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.assignment_outlined,
                      size: 22,
                      color: isDark ? pack.primary : pack.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 主题专属流光大呼叫按钮
          SizedBox(
            width: double.infinity,
            height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: pack.buttonGradient,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: pack.primary.withValues(alpha: 0.38),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                ),
                icon: const Icon(
                  Icons.phone_in_talk_rounded,
                  color: Colors.white,
                  size: 21,
                ),
                label: Text(
                  l10n.dialButton,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                onPressed: () => _makeCall(_targetIdController.text),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncomingCallOverlay() {
    final l10n = _l10n();
    final caller = _webrtcService.currentPeerId ?? l10n.unknownUser;
    final callerAvatar = _buildPeerAvatar(
      _webrtcService.remotePeerAvatar,
      _webrtcService.remotePeerAvatarImage,
      _webrtcService.currentPeerId ?? '',
    );

    return Container(
      color: Colors.black.withValues(alpha: 0.94),
      width: double.infinity,
      height: double.infinity,
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            AvatarCircle(avatar: callerAvatar, size: 110, glow: true),
            const SizedBox(height: 24),
            Text(
              l10n.incomingCall,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              caller,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock, color: Color(0xFF10B981), size: 14),
                  const SizedBox(width: 6),
                  Text(
                    l10n.e2eUdpBadge,
                    style: const TextStyle(
                        color: Color(0xFF10B981), fontSize: 12),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      FloatingActionButton(
                        heroTag: 'reject_call',
                        backgroundColor: const Color(0xFFEF4444),
                        onPressed: () => _webrtcService.rejectCall(),
                        child: const Icon(Icons.call_end,
                            color: Colors.white, size: 28),
                      ),
                      const SizedBox(height: 8),
                      Text(l10n.hangup,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                  Column(
                    children: [
                      FloatingActionButton(
                        heroTag: 'accept_call',
                        backgroundColor: const Color(0xFF10B981),
                        onPressed: () => _webrtcService.acceptCall(),
                        child: const Icon(Icons.call,
                            color: Colors.white, size: 28),
                      ),
                      const SizedBox(height: 8),
                      Text(l10n.answer,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveCallOverlay() {
    final l10n = _l10n();
    final peer = _webrtcService.currentPeerId ?? '';
    final peerAvatar = _buildPeerAvatar(
      _webrtcService.remotePeerAvatar,
      _webrtcService.remotePeerAvatarImage,
      _webrtcService.currentPeerId ?? '',
    );
    final isConnected = _callStatus == CallStatus.connected;
    final isDirect = _webrtcService.connectionType.contains('穿透') ||
        _webrtcService.connectionType.contains('SRTP');

    final headerText = isConnected
        ? (isDirect ? l10n.secureCalling : l10n.p2pCalling)
        : l10n.establishing;

    return Container(
      color: const Color(0xFF0B1120),
      width: double.infinity,
      height: double.infinity,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 30),
            Text(
              headerText,
              style: TextStyle(
                color: isConnected
                    ? const Color(0xFF34D399)
                    : const Color(0xFFF59E0B),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            AvatarCircle(avatar: peerAvatar, size: 96, glow: true),
            const SizedBox(height: 14),
            Text(
              peer,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              isConnected ? _formatDuration(_callSeconds) : l10n.negotiating,
              style: TextStyle(
                color: isConnected ? Colors.white70 : const Color(0xFF94A3B8),
                fontSize: 16,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.transportProtocol,
                          style: const TextStyle(
                              color: Color(0xFF94A3B8), fontSize: 12)),
                      Text(
                        _webrtcService.connectionType,
                        style: TextStyle(
                          color:
                              _webrtcService.connectionType.contains('直连')
                                  ? const Color(0xFF34D399)
                                  : const Color(0xFF38BDF8),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.iceStateLabel,
                          style: const TextStyle(
                              color: Color(0xFF94A3B8), fontSize: 12)),
                      Text(
                        _iceState,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 40, left: 30, right: 30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _callControl(
                    icon: _webrtcService.isMuted ? Icons.mic_off : Icons.mic,
                    label: _webrtcService.isMuted
                        ? l10n.mutedLabel
                        : l10n.micLabel,
                    active: _webrtcService.isMuted,
                    onPressed: () async {
                      await _webrtcService.toggleMute();
                      if (mounted) setState(() {});
                    },
                  ),
                  _callControl(
                    icon: Icons.call_end,
                    label: l10n.hangup,
                    active: false,
                    danger: true,
                    onPressed: () => _webrtcService.hangup(),
                  ),
                  _callControl(
                    icon: _webrtcService.isSpeakerphoneOn
                        ? Icons.volume_up
                        : Icons.volume_down,
                    label: _webrtcService.isSpeakerphoneOn
                        ? l10n.speakerLabel
                        : l10n.earpieceLabel,
                    active: _webrtcService.isSpeakerphoneOn,
                    onPressed: () async {
                      await _webrtcService.toggleSpeakerphone();
                      if (mounted) setState(() {});
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _callControl({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onPressed,
    bool danger = false,
  }) {
    return Column(
      children: [
        IconButton.filled(
          style: IconButton.styleFrom(
            backgroundColor: danger
                ? const Color(0xFFEF4444)
                : (active ? Colors.white : const Color(0xFF1E293B)),
            padding: EdgeInsets.all(danger ? 20 : 16),
          ),
          icon: Icon(
            icon,
            color: danger
                ? Colors.white
                : (active ? Colors.black : Colors.white),
            size: danger ? 34 : 28,
          ),
          onPressed: onPressed,
        ),
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  Future<void> _pickAndAddCustomAvatar(StateSetter setModalState) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 256,
        maxHeight: 256,
        imageQuality: 85,
      );
      if (pickedFile == null) return;

      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedImage =
          await File(pickedFile.path).copy('${appDir.path}/$fileName');

      final newId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
      final newAvatar = AvatarItem(
        id: newId,
        name: '自定义',
        emoji: '🖼️',
        imagePath: savedImage.path,
        gradient: const [Color(0xFF0284C7), Color(0xFF38BDF8)],
      );

      await AvatarManager.addAvatar(newAvatar);
      setState(() => _myAvatar = newId);
      setModalState(() {});

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_avatar', newId);

      // Share the custom photo with other devices via the signaling server.
      _myAvatarImageBase64 = await AvatarManager.imageToBase64(savedImage.path);
      _signalingService.updateProfile(
          newAvatar: newId, newAvatarImage: _myAvatarImageBase64);

      if (mounted) {
        _showSnack('已添加并切换为自定义头像');
      }
    } catch (e) {
      if (mounted) {
        _showSnack('添加头像失败: $e');
      }
    }
  }

  void _showAvatarPicker(bool isDark, ThemeColorPack pack) {
    final l10n = _l10n();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final avatars = AvatarManager.presets;

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: BoxDecoration(
                color: isDark ? pack.darkBgStart : pack.lightBgStart,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.08),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 拖拽手柄
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 标题与添加自定义头像按钮
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.avatarPickerTitle,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? pack.darkTextPrimary
                                    : pack.lightTextPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '轻点选择头像，右上角红色叉号可删除',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? pack.darkTextPrimary
                                        .withValues(alpha: 0.55)
                                    : pack.lightTextPrimary
                                        .withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                        // 从相册添加头像按钮
                        Container(
                          height: 36,
                          decoration: BoxDecoration(
                            gradient: pack.buttonGradient,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: pack.primary.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            icon: const Icon(
                              Icons.add_photo_alternate_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                            label: const Text(
                              '添加头像',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: () =>
                                _pickAndAddCustomAvatar(setModalState),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 头像网格展示与管理
                    Expanded(
                      child: GridView.builder(
                        physics: const BouncingScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 14,
                          childAspectRatio: 0.82,
                        ),
                        itemCount: avatars.length,
                        itemBuilder: (context, index) {
                          final item = avatars[index];
                          final isSelected = item.id == _myAvatar;

                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              GestureDetector(
                                onTap: () async {
                                  setState(() => _myAvatar = item.id);
                                  setModalState(() {});
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  await prefs.setString('user_avatar', item.id);

                                  String? avatarImage;
                                  if (item.imagePath != null &&
                                      item.imagePath!.isNotEmpty) {
                                    avatarImage = await AvatarManager
                                        .imageToBase64(item.imagePath!);
                                  }
                                  _myAvatarImageBase64 = avatarImage;
                                  _signalingService.updateProfile(
                                      newAvatar: item.id,
                                      newAvatarImage: avatarImage);
                                  if (context.mounted) Navigator.pop(context);
                                },
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AvatarCircle(
                                        avatar: item,
                                        size: 56,
                                        border: isSelected
                                            ? Border.all(
                                                color: pack.primary,
                                                width: 3.5,
                                              )
                                            : null,
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        l10n.avatarName(item.id),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: isDark
                                              ? (isSelected
                                                  ? pack.primary
                                                  : pack.darkTextPrimary
                                                      .withValues(alpha: 0.75))
                                              : (isSelected
                                                  ? pack.secondary
                                                  : pack.lightTextPrimary
                                                      .withValues(alpha: 0.75)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // 允许用户自行删除默认头像与自定义头像
                              if (avatars.length > 1)
                                Positioned(
                                  top: 0,
                                  right: 4,
                                  child: GestureDetector(
                                    onTap: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('删除头像'),
                                          content: Text(
                                              '确定要删除头像「${l10n.avatarName(item.id)}」吗？'),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: const Text('取消'),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: const Text('删除',
                                                  style: TextStyle(
                                                      color: Colors.redAccent)),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm != true) return;

                                      if (item.id == _myAvatar) {
                                        final other = avatars.firstWhere(
                                            (a) => a.id != item.id);
                                        setState(() => _myAvatar = other.id);
                                        final prefs =
                                            await SharedPreferences
                                                .getInstance();
                                        await prefs.setString(
                                            'user_avatar', other.id);

                                        String? avatarImage;
                                        if (other.imagePath != null &&
                                            other.imagePath!.isNotEmpty) {
                                          avatarImage = await AvatarManager
                                              .imageToBase64(other.imagePath!);
                                        }
                                        _myAvatarImageBase64 = avatarImage;
                                        _signalingService.updateProfile(
                                            newAvatar: other.id,
                                            newAvatarImage: avatarImage);
                                      }

                                      await AvatarManager.deleteAvatar(item.id);
                                      setModalState(() {});
                                      setState(() {});
                                      if (mounted) {
                                        _showSnack('已移除头像');
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(3.5),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isDark
                                            ? Colors.black87
                                            : Colors.white,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.20),
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.close_rounded,
                                        size: 13,
                                        color: Colors.redAccent,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),

                    // 恢复默认预设
                    Center(
                      child: TextButton.icon(
                        icon: const Icon(Icons.restart_alt_rounded, size: 16),
                        label: const Text('恢复全部默认预设头像',
                            style: TextStyle(fontSize: 12)),
                        onPressed: () async {
                          await AvatarManager.resetToDefaults();
                          setModalState(() {});
                          setState(() {});
                          if (mounted) _showSnack('已恢复默认头像列表');
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showEditUserIdDialog(bool isDark, ThemeColorPack pack) {
    final l10n = _l10n();
    final controller = TextEditingController(text: _myUserId);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? pack.darkBgStart : pack.lightBgStart,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          l10n.editIdTitle,
          style: TextStyle(
              color: isDark ? pack.darkTextPrimary : pack.lightTextPrimary),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(
              color: isDark ? pack.darkTextPrimary : pack.lightTextPrimary),
          decoration: InputDecoration(
            hintText: l10n.enterNewIdHint,
            hintStyle: TextStyle(
              color: isDark
                  ? pack.darkTextPrimary.withValues(alpha: 0.4)
                  : pack.lightTextPrimary.withValues(alpha: 0.4),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            child: Text(
              l10n.cancel,
              style: TextStyle(
                color: isDark
                    ? pack.darkTextPrimary.withValues(alpha: 0.6)
                    : pack.lightTextPrimary.withValues(alpha: 0.6),
              ),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: pack.secondary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(l10n.save,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () async {
              final newId = controller.text.trim();
              if (newId.isNotEmpty && newId != _myUserId) {
                setState(() => _myUserId = newId);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('user_id', newId);
                _signalingService.updateProfile(newUserId: newId);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Widget _settingsSectionHeader({
    required IconData icon,
    required String title,
    required bool isDark,
    required ThemeColorPack pack,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: isDark ? pack.primary : pack.secondary,
        ),
        const SizedBox(width: 7),
        Text(
          title,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: isDark ? pack.darkTextPrimary : pack.lightTextPrimary,
          ),
        ),
      ],
    );
  }

  Widget _styledSettingsField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData prefixIcon,
    required bool isDark,
    required ThemeColorPack pack,
    bool obscureText = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: isDark
                ? pack.darkTextPrimary.withValues(alpha: 0.7)
                : pack.lightTextPrimary.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 5),
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Icon(
                prefixIcon,
                size: 18,
                color: isDark ? pack.primary : pack.secondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: obscureText,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: isDark
                        ? pack.darkTextPrimary
                        : pack.lightTextPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showSettingsDialog(bool isDark, ThemeColorPack pack) async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final tokenController =
        TextEditingController(text: prefs.getString('access_token') ?? '');

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final l10n = AppLocalizations.of(context)!;
            final currentTheme = currentThemeTypeNotifier.value;
            final currentThemePack = AppTheme.getPack(currentTheme);

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: GlassCard(
                isDark: isDark,
                borderRadius: 26,
                blurSigma: 24,
                backgroundColor: isDark
                    ? const Color(0xE60D1520)
                    : const Color(0xF2FFFFFF),
                borderGradient: currentThemePack.gradient,
                padding: const EdgeInsets.all(22),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.85,
                  ),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 标题栏
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    gradient: currentThemePack.gradient,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.tune_rounded,
                                    color: isDark
                                        ? currentThemePack.darkBgStart
                                        : Colors.white,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  l10n.settingsTitle,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: isDark
                                        ? currentThemePack.darkTextPrimary
                                        : currentThemePack.lightTextPrimary,
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.close_rounded,
                                color: isDark
                                    ? Colors.white70
                                    : const Color(0xFF64748B),
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // ==========================================
                        // 板块 1：🎨 专属东方国色主题切换 (收纳至设置)
                        // ==========================================
                        _settingsSectionHeader(
                          icon: Icons.palette_outlined,
                          title: '默认主题配色',
                          isDark: isDark,
                          pack: currentThemePack,
                        ),
                        const SizedBox(height: 10),
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 2.3,
                          children: AppThemeType.values.map((type) {
                            final p = AppTheme.getPack(type);
                            final isSelected = type == currentTheme;
                            return GestureDetector(
                              onTap: () async {
                                currentThemeTypeNotifier.value = type;
                                final pPrefs =
                                    await SharedPreferences.getInstance();
                                await pPrefs.setString('theme_type', type.name);
                                setDialogState(() {});
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? (isDark
                                          ? p.primary.withValues(alpha: 0.25)
                                          : Colors.white)
                                      : (isDark
                                          ? Colors.white.withValues(alpha: 0.05)
                                          : const Color(0xFFF1F5F9)),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected
                                        ? p.primary
                                        : (isDark
                                            ? Colors.white
                                                .withValues(alpha: 0.12)
                                            : Colors.black
                                                .withValues(alpha: 0.08)),
                                    width: isSelected ? 2.0 : 1.0,
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: p.primary
                                                .withValues(alpha: 0.35),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: p.gradient,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        p.name,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          color: isSelected
                                              ? (isDark
                                                  ? p.primary
                                                  : const Color(0xFF0F172A))
                                              : (isDark
                                                  ? Colors.white70
                                                  : const Color(0xFF475569)),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isSelected)
                                      Icon(
                                        Icons.check_circle_rounded,
                                        size: 16,
                                        color: isDark
                                            ? p.primary
                                            : const Color(0xFF0F172A),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 18),

                        // ==========================================
                        // 板块 2：🌓 外观与视觉 (亮暗模式 & 背景壁纸)
                        // ==========================================
                        _settingsSectionHeader(
                          icon: Icons.auto_awesome_rounded,
                          title: '外观与个性化',
                          isDark: isDark,
                          pack: currentThemePack,
                        ),
                        const SizedBox(height: 10),

                        // 自定义壁纸 (支持自动等比缩放消除留白与多档微调)
                        if (_backgroundPath != null &&
                            File(_backgroundPath!).existsSync()) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.06),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.file(
                                        File(_backgroundPath!),
                                        width: 44,
                                        height: 44,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        l10n.backgroundSaved,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: isDark
                                              ? currentThemePack.darkTextPrimary
                                              : currentThemePack.lightTextPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined,
                                          size: 20),
                                      tooltip: l10n.chooseImage,
                                      onPressed: () async {
                                        await _pickBackground(
                                            setDialogState: setDialogState);
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 20,
                                          color: Colors.redAccent),
                                      tooltip: l10n.resetBackground,
                                      onPressed: () async {
                                        await _resetBackground(
                                            setDialogState: setDialogState);
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              side: BorderSide(
                                color: isDark
                                    ? currentThemePack.primary
                                        .withValues(alpha: 0.4)
                                    : currentThemePack.secondary
                                        .withValues(alpha: 0.4),
                              ),
                            ),
                            icon: Icon(
                              Icons.image_outlined,
                              size: 18,
                              color: isDark
                                  ? currentThemePack.primary
                                  : currentThemePack.secondary,
                            ),
                            label: Text(
                              '选择相册图片作为背景',
                              style: TextStyle(
                                color: isDark
                                    ? currentThemePack.primary
                                    : currentThemePack.secondary,
                              ),
                            ),
                            onPressed: () async {
                              await _pickBackground(
                                  setDialogState: setDialogState);
                            },
                          ),
                        ],
                        const SizedBox(height: 18),

                        // ==========================================
                        // 板块 3：🌐 网络与穿透连接
                        // ==========================================
                        _settingsSectionHeader(
                          icon: Icons.hub_outlined,
                          title: '网络与穿透服务',
                          isDark: isDark,
                          pack: currentThemePack,
                        ),
                        const SizedBox(height: 10),

                        _styledSettingsField(
                          label: l10n.serverLabel,
                          hint: 'ws://server-ip:8080',
                          controller: _serverUrlController,
                          prefixIcon: Icons.dns_rounded,
                          isDark: isDark,
                          pack: currentThemePack,
                        ),
                        const SizedBox(height: 10),

                        _styledSettingsField(
                          label: l10n.stunLabel,
                          hint: 'stun:server-ip:3478',
                          controller: _stunServerController,
                          prefixIcon: Icons.cell_tower_rounded,
                          isDark: isDark,
                          pack: currentThemePack,
                        ),
                        const SizedBox(height: 10),

                        _styledSettingsField(
                          label: l10n.tokenLabel,
                          hint: '留空表示无密码访问',
                          controller: tokenController,
                          prefixIcon: Icons.key_rounded,
                          isDark: isDark,
                          pack: currentThemePack,
                          obscureText: true,
                        ),
                        const SizedBox(height: 18),

                        // ==========================================
                        // 板块 4：🌍 语言切换
                        // ==========================================
                        _settingsSectionHeader(
                          icon: Icons.translate_rounded,
                          title: l10n.languageLabel,
                          isDark: isDark,
                          pack: currentThemePack,
                        ),
                        const SizedBox(height: 10),
                        ValueListenableBuilder<String>(
                          valueListenable: languageCodeNotifier,
                          builder: (context, lang, _) {
                            final options = [
                              {'code': 'auto', 'label': l10n.languageAuto},
                              {'code': 'zh', 'label': '中文'},
                              {'code': 'en', 'label': 'English'},
                              {'code': 'fr', 'label': 'Français'},
                            ];
                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: options.map((opt) {
                                final isSelected = opt['code'] == lang;
                                return ChoiceChip(
                                  label: Text(opt['label']!),
                                  selected: isSelected,
                                  selectedColor: currentThemePack.primary
                                      .withValues(alpha: isDark ? 0.3 : 0.2),
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? (isDark
                                            ? currentThemePack.primary
                                            : const Color(0xFF0F172A))
                                        : (isDark
                                            ? Colors.white70
                                            : const Color(0xFF475569)),
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 12.5,
                                  ),
                                  onSelected: (_) async {
                                    languageCodeNotifier.value = opt['code']!;
                                    final pPrefs =
                                        await SharedPreferences.getInstance();
                                    await pPrefs.setString(
                                        'language_code', opt['code']!);
                                    setDialogState(() {});
                                  },
                                );
                              }).toList(),
                            );
                          },
                        ),
                        const SizedBox(height: 22),

                        // 底部操作按钮
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Text(l10n.cancel),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  gradient: currentThemePack.buttonGradient,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: currentThemePack.primary
                                          .withValues(alpha: 0.35),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: Text(
                                    l10n.applySave,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  onPressed: () async {
                                    final pPrefs =
                                        await SharedPreferences.getInstance();
                                    await pPrefs.setString('server_url',
                                        _serverUrlController.text.trim());
                                    await pPrefs.setString('stun_server',
                                        _stunServerController.text.trim());
                                    await pPrefs.setString('access_token',
                                        tokenController.text.trim());

                                    _signalingService.setAuthToken(
                                        tokenController.text.trim());
                                    _webrtcService.updateStunServer(
                                        _stunServerController.text);
                                    _connectSignaling();
                                    if (context.mounted) Navigator.pop(context);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    tokenController.dispose();
  }
}

/// 发起呼叫控制台右下角音波/心率动态装饰线 (完全复刻参考截图)
class _AudioWaveformPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(0, size.height * 0.72);

    // 平滑有机声波曲线
    path.quadraticBezierTo(
        size.width * 0.12, size.height * 0.68, size.width * 0.22, size.height * 0.74);
    path.quadraticBezierTo(
        size.width * 0.32, size.height * 0.82, size.width * 0.42, size.height * 0.48);
    path.quadraticBezierTo(
        size.width * 0.50, size.height * 0.12, size.width * 0.58, size.height * 0.85);
    path.quadraticBezierTo(
        size.width * 0.66, size.height * 0.98, size.width * 0.74, size.height * 0.32);
    path.quadraticBezierTo(
        size.width * 0.82, size.height * 0.08, size.width * 0.88, size.height * 0.68);
    path.quadraticBezierTo(
        size.width * 0.94, size.height * 0.76, size.width, size.height * 0.65);

    canvas.drawPath(path, paint);

    // 第二道微弱层次声波
    final faintPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final faintPath = Path();
    faintPath.moveTo(size.width * 0.15, size.height * 0.78);
    faintPath.quadraticBezierTo(
        size.width * 0.35, size.height * 0.58, size.width * 0.52, size.height * 0.74);
    faintPath.quadraticBezierTo(
        size.width * 0.68, size.height * 0.28, size.width * 0.82, size.height * 0.52);
    faintPath.quadraticBezierTo(
        size.width * 0.92, size.height * 0.80, size.width, size.height * 0.58);

    canvas.drawPath(faintPath, faintPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

