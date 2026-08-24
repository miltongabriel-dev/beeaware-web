import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'report_step_indicator.dart';
import '../theme/beeaware_theme.dart';

/// Shared scaffold for every "choice" step of the report flow (category,
/// subcategory, severity, description, date/time) — AppBar, step indicator,
/// watermark, and a centered/constrained content area. Extracted because
/// this exact structure was independently copy-pasted into each screen and
/// had already started to drift (description screen's watermark opacity and
/// content padding didn't match the others). Opacity and padding are fixed
/// here on purpose, not parameters — the point is that no screen can pick
/// its own value anymore.
///
/// Not used by the location screen (full-bleed map, a watermark doesn't fit)
/// or the summary screen (deliberately outside the step flow — see
/// ReportStepIndicator's own doc comment).
class ReportStepScaffold extends StatelessWidget {
  final int step;
  final String title;
  final Widget child;

  const ReportStepScaffold({
    super.key,
    required this.step,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          ReportStepIndicator(step: step),
          Expanded(
            child: Stack(
              children: [
                Center(
                  child: Opacity(
                    opacity: 0.05,
                    child: SvgPicture.asset(
                      'assets/logo/beeaware_symbol.svg',
                      width: MediaQuery.of(context).size.width * 0.9,
                    ),
                  ),
                ),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: child,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
