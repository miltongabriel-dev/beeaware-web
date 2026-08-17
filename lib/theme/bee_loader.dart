import 'package:flutter/material.dart';

import 'beeaware_theme.dart';

/// Small branded spinner — a plain [CircularProgressIndicator] with an
/// explicit brand color, used inside buttons and inline loading spots
/// instead of the unstyled default.
class BeeLoader extends StatelessWidget {
  final double size;
  final Color? color;

  const BeeLoader({super.key, this.size = 18, this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: size <= 24 ? 2.2 : 3,
        valueColor:
            AlwaysStoppedAnimation<Color>(color ?? BeeAwareTheme.primary),
      ),
    );
  }
}

/// Self-contained loading card — spinner + message inside a rounded
/// surface, for full-screen/overlay loading states so they read as a
/// designed moment rather than a bare spinner floating on the screen.
class BeeLoadingCard extends StatelessWidget {
  final String message;

  const BeeLoadingCard({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: BeeAwareTheme.border),
          boxShadow: BeeAwareTheme.cardShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BeeLoader(size: 28),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: BeeAwareTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
