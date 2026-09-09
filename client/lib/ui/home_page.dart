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

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late final SignalingService _signalingService;
  late final WebRTCService _webrtcService;

  final TextEditingController _targetIdController = TextEditingController();
  final TextEditingController _serverUrlController =
      TextEditingController(text: 'ws://170.106.195.109:8080');
  final TextEditingController _stunServerController =
      TextEditingController(text: '170.106.195.109:3478');

  String _myUserId = '';
  String _myAvatar = 'pilot';
  SignalingStatus _signalingStatus = SignalingStatus.disconnected;
  CallStatus _callStatus = CallStatus.idle;
  List<PeerInfo> _onlinePeers = [];
  String _iceState = 'Idle';
  String? _backgroundPath;

  Timer? _callDurationTimer;
  int _callSeconds = 0;

  StreamSubscription? _signalingSub;
  StreamSubscription? _callStatusSub;
  StreamSubscription? _iceStateSub;

  @override
  void initState() {
    super.initState();
    _initServices();
    _requestPermissions();
    _loadPreferences();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.microphone,
      Permission.bluetoothConnect,
      Permission.notification,
    ].request();
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

  Color _getCardColor(bool isDark) {
    if (_backgroundPath != null && File(_backgroundPath!).existsSync()) {
      return isDark
          ? AppTheme.darkCard.withValues(alpha: 0.85)
          : AppTheme.skyCard.withValues(alpha: 0.90);
    }
    return isDark ? AppTheme.darkCard : AppTheme.skyCard;
  }

  void _initServices() {
    _signalingService = SignalingService();
    _webrtcService = WebRTCService(signalingService: _signalingService);

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
          if (status == CallStatus.connected) {
            _startCallTimer();
            ForegroundServiceManager.startCallForeground(
                _webrtcService.currentPeerId ?? _l10n().unknownUser);
          } else if (status == CallStatus.ended || status == CallStatus.idle) {
            _stopCallTimer();
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
      await _signalingService.connect(url, _myUserId, avatar: _myAvatar);
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
      print('[Background] Failed to set background: $e');
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
    _signalingSub?.cancel();
    _callStatusSub?.cancel();
    _iceStateSub?.cancel();
    _stopCallTimer();
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
        final l10n = AppLocalizations.of(context)!;
        return Scaffold(
          backgroundColor: isDark ? AppTheme.darkBg : AppTheme.skyBg,
          appBar: AppBar(
            backgroundColor: _getCardColor(isDark),
            elevation: isDark ? 0 : 1,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: (isDark ? AppTheme.darkAccent : AppTheme.skyAccent)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.bolt,
                    color: isDark ? AppTheme.darkAccent : AppTheme.skyAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  l10n.headerTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: isDark ? Colors.white : AppTheme.skyTextPrimary,
                  ),
                ),
              ],
            ),
            actions: [
              _buildSignalingStatusPill(),
              IconButton(
                icon: Icon(
                  isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  color: isDark ? Colors.amber : AppTheme.skyAccent,
                ),
                tooltip: isDark ? l10n.tooltipLightTheme : l10n.tooltipDarkTheme,
                onPressed: () async {
                  final newMode = !isDark;
                  isDarkModeNotifier.value = newMode;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('is_dark_mode', newMode);
                },
              ),
              IconButton(
                icon: Icon(
                  Icons.settings,
                  color: isDark ? Colors.white70 : AppTheme.skyTextSecondary,
                ),
                tooltip: l10n.tooltipSettings,
                onPressed: () => _showSettingsDialog(isDark),
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: Stack(
            children: [
              if (_backgroundPath != null &&
                  File(_backgroundPath!).existsSync()) ...[
                Positioned.fill(
                  child: Image.file(
                    File(_backgroundPath!),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => const SizedBox(),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.40)
                        : Colors.white.withValues(alpha: 0.30),
                  ),
                ),
              ],
              SafeArea(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMyIdentityCard(isDark),
                      const SizedBox(height: 16),
                      _buildDirectP2PNotice(isDark),
                      const SizedBox(height: 20),
                      _buildDialCard(isDark),
                      const SizedBox(height: 24),
                      _buildOnlineUsersSection(isDark),
                    ],
                  ),
                ),
              ),
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
  }

  Widget _buildSignalingStatusPill() {
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
        icon = Icons.sync;
        break;
      case SignalingStatus.error:
      case SignalingStatus.disconnected:
        color = AppTheme.danger;
        text = l10n.statusOffline;
        break;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 12, color: color)
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildMyIdentityCard(bool isDark) {
    final l10n = _l10n();
    final avatarItem = AvatarManager.getById(_myAvatar);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _getCardColor(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.skyBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : const Color(0xFF0284C7).withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _showAvatarPicker(isDark),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AvatarCircle(avatar: avatarItem, size: 54),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF38BDF8)
                          : const Color(0xFF0284C7),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: isDark ? AppTheme.darkCard : AppTheme.skyCard,
                          width: 2),
                    ),
                    child: const Icon(Icons.edit, size: 10, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
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
                            ? AppTheme.darkTextSecondary
                            : AppTheme.skyTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(${l10n.avatarName(_myAvatar)})',
                      style: TextStyle(
                        color: isDark
                            ? AppTheme.darkAccent
                            : AppTheme.skyAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _myUserId.isEmpty ? l10n.loading : _myUserId,
                  style: TextStyle(
                    color: isDark ? Colors.white : AppTheme.skyTextPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.copy,
              color: isDark ? AppTheme.darkAccent : AppTheme.skyAccent,
              size: 20,
            ),
            tooltip: l10n.tooltipCopy,
            onPressed: () {
              if (_myUserId.isNotEmpty) {
                Clipboard.setData(ClipboardData(text: _myUserId));
                _showSnack(l10n.toastCopied);
              }
            },
          ),
          IconButton(
            icon: Icon(
              Icons.edit,
              color: isDark ? Colors.white70 : AppTheme.skyTextSecondary,
              size: 20,
            ),
            tooltip: l10n.tooltipEdit,
            onPressed: () => _showEditUserIdDialog(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectP2PNotice(bool isDark) {
    final l10n = _l10n();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF064E3B).withValues(alpha: 0.3)
            : const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? const Color(0xFF059669).withValues(alpha: 0.3)
              : const Color(0xFF86EFAC),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.shield_outlined,
            color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.secureNotice,
              style: TextStyle(
                color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF15803D),
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialCard(bool isDark) {
    final l10n = _l10n();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _getCardColor(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.skyBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : const Color(0xFF0284C7).withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.dialTitle,
            style: TextStyle(
              color: isDark ? Colors.white : AppTheme.skyTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _targetIdController,
            style: TextStyle(
              color: isDark ? Colors.white : AppTheme.skyTextPrimary,
              fontSize: 15,
            ),
            decoration: InputDecoration(
              hintText: l10n.dialHint,
              hintStyle: TextStyle(
                color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                fontSize: 14,
              ),
              filled: true,
              fillColor: isDark ? AppTheme.darkBg : AppTheme.skyBg,
              prefixIcon: Icon(
                Icons.call_outlined,
                color: isDark ? AppTheme.darkAccent : AppTheme.skyAccent,
                size: 20,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? AppTheme.darkBorder : AppTheme.skyBorder,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? AppTheme.darkBorder : AppTheme.skyBorder,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? AppTheme.darkAccent : AppTheme.skyAccent,
                ),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isDark ? AppTheme.primaryButtonDark : AppTheme.skyButton,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 3,
              ),
              icon: const Icon(Icons.phone, color: Colors.white),
              label: Text(
                l10n.dialButton,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: () => _makeCall(_targetIdController.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOnlineUsersSection(bool isDark) {
    final l10n = _l10n();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  l10n.onlineDevices,
                  style: TextStyle(
                    color: isDark ? Colors.white : AppTheme.skyTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isDark ? AppTheme.darkAccent : AppTheme.skyAccent)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_onlinePeers.length}',
                    style: TextStyle(
                      color: isDark ? AppTheme.darkAccent : AppTheme.skyAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            IconButton(
              icon: Icon(
                Icons.refresh,
                color: isDark ? Colors.white70 : AppTheme.skyTextSecondary,
                size: 20,
              ),
              onPressed: () => _signalingService.refreshUsers(),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_onlinePeers.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36),
            decoration: BoxDecoration(
              color: isDark
                  ? AppTheme.darkCard.withValues(alpha: 0.5)
                  : AppTheme.skyCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : AppTheme.skyBorder,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.devices_other,
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                  size: 36,
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.noPeers,
                  style: TextStyle(
                    color:
                        isDark ? AppTheme.darkTextSecondary : AppTheme.skyTextSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.noPeersHint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _onlinePeers.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final peer = _onlinePeers[index];
              final peerAvatar = AvatarManager.getById(peer.avatar);

              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _getCardColor(isDark),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? AppTheme.darkBorder : AppTheme.skyBorder,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.1)
                          : const Color(0xFF0284C7).withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    AvatarCircle(
                        avatar: peerAvatar, size: 44, showOnlineDot: true),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            peer.userId,
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white
                                  : AppTheme.skyTextPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.avatarName(peer.avatar),
                            style: TextStyle(
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.skyTextSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.callGreen,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.phone, size: 16, color: Colors.white),
                      label: Text(l10n.directCall,
                          style:
                              const TextStyle(color: Colors.white, fontSize: 13)),
                      onPressed: () =>
                          _makeCall(peer.userId, targetAvatar: peer.avatar),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildIncomingCallOverlay() {
    final l10n = _l10n();
    final caller = _webrtcService.currentPeerId ?? l10n.unknownUser;
    final callerAvatar = AvatarManager.getById(_webrtcService.remotePeerAvatar);

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
    final peerAvatar = AvatarManager.getById(_webrtcService.remotePeerAvatar);
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

  void _showAvatarPicker(bool isDark) {
    final l10n = _l10n();
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.darkCard : AppTheme.skyCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.avatarPickerTitle,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color:
                              isDark ? Colors.white : AppTheme.skyTextPrimary,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: isDark
                              ? Colors.white70
                              : AppTheme.skyTextSecondary,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 260,
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.88,
                      ),
                      itemCount: AvatarManager.presets.length,
                      itemBuilder: (context, index) {
                        final item = AvatarManager.presets[index];
                        final isSelected = item.id == _myAvatar;
                        return GestureDetector(
                          onTap: () async {
                            setState(() => _myAvatar = item.id);
                            setModalState(() {});
                            final prefs =
                                await SharedPreferences.getInstance();
                            await prefs.setString('user_avatar', item.id);
                            _signalingService.updateProfile(newAvatar: item.id);
                            if (context.mounted) Navigator.pop(context);
                          },
                          child: Column(
                            children: [
                              AvatarCircle(
                                avatar: item,
                                size: 56,
                                border: isSelected
                                    ? Border.all(
                                        color: isDark
                                            ? const Color(0xFF38BDF8)
                                            : const Color(0xFF0284C7),
                                        width: 3,
                                      )
                                    : null,
                              ),
                              const SizedBox(height: 4),
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
                                          ? AppTheme.darkAccent
                                          : Colors.white70)
                                      : (isSelected
                                          ? AppTheme.skyAccent
                                          : AppTheme.skyTextSecondary),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showEditUserIdDialog(bool isDark) {
    final l10n = _l10n();
    final controller = TextEditingController(text: _myUserId);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkCard : AppTheme.skyCard,
        title: Text(
          l10n.editIdTitle,
          style: TextStyle(color: isDark ? Colors.white : AppTheme.skyTextPrimary),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(
              color: isDark ? Colors.white : AppTheme.skyTextPrimary),
          decoration: InputDecoration(
            hintText: l10n.enterNewIdHint,
            hintStyle: TextStyle(
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
            ),
          ),
        ),
        actions: [
          TextButton(
            child: Text(
              l10n.cancel,
              style: TextStyle(
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.skyTextSecondary,
              ),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isDark ? AppTheme.primaryButtonDark : AppTheme.skyButton,
            ),
            child: Text(l10n.save, style: const TextStyle(color: Colors.white)),
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

  Future<void> _showSettingsDialog(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final tokenController =
        TextEditingController(text: prefs.getString('access_token') ?? '');

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final l10n = AppLocalizations.of(context)!;
            return AlertDialog(
              backgroundColor: isDark ? AppTheme.darkCard : AppTheme.skyCard,
              title: Text(
                l10n.settingsTitle,
                style: TextStyle(
                    color: isDark ? Colors.white : AppTheme.skyTextPrimary),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _settingsLabel(l10n.serverLabel, isDark),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _serverUrlController,
                      style: TextStyle(
                        color:
                            isDark ? Colors.white : AppTheme.skyTextPrimary,
                        fontSize: 14,
                      ),
                      decoration: _settingsInputDecoration(isDark,
                          hint: 'ws://server-ip:8080'),
                    ),
                    const SizedBox(height: 16),
                    _settingsLabel(l10n.stunLabel, isDark),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _stunServerController,
                      style: TextStyle(
                        color:
                            isDark ? Colors.white : AppTheme.skyTextPrimary,
                        fontSize: 14,
                      ),
                      decoration: _settingsInputDecoration(isDark,
                          hint: 'stun:server-ip:3478'),
                    ),
                    const SizedBox(height: 16),
                    _settingsLabel(l10n.tokenLabel, isDark),
                    const SizedBox(height: 6),
                    TextField(
                      controller: tokenController,
                      obscureText: true,
                      style: TextStyle(
                        color:
                            isDark ? Colors.white : AppTheme.skyTextPrimary,
                        fontSize: 14,
                      ),
                      decoration: _settingsInputDecoration(isDark, hint: ''),
                    ),
                    const SizedBox(height: 16),
                    _settingsLabel(l10n.languageLabel, isDark),
                    const SizedBox(height: 6),
                    ValueListenableBuilder<String>(
                      valueListenable: languageCodeNotifier,
                      builder: (context, lang, _) {
                        final innerL10n = AppLocalizations.of(context)!;
                        return DropdownButton<String>(
                          value: lang,
                          isExpanded: true,
                          underline: const SizedBox(),
                          items: [
                            DropdownMenuItem(
                                value: 'auto',
                                child: Text(innerL10n.languageAuto)),
                            const DropdownMenuItem(
                                value: 'zh', child: Text('中文')),
                            const DropdownMenuItem(
                                value: 'en', child: Text('English')),
                            const DropdownMenuItem(
                                value: 'fr', child: Text('Français')),
                          ],
                          onChanged: (v) async {
                            if (v == null) return;
                            languageCodeNotifier.value = v;
                            final prefs =
                                await SharedPreferences.getInstance();
                            await prefs.setString('language_code', v);
                            setDialogState(() {});
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _settingsLabel(l10n.backgroundLabel, isDark),
                    const SizedBox(height: 8),
                    if (_backgroundPath != null &&
                        File(_backgroundPath!).existsSync()) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark
                                ? AppTheme.darkBorder
                                : AppTheme.skyBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.file(
                                File(_backgroundPath!),
                                width: 42,
                                height: 42,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                l10n.backgroundSaved,
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white70
                                      : AppTheme.skyTextSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              tooltip: l10n.chooseImage,
                              onPressed: () async {
                                await _pickBackground(
                                    setDialogState: setDialogState);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 20, color: Colors.redAccent),
                              tooltip: l10n.resetBackground,
                              onPressed: () async {
                                await _resetBackground(
                                    setDialogState: setDialogState);
                              },
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(42),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.image_outlined, size: 18),
                        label: Text(l10n.chooseImage),
                        onPressed: () async {
                          await _pickBackground(setDialogState: setDialogState);
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      l10n.settingsNote,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: Text(
                    l10n.cancel,
                    style: TextStyle(
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.skyTextSecondary,
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark
                        ? AppTheme.primaryButtonDark
                        : AppTheme.skyButton,
                  ),
                  child:
                      Text(l10n.applySave, style: const TextStyle(color: Colors.white)),
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString(
                        'server_url', _serverUrlController.text.trim());
                    await prefs.setString(
                        'stun_server', _stunServerController.text.trim());
                    await prefs.setString(
                        'access_token', tokenController.text.trim());

                    _signalingService.setAuthToken(tokenController.text.trim());
                    _webrtcService.updateStunServer(_stunServerController.text);
                    _connectSignaling();
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              ],
            );
          },
        );
      },
    );
    tokenController.dispose();
  }

  Widget _settingsLabel(String text, bool isDark) {
    return Text(
      text,
      style: TextStyle(
        color: isDark ? AppTheme.darkTextSecondary : AppTheme.skyTextSecondary,
        fontSize: 12,
      ),
    );
  }

  InputDecoration _settingsInputDecoration(bool isDark, {required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
        fontSize: 14,
      ),
      filled: true,
      fillColor: isDark ? AppTheme.darkBg : AppTheme.skyBg,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
