import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/call_controller.dart';
import '../l10n/app_localizations.dart';
import '../models/avatar_model.dart';
import '../models/call_state.dart';
import '../theme/app_theme.dart';
import 'call_view.dart';
import 'settings_page.dart';
import 'profile_sheet.dart';
import 'widgets/avatar_circle.dart';
import 'widgets/surface_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.controller});
  final CallController? controller;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late final CallController _session;
  final _target = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = widget.controller ?? CallController();
    _session.onFeedback = (message, isError) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.t(message)),
            backgroundColor: isError
                ? Theme.of(context).colorScheme.error
                : null,
            behavior: SnackBarBehavior.floating,
          ),
        );
    };
    if (widget.controller == null) _session.initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _session.resume();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.onFeedback = null;
    if (widget.controller == null) _session.dispose();
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _session,
    builder: (context, _) {
      final l = AppLocalizations.of(context)!;
      final theme = Theme.of(context);
      final dark = theme.brightness == Brightness.dark;
      return PopScope(
        canPop: !_session.inCall,
        child: Scaffold(
          extendBodyBehindAppBar: true,
          appBar: _session.inCall
              ? null
              : AppBar(
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  title: const Text(
                    'P2P',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  actions: [
                    IconButton(
                      tooltip: dark ? l.tooltipLightTheme : l.tooltipDarkTheme,
                      icon: Icon(
                        dark
                            ? Icons.light_mode_outlined
                            : Icons.dark_mode_outlined,
                      ),
                      onPressed: () async {
                        isDarkModeNotifier.value = !dark;
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('is_dark_mode', !dark);
                      },
                    ),
                    IconButton(
                      tooltip: l.tooltipSettings,
                      icon: const Icon(Icons.tune_rounded),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SettingsPage(session: _session),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
          body: _session.inCall
              ? CallView(session: _session)
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_session.backgroundPath != null) ...[
                      Image.file(
                        File(_session.backgroundPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, error, stack) =>
                            const SizedBox.shrink(),
                      ),
                      ColoredBox(
                        color: theme.scaffoldBackgroundColor.withValues(
                          alpha: .85,
                        ),
                      ),
                    ] else ...[
                      // Dynamic ambient glowing mesh that distinctly reflects the active theme
                      Positioned(
                        top: -60,
                        right: -50,
                        child: IgnorePointer(
                          child: Container(
                            width: 360,
                            height: 360,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  theme.colorScheme.primary.withValues(
                                    alpha: dark ? 0.38 : 0.22,
                                  ),
                                  theme.colorScheme.primary.withValues(
                                    alpha: 0.0,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 220,
                        left: -80,
                        child: IgnorePointer(
                          child: Container(
                            width: 340,
                            height: 340,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  theme.colorScheme.secondary.withValues(
                                    alpha: dark ? 0.28 : 0.16,
                                  ),
                                  theme.colorScheme.secondary.withValues(
                                    alpha: 0.0,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 40,
                        right: -60,
                        child: IgnorePointer(
                          child: Container(
                            width: 320,
                            height: 320,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  theme.colorScheme.tertiary.withValues(
                                    alpha: dark ? 0.24 : 0.14,
                                  ),
                                  theme.colorScheme.tertiary.withValues(
                                    alpha: 0.0,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    SafeArea(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 840;
                          return SingleChildScrollView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: EdgeInsets.only(
                              left: wide ? 32 : 20,
                              right: wide ? 32 : 20,
                              top: kToolbarHeight + 8,
                              bottom: 24,
                            ),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 720,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _status(context),
                                    const SizedBox(height: 18),
                                    _identity(context),
                                    const SizedBox(height: 16),
                                    _dial(context),
                                    const SizedBox(height: 16),
                                    _peers(context),
                                    const SizedBox(height: 20),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
      );
    },
  );

  Widget _status(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final online = _session.signalingStatus == SignalingStatus.connected;
    final connecting =
        _session.signalingStatus == SignalingStatus.connecting ||
        _session.signalingStatus == SignalingStatus.reconnecting;
    final label = switch (_session.signalingStatus) {
      SignalingStatus.connected => l.statusOnline,
      SignalingStatus.connecting => l.statusConnecting,
      SignalingStatus.reconnecting => l.statusReconnecting,
      _ => l.statusOffline,
    };
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    final indicatorColor = online
        ? const Color(0xFF00E599)
        : connecting
            ? const Color(0xFFF59E0B)
            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6);

    return Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: dark
                    ? Color.alphaBlend(
                        primary.withValues(alpha: 0.06),
                        theme.colorScheme.surface.withValues(alpha: 0.62),
                      )
                    : theme.colorScheme.surface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: primary.withValues(alpha: dark ? 0.22 : 0.20),
                  width: 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: dark
                        ? Colors.black.withValues(alpha: 0.25)
                        : Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                  BoxShadow(
                    color: primary.withValues(alpha: dark ? 0.10 : 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: indicatorColor,
                      boxShadow: (online || connecting)
                          ? [
                              BoxShadow(
                                color: indicatorColor.withValues(alpha: 0.6),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!online)
          TextButton.icon(
            onPressed: _session.ready ? _session.reconnect : null,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(l.t('retry')),
          ),
      ],
    );
  }

  Widget _identity(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return SurfaceCard(
      child: Row(
        children: [
          IconButton(
            tooltip: l.avatarPickerTitle,
            onPressed: _session.ready
                ? () => showProfileSheet(context, _session)
                : null,
            icon: AvatarCircle(
              avatar: AvatarManager.getById(_session.avatarId, isMe: true),
              size: 50,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.myUserIdLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _session.ready ? _session.userId : l.loading,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: l.tooltipCopy,
            icon: const Icon(Icons.copy_rounded, size: 18),
            style: IconButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: !_session.ready
                ? null
                : () async {
                    await Clipboard.setData(
                      ClipboardData(text: _session.userId),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(l.toastCopied)));
                    }
                  },
          ),
        ],
      ),
    );
  }

  Widget _dial(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.phone_forwarded_rounded,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l.t('dialHeading'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _target,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: 64,
            textInputAction: TextInputAction.go,
            decoration: InputDecoration(
              prefixIcon: Icon(
                Icons.tag_rounded,
                size: 20,
                color: theme.colorScheme.primary.withValues(alpha: 0.7),
              ),
              labelText: l.t('peerId'),
              hintText: 'user_8888',
              counterText: '',
            ),
            onSubmitted: _session.canCall
                ? (value) {
                    FocusScope.of(context).unfocus();
                    _session.call(value);
                  }
                : null,
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder(
            valueListenable: _target,
            builder: (context, value, _) => SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _session.canCall && value.text.trim().isNotEmpty
                    ? () {
                        FocusScope.of(context).unfocus();
                        _session.call(value.text);
                      }
                    : null,
                icon: const Icon(Icons.call_rounded, size: 20),
                label: Text(l.directCall),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _peers(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.devices_rounded,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l.onlineDevices,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Text(
                  '${_session.peers.length}',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: l.t('refresh'),
                onPressed: _session.signaling.isConnected
                    ? _session.signaling.refreshUsers
                    : null,
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
            ],
          ),
          if (_session.peers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.devices_other_rounded,
                      size: 38,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l.noPeers,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l.noPeersHint,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            const SizedBox(height: 14),
            ..._session.peers.map(
              (peer) => Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: dark
                      ? theme.colorScheme.surfaceContainer.withValues(alpha: 0.45)
                      : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: dark
                        ? Colors.white.withValues(alpha: 0.06)
                        : theme.colorScheme.primary.withValues(alpha: 0.08),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    AvatarCircle(
                      avatar: remoteAvatar(
                        peer.avatar,
                        peer.avatarImage,
                        peer.userId,
                      ),
                      size: 42,
                      showOnlineDot: true,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        peer.userId,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: '${l.directCall} ${peer.userId}',
                      style: IconButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _session.canCall
                          ? () => _session.call(peer.userId)
                          : null,
                      icon: const Icon(Icons.call_outlined, size: 20),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
