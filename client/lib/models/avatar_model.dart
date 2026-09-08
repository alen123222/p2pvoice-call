import 'package:flutter/material.dart';

class AvatarItem {
  final String id;
  final String name;
  final String emoji;
  final List<Color> gradient;

  const AvatarItem({
    required this.id,
    required this.name,
    required this.emoji,
    required this.gradient,
  });
}

class AvatarManager {
  static const List<AvatarItem> presets = [
    AvatarItem(
      id: 'pilot',
      name: '领航员',
      emoji: '🚀',
      gradient: [Color(0xFF0284C7), Color(0xFF38BDF8)],
    ),
    AvatarItem(
      id: 'cyber_fox',
      name: '极客狐',
      emoji: '🦊',
      gradient: [Color(0xFFEA580C), Color(0xFFF97316)],
    ),
    AvatarItem(
      id: 'cyber_cat',
      name: '赛博猫',
      emoji: '🐱',
      gradient: [Color(0xFF8B5CF6), Color(0xFFA78BFA)],
    ),
    AvatarItem(
      id: 'tiger',
      name: '荣耀虎',
      emoji: '🐯',
      gradient: [Color(0xFFD97706), Color(0xFFFBBF24)],
    ),
    AvatarItem(
      id: 'panda',
      name: '功夫熊',
      emoji: '🐼',
      gradient: [Color(0xFF059669), Color(0xFF34D399)],
    ),
    AvatarItem(
      id: 'lion',
      name: '霸气狮',
      emoji: '🦁',
      gradient: [Color(0xFFB45309), Color(0xFFF59E0B)],
    ),
    AvatarItem(
      id: 'dolphin',
      name: '星海豚',
      emoji: '🐬',
      gradient: [Color(0xFF0284C7), Color(0xFF06B6D4)],
    ),
    AvatarItem(
      id: 'eagle',
      name: '苍穹鹰',
      emoji: '🦅',
      gradient: [Color(0xFF4338CA), Color(0xFF6366F1)],
    ),
    AvatarItem(
      id: 'unicorn',
      name: '独角兽',
      emoji: '🦄',
      gradient: [Color(0xFFDB2777), Color(0xFFF472B6)],
    ),
    AvatarItem(
      id: 'robot',
      name: '极智机',
      emoji: '🤖',
      gradient: [Color(0xFF475569), Color(0xFF94A3B8)],
    ),
    AvatarItem(
      id: 'lightning',
      name: '光子速',
      emoji: '⚡',
      gradient: [Color(0xFFCA8A04), Color(0xFFFACC15)],
    ),
    AvatarItem(
      id: 'shield',
      name: '圣盾甲',
      emoji: '🛡️',
      gradient: [Color(0xFF0D9488), Color(0xFF2DD4BF)],
    ),
  ];

  static AvatarItem getById(String? id) {
    if (id == null || id.isEmpty) return presets[0];
    return presets.firstWhere(
      (a) => a.id == id,
      orElse: () => presets[0],
    );
  }
}
