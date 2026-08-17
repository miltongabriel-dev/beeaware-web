import 'package:flutter/material.dart';

import '../theme/beeaware_theme.dart';

/// Row of segments showing progress through the report flow
/// (Category → Subcategory → Severity → Description → Date/time →
/// Location). The review/summary screen isn't part of this — it's the
/// final confirmation, not another choice.
class ReportStepIndicator extends StatelessWidget {
  static const int totalSteps = 6;

  final int step; // 1-based

  const ReportStepIndicator({super.key, required this.step});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
      child: Row(
        children: List.generate(totalSteps, (i) {
          final active = i < step;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i == totalSteps - 1 ? 0 : 6),
              height: 4,
              decoration: BoxDecoration(
                color: active ? BeeAwareTheme.primary : BeeAwareTheme.border,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
          );
        }),
      ),
    );
  }
}
