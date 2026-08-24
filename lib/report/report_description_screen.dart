import 'package:flutter/material.dart';

import 'report_draft.dart';
import 'report_location_screen.dart';
import 'report_step_scaffold.dart';
import '../l10n/app_localizations.dart';
import '../theme/beeaware_theme.dart';

class ReportDescriptionScreen extends StatefulWidget {
  final ReportDraft draft;

  const ReportDescriptionScreen({super.key, required this.draft});

  @override
  State<ReportDescriptionScreen> createState() =>
      _ReportDescriptionScreenState();
}

class _ReportDescriptionScreenState extends State<ReportDescriptionScreen> {
  late final TextEditingController _controller;
  bool _canContinue = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.draft.description ?? '');
    _canContinue = _controller.text.trim().isNotEmpty;

    _controller.addListener(() {
      setState(() {
        _canContinue = _controller.text.trim().isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _continue() {
    widget.draft.description = _controller.text.trim();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportLocationScreen(draft: widget.draft),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    return ReportStepScaffold(
      step: 4,
      title: loc.describeWhatHappenedTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.addShortDescription,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            loc.descriptionHelperText,
            style: theme.textTheme.bodySmall,
          ),

          const SizedBox(height: 20),

          // ===== Text field =====
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: BeeAwareTheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                boxShadow: BeeAwareTheme.cardShadow,
              ),
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: loc.descriptionHint,
                  border: InputBorder.none,
                ),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== Continue button =====
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _canContinue ? _continue : null,
              style: ElevatedButton.styleFrom(
                foregroundColor: BeeAwareTheme.textPrimary,
                disabledForegroundColor:
                    BeeAwareTheme.textPrimary.withValues(alpha: 0.6),
                backgroundColor: theme.colorScheme.primary,
                disabledBackgroundColor:
                    theme.colorScheme.primary.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
              ),
              child: Text(
                loc.continueButton,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
