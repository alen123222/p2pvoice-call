import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 高质感毛玻璃卡片 (Frosted Glassmorphism Card)
/// 提供平滑的高斯模糊、渐变晶透边缘微光与浮雕质感
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blurSigma;
  final Color? backgroundColor;
  final Color? borderColor;
  final VoidCallback? onTap;
  final bool isDark;
  final Gradient? borderGradient;
  final List<BoxShadow>? customShadow;

  const GlassCard({
    super.key,
    required this.child,
    required this.isDark,
    this.padding = const EdgeInsets.all(18),
    this.margin,
    this.borderRadius = 20,
    this.blurSigma = 16.0,
    this.backgroundColor,
    this.borderColor,
    this.onTap,
    this.borderGradient,
    this.customShadow,
  });

  @override
  Widget build(BuildContext context) {
    // 根据明暗主题精调透明度与背景色
    final defaultBg = isDark
        ? const Color(0xFF141C30).withValues(alpha: 0.55)
        : Colors.white.withValues(alpha: 0.65);

    final defaultBorderColor = isDark
        ? AppTheme.riverBlue.withValues(alpha: 0.22)
        : AppTheme.sakuraPink.withValues(alpha: 0.40);

    final shadows = customShadow ??
        [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.35)
                : AppTheme.riverBlue.withValues(alpha: 0.12),
            blurRadius: 16,
            spreadRadius: -2,
            offset: const Offset(0, 6),
          ),
          if (!isDark)
            BoxShadow(
              color: AppTheme.sakuraPink.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
        ];

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? defaultBg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: borderGradient == null
            ? Border.all(
                color: borderColor ?? defaultBorderColor,
                width: 1.2,
              )
            : null,
      ),
      child: child,
    );

    // 如果指定了渐变边框
    if (borderGradient != null) {
      content = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          gradient: borderGradient,
        ),
        padding: const EdgeInsets.all(1.2), // 边框粗细
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: backgroundColor ?? defaultBg,
            borderRadius: BorderRadius.circular(borderRadius - 1.2),
          ),
          child: child,
        ),
      );
    }

    Widget card = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: content,
      ),
    );

    if (onTap != null) {
      card = Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: onTap,
          child: card,
        ),
      );
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: shadows,
      ),
      child: card,
    );
  }
}
