import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/avatar_model.dart';

/// A reusable circular avatar used across the identity card, peer list,
/// incoming-call overlay and active-call overlay. Supports both emoji and custom photo avatars.
class AvatarCircle extends StatelessWidget {
  const AvatarCircle({
    super.key,
    required this.avatar,
    this.size = 48,
    this.emojiSize,
    this.showOnlineDot = false,
    this.glow = false,
    this.border,
  });

  final AvatarItem avatar;
  final double size;
  final double? emojiSize;
  final bool showOnlineDot;
  final bool glow;
  final Border? border;

  @override
  Widget build(BuildContext context) {
    final hasLocalImage = avatar.imagePath != null &&
        avatar.imagePath!.isNotEmpty &&
        File(avatar.imagePath!).existsSync();
    final hasRemoteImage =
        avatar.imageBase64 != null && avatar.imageBase64!.isNotEmpty;

    Widget avatarContent;
    if (hasLocalImage) {
      avatarContent = Image.file(
        File(avatar.imagePath!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            Text(avatar.emoji, style: TextStyle(fontSize: emojiSize ?? size * 0.52)),
      );
    } else if (hasRemoteImage) {
      try {
        final bytes = base64Decode(avatar.imageBase64!);
        avatarContent = Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              Text(avatar.emoji, style: TextStyle(fontSize: emojiSize ?? size * 0.52)),
        );
      } catch (_) {
        avatarContent = Text(avatar.emoji, style: TextStyle(fontSize: emojiSize ?? size * 0.52));
      }
    } else {
      avatarContent = Text(avatar.emoji, style: TextStyle(fontSize: emojiSize ?? size * 0.52));
    }

    final circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: avatar.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        border: border,
        boxShadow: glow
            ? [
                BoxShadow(
                  color: avatar.gradient.first.withValues(alpha: 0.5),
                  blurRadius: size * 0.18,
                  spreadRadius: size * 0.03,
                ),
              ]
            : [
                BoxShadow(
                  color: avatar.gradient.first.withValues(alpha: 0.35),
                  blurRadius: size * 0.08,
                  offset: Offset(0, size * 0.04),
                ),
              ],
      ),
      alignment: Alignment.center,
      child: ClipOval(child: avatarContent),
    );

    if (!showOnlineDot) return circle;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        circle,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: size * 0.24,
            height: size * 0.24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF10B981),
              border: Border.all(color: const Color(0xFF1E293B), width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
