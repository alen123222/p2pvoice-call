import 'package:flutter/material.dart';

import '../controllers/call_controller.dart';
import '../l10n/app_localizations.dart';
import '../models/avatar_model.dart';
import '../models/call_state.dart';
import 'widgets/avatar_circle.dart';

AvatarItem remoteAvatar(String id, String? image, String peerId) {
  final base = AvatarManager.getById(id, peerSeed: peerId);
  return AvatarItem(
    id: base.id,
    name: base.name,
    emoji: base.emoji,
    gradient: base.gradient,
    imageBase64: image,
  );
}

class CallView extends StatelessWidget {
  const CallView({super.key, required this.session});
  final CallController session;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final incoming = session.callStatus == CallStatus.incoming;
    final connected = session.callStatus == CallStatus.connected;
    final rtc = session.rtc;
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    incoming
                        ? l.incomingCall
                        : connected
                        ? l.t('callConnected')
                        : l.t('callConnecting'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.colorScheme.primary.withValues(
                              alpha: .08,
                            ),
                          ),
                          child: AvatarCircle(
                            avatar: remoteAvatar(
                              rtc.remotePeerAvatar,
                              rtc.remotePeerAvatarImage,
                              rtc.currentPeerId ?? '',
                            ),
                            size: 96,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          rtc.currentPeerId ?? l.unknownUser,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          connected
                              ? session.duration
                              : incoming
                              ? l.t('incomingHint')
                              : l.negotiating,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (connected) ...[
                          const SizedBox(height: 20),
                          Text(
                            l.t('encrypted'),
                            style: theme.textTheme.labelLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l.t(rtc.connectionType),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 28,
                    runSpacing: 20,
                    children: [
                      if (!incoming)
                        _control(
                          context,
                          rtc.isMuted
                              ? Icons.mic_off_rounded
                              : Icons.mic_none_rounded,
                          rtc.isMuted ? l.mutedLabel : l.micLabel,
                          connected
                              ? () async {
                                  await rtc.toggleMute();
                                  session.notifyControlsChanged();
                                }
                              : null,
                          selected: rtc.isMuted,
                        ),
                      _control(
                        context,
                        Icons.call_end_rounded,
                        l.hangup,
                        incoming ? rtc.rejectCall : rtc.hangup,
                        danger: true,
                      ),
                      if (incoming)
                        _control(
                          context,
                          Icons.call_rounded,
                          l.answer,
                          rtc.acceptCall,
                          selected: true,
                        )
                      else
                        _control(
                          context,
                          rtc.isSpeakerphoneOn
                              ? Icons.volume_up_rounded
                              : Icons.hearing_rounded,
                          rtc.isSpeakerphoneOn
                              ? l.speakerLabel
                              : l.earpieceLabel,
                          connected
                              ? () async {
                                  await rtc.toggleSpeakerphone();
                                  session.notifyControlsChanged();
                                }
                              : null,
                          selected: rtc.isSpeakerphoneOn,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _control(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback? action, {
    bool selected = false,
    bool danger = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          tooltip: label,
          onPressed: action,
          style: IconButton.styleFrom(
            minimumSize: const Size(68, 68),
            backgroundColor: danger
                ? colors.error
                : selected
                ? colors.primary
                : colors.surfaceContainerHigh,
            foregroundColor: danger
                ? colors.onError
                : selected
                ? colors.onPrimary
                : colors.onSurface,
          ),
          icon: Icon(icon, size: 28),
        ),
        const SizedBox(height: 10),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}
