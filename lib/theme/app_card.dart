import 'package:flutter/material.dart';

import 'beeaware_theme.dart';

/// Shared tappable card surface — the standard rounded/shadowed container
/// used across the report flow, auth, and purchase screens, so every
/// "card" in the app shares the same radius, shadow, and background.
class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? backgroundColor;
  final Border? border;

  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.radius = AppRadius.lg,
    this.backgroundColor,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);

    return InkWell(
      borderRadius: borderRadius,
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: backgroundColor ?? BeeAwareTheme.surface,
          borderRadius: borderRadius,
          border: border ?? Border.all(color: BeeAwareTheme.border),
          boxShadow: BeeAwareTheme.cardShadow,
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
