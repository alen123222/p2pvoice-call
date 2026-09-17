import 'dart:ui';
import 'package:flutter/material.dart';

/// Translucent frosted glass card (glassmorphism) that dynamically echoes the active theme.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: isDark
                ? Color.alphaBlend(
                    primary.withValues(alpha: 0.04),
                    theme.colorScheme.surface.withValues(alpha: 0.65),
                  )
                : theme.colorScheme.surface.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? primary.withValues(alpha: 0.22)
                  : primary.withValues(alpha: 0.20),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.40)
                    : Colors.black.withValues(alpha: 0.04),
                blurRadius: 24,
                offset: const Offset(0, 8),
                spreadRadius: -2,
              ),
              BoxShadow(
                color: primary.withValues(alpha: isDark ? 0.12 : 0.08),
                blurRadius: 18,
                offset: const Offset(0, 4),
                spreadRadius: 0,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
