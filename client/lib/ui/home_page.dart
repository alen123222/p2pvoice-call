import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/avatar_model.dart';
import '../models/call_state.dart';
import '../services/foreground_service.dart';
import '../services/signaling_service.dart';
import '../services/webrtc_service.dart';
import '../theme/app_theme.dart';

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

    if (mounted) setState(() {});
    _connectSignaling();
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
                _webrtcService.currentPeerId ?? '对端用户');
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    };
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

  void _makeCall(String targetId, {String? targetAvatar}) async {
    final target = targetId.trim();
    if (target.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入对方的用户 ID')),
      );
      return;
    }
    if (target == _myUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('不能呼叫自己')),
      );
      return;
    }

    if (targetAvatar != null) {
      _webrtcService.setRemotePeerAvatar(targetAvatar);
    }

    await _webrtcService.startCall(target);
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
        return Scaffold(
          backgroundColor: isDark ? AppTheme.darkBg : AppTheme.skyBg,
          appBar: AppBar(
            backgroundColor: isDark ? AppTheme.darkCard : AppTheme.skyCard,
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
                  'P2P 语音直通',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: isDark ? Colors.white : AppTheme.skyTextPrimary,
                  ),
                ),
              ],
            ),
            actions: [
              _buildSignalingStatusPill(isDark),
              IconButton(
                icon: Icon(
                  isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  color: isDark ? Colors.amber : AppTheme.skyAccent,
                ),
                tooltip: isDark ? '切换为天蓝浅色主题' : '切换为深色主题',
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
                tooltip: '网络与服务器设置',
                onPressed: () => _showSettingsDialog(isDark),
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: Stack(
            children: [
              SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
              // Incoming call overlay
              if (_callStatus == CallStatus.incoming)
                _buildIncomingCallOverlay(isDark),
              // Active or Calling overlay
              if (_callStatus == CallStatus.calling ||
                  _callStatus == CallStatus.connected)
                _buildActiveCallOverlay(isDark),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSignalingStatusPill(bool isDark) {
    Color color;
    String text;
    IconData? icon;

    switch (_signalingStatus) {
      case SignalingStatus.connected:
        color = const Color(0xFF10B981);
        text = '在线';
        break;
      case SignalingStatus.connecting:
        color = const Color(0xFFF59E0B);
        text = '连接中';
        break;
      case SignalingStatus.reconnecting:
        color = const Color(0xFFF97316);
        text = '自动重连中';
        icon = Icons.sync;
        break;
      case SignalingStatus.error:
      case SignalingStatus.disconnected:
        color = const Color(0xFFEF4444);
        text = '未连信令';
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
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildMyIdentityCard(bool isDark) {
    final avatarItem = AvatarManager.getById(_myAvatar);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.skyCard,
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
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: avatarItem.gradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: avatarItem.gradient.first.withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    avatarItem.emoji,
                    style: const TextStyle(fontSize: 28),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                      shape: BoxShape.circle,
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
                      '我的用户 ID',
                      style: TextStyle(
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.skyTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(${avatarItem.name})',
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
                  _myUserId.isEmpty ? '加载中...' : _myUserId,
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
            tooltip: '复制 ID',
            onPressed: () {
              if (_myUserId.isNotEmpty) {
                Clipboard.setData(ClipboardData(text: _myUserId));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制用户 ID 到剪贴板')),
                );
              }
            },
          ),
          IconButton(
            icon: Icon(
              Icons.edit,
              color: isDark ? Colors.white70 : AppTheme.skyTextSecondary,
              size: 20,
            ),
            tooltip: '修改 ID',
            onPressed: () => _showEditUserIdDialog(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectP2PNotice(bool isDark) {
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
              '安全直连：音频流在手机间通过硬件级 DTLS-SRTP 密文点对点传输，零云端存储，防窃听防篡改。',
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.skyCard,
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
            '发起 P2P 呼叫',
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
              hintText: '输入对方的用户 ID (例如 user_8888)',
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? const Color(0xFF2563EB) : AppTheme.skyButton,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 3,
              ),
              icon: const Icon(Icons.phone, color: Colors.white),
              label: const Text(
                '开始高清直连通话',
                style: TextStyle(
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  '当前在线设备',
                  style: TextStyle(
                    color: isDark ? Colors.white : AppTheme.skyTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                  '暂无其他设备在线',
                  style: TextStyle(
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.skyTextSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '在另一台手机上启动本应用即可在此自动感知',
                  style: TextStyle(
                    color: isDark ? const Color(0xFF64748B) : const Color(0xFF64748B),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkCard : AppTheme.skyCard,
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
                    Stack(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: peerAvatar.gradient,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            peerAvatar.emoji,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            peer.userId,
                            style: TextStyle(
                              color: isDark ? Colors.white : AppTheme.skyTextPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            peerAvatar.name,
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
                        backgroundColor: const Color(0xFF059669),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.phone, size: 16, color: Colors.white),
                      label: const Text('直拨', style: TextStyle(color: Colors.white, fontSize: 13)),
                      onPressed: () => _makeCall(peer.userId, targetAvatar: peer.avatar),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildIncomingCallOverlay(bool isDark) {
    final caller = _webrtcService.currentPeerId ?? '未知设备';
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
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: callerAvatar.gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: callerAvatar.gradient.first.withValues(alpha: 0.5),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(callerAvatar.emoji, style: const TextStyle(fontSize: 54)),
            ),
            const SizedBox(height: 24),
            const Text(
              '收到 P2P 直连呼叫',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 16),
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
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock, color: Color(0xFF10B981), size: 14),
                  SizedBox(width: 6),
                  Text(
                    '端到端 UDP 加密直连',
                    style: TextStyle(color: Color(0xFF10B981), fontSize: 12),
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
                        child: const Icon(Icons.call_end, color: Colors.white, size: 28),
                      ),
                      const SizedBox(height: 8),
                      const Text('挂断', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                  Column(
                    children: [
                      FloatingActionButton(
                        heroTag: 'accept_call',
                        backgroundColor: const Color(0xFF10B981),
                        onPressed: () => _webrtcService.acceptCall(),
                        child: const Icon(Icons.call, color: Colors.white, size: 28),
                      ),
                      const SizedBox(height: 8),
                      const Text('接听', style: TextStyle(color: Colors.white70, fontSize: 13)),
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

  Widget _buildActiveCallOverlay(bool isDark) {
    final peer = _webrtcService.currentPeerId ?? '';
    final peerAvatar = AvatarManager.getById(_webrtcService.remotePeerAvatar);
    final isConnected = _callStatus == CallStatus.connected;

    return Container(
      color: isDark ? const Color(0xFF0B1120) : const Color(0xFF082F49),
      width: double.infinity,
      height: double.infinity,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 30),
            // Header status
            Text(
              isConnected
                  ? (_webrtcService.connectionType.contains('穿透') ||
                          _webrtcService.connectionType.contains('SRTP')
                      ? '🔒 端到端加密安全通话中'
                      : '🟢 100% P2P 纯直连通话中')
                  : '正在建立端到端加密直连...',
              style: TextStyle(
                color: isConnected
                    ? const Color(0xFF34D399)
                    : const Color(0xFFF59E0B),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),

            // Peer Avatar with glow
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: peerAvatar.gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: peerAvatar.gradient.first.withValues(alpha: 0.5),
                    blurRadius: 18,
                    spreadRadius: 3,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(peerAvatar.emoji, style: const TextStyle(fontSize: 48)),
            ),
            const SizedBox(height: 14),

            Text(
              peer,
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              isConnected ? _formatDuration(_callSeconds) : '信令协商与 NAT 打洞中...',
              style: TextStyle(
                color: isConnected ? Colors.white70 : const Color(0xFF94A3B8),
                fontSize: 16,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 16),

            // Connection metrics badge
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                      const Text('传输协议', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                      Text(
                        _webrtcService.connectionType,
                        style: TextStyle(
                          color: _webrtcService.connectionType.contains('直连')
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
                      const Text('ICE 状态', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                      Text(
                        _iceState,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Spacer(),

            // In-call control bar
            Padding(
              padding: const EdgeInsets.only(bottom: 40, left: 30, right: 30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mute toggle
                  Column(
                    children: [
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: _webrtcService.isMuted
                              ? Colors.white
                              : const Color(0xFF1E293B),
                          padding: const EdgeInsets.all(16),
                        ),
                        icon: Icon(
                          _webrtcService.isMuted ? Icons.mic_off : Icons.mic,
                          color: _webrtcService.isMuted ? Colors.black : Colors.white,
                          size: 28,
                        ),
                        onPressed: () async {
                          await _webrtcService.toggleMute();
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _webrtcService.isMuted ? '已静音' : '麦克风',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),

                  // Hangup button
                  Column(
                    children: [
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          padding: const EdgeInsets.all(20),
                        ),
                        icon: const Icon(Icons.call_end, color: Colors.white, size: 34),
                        onPressed: () => _webrtcService.hangup(),
                      ),
                      const SizedBox(height: 8),
                      const Text('挂断', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),

                  // Speaker toggle
                  Column(
                    children: [
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: _webrtcService.isSpeakerphoneOn
                              ? Colors.white
                              : const Color(0xFF1E293B),
                          padding: const EdgeInsets.all(16),
                        ),
                        icon: Icon(
                          _webrtcService.isSpeakerphoneOn
                              ? Icons.volume_up
                              : Icons.volume_down,
                          color: _webrtcService.isSpeakerphoneOn ? Colors.black : Colors.white,
                          size: 28,
                        ),
                        onPressed: () async {
                          await _webrtcService.toggleSpeakerphone();
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _webrtcService.isSpeakerphoneOn ? '扬声器' : '听筒',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
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

  void _showAvatarPicker(bool isDark) {
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
                        '选择您的专属头像',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppTheme.skyTextPrimary,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: isDark ? Colors.white70 : AppTheme.skyTextSecondary,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: GridView.builder(
                      shrinkWrap: true,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('user_avatar', item.id);
                            _signalingService.updateProfile(newAvatar: item.id);
                            if (context.mounted) Navigator.pop(context);
                          },
                          child: Column(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: item.gradient,
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  shape: BoxShape.circle,
                                  border: isSelected
                                      ? Border.all(
                                          color: isDark
                                              ? const Color(0xFF38BDF8)
                                              : const Color(0xFF0284C7),
                                          width: 3,
                                        )
                                      : null,
                                  boxShadow: [
                                    if (isSelected)
                                      BoxShadow(
                                        color: item.gradient.first.withValues(alpha: 0.5),
                                        blurRadius: 10,
                                        spreadRadius: 2,
                                      ),
                                  ],
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  item.emoji,
                                  style: const TextStyle(fontSize: 28),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.name,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isDark
                                      ? (isSelected ? AppTheme.darkAccent : Colors.white70)
                                      : (isSelected ? AppTheme.skyAccent : AppTheme.skyTextSecondary),
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
    final controller = TextEditingController(text: _myUserId);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkCard : AppTheme.skyCard,
        title: Text(
          '修改用户 ID',
          style: TextStyle(color: isDark ? Colors.white : AppTheme.skyTextPrimary),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(color: isDark ? Colors.white : AppTheme.skyTextPrimary),
          decoration: InputDecoration(
            hintText: '请输入新 ID',
            hintStyle: TextStyle(
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
            ),
          ),
        ),
        actions: [
          TextButton(
            child: Text(
              '取消',
              style: TextStyle(
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.skyTextSecondary,
              ),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFF2563EB) : AppTheme.skyButton,
            ),
            child: const Text('保存修改', style: TextStyle(color: Colors.white)),
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
    );
  }

  void _showSettingsDialog(bool isDark) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkCard : AppTheme.skyCard,
        title: Text(
          '服务器与网络设置',
          style: TextStyle(color: isDark ? Colors.white : AppTheme.skyTextPrimary),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WebSocket 信令服务器地址',
                style: TextStyle(
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.skyTextSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _serverUrlController,
                style: TextStyle(
                  color: isDark ? Colors.white : AppTheme.skyTextPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'ws://硅谷服务器IP:8080',
                  hintStyle: TextStyle(
                    color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                  ),
                  filled: true,
                  fillColor: isDark ? AppTheme.darkBg : AppTheme.skyBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'STUN 打洞穿透服务器',
                style: TextStyle(
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.skyTextSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _stunServerController,
                style: TextStyle(
                  color: isDark ? Colors.white : AppTheme.skyTextPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'stun:硅谷服务器IP:3478 或 stun.l.google.com:19302',
                  hintStyle: TextStyle(
                    color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                  ),
                  filled: true,
                  fillColor: isDark ? AppTheme.darkBg : AppTheme.skyBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '注：修改后将自动保存并重新连接信令服务。',
                style: TextStyle(
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF64748B),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: Text(
              '取消',
              style: TextStyle(
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.skyTextSecondary,
              ),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFF2563EB) : AppTheme.skyButton,
            ),
            child: const Text('应用并保存', style: TextStyle(color: Colors.white)),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('server_url', _serverUrlController.text.trim());
              await prefs.setString('stun_server', _stunServerController.text.trim());

              _webrtcService.updateStunServer(_stunServerController.text);
              _connectSignaling();
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
