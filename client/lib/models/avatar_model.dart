import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AvatarItem {
  final String id;
  final String name;
  final String emoji;
  final String? imagePath;
  final List<Color> gradient;

  const AvatarItem({
    required this.id,
    required this.name,
    required this.emoji,
    this.imagePath,
    required this.gradient,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'imagePath': imagePath,
        'gradient': gradient.map((c) => c.toARGB32()).toList(),
      };

  factory AvatarItem.fromJson(Map<String, dynamic> json) {
    final gradList = (json['gradient'] as List<dynamic>?)
            ?.map((e) => Color(e as int))
            .toList() ??
        const [Color(0xFF0284C7), Color(0xFF38BDF8)];
    return AvatarItem(
      id: json['id'] as String,
      name: json['name'] as String,
      emoji: (json['emoji'] as String?) ?? '🖼️',
      imagePath: json['imagePath'] as String?,
      gradient: gradList,
    );
  }
}

class AvatarManager {
  static const List<AvatarItem> defaultPresets = [
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

  static List<AvatarItem> _currentList = List.from(defaultPresets);

  /// 保持向后兼容，所有获取头像列表处均返回当前列表
  static List<AvatarItem> get presets => List.unmodifiable(_currentList);

  /// 从本地持久化加载头像列表
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('custom_avatars_v1');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        final loaded = decoded
            .map((e) => AvatarItem.fromJson(e as Map<String, dynamic>))
            .toList();
        if (loaded.isNotEmpty) {
          _currentList = loaded;
        }
      }
    } catch (_) {
      // 容错保留默认预设
    }
  }

  /// 保存当前列表到本地
  static Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_currentList.map((e) => e.toJson()).toList());
      await prefs.setString('custom_avatars_v1', encoded);
    } catch (_) {}
  }

  /// 添加自定义头像（图片或自定义属性）
  static Future<void> addAvatar(AvatarItem item) async {
    _currentList.insert(0, item); // 新增放最前
    await save();
  }

  /// 删除指定 ID 头像
  static Future<bool> deleteAvatar(String id) async {
    if (_currentList.length <= 1) {
      return false; // 保证至少保留一个头像
    }
    _currentList.removeWhere((a) => a.id == id);
    await save();
    return true;
  }

  /// 重置为初始预设
  static Future<void> resetToDefaults() async {
    _currentList = List.from(defaultPresets);
    await save();
  }

  static AvatarItem getById(String? id) {
    if (_currentList.isEmpty) return defaultPresets[0];
    if (id == null || id.isEmpty) return _currentList[0];
    return _currentList.firstWhere(
      (a) => a.id == id,
      orElse: () => _currentList[0],
    );
  }
}
