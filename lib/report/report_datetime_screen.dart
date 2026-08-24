import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'report_draft.dart';
import 'report_step_scaffold.dart';
import 'report_summary_screen.dart';
import '../config/app_config.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_card.dart';
import '../theme/beeaware_theme.dart';
import '../theme/fade_in.dart';

class ReportDateTimeScreen extends StatefulWidget {
  final ReportDraft draft;

  const ReportDateTimeScreen({super.key, required this.draft});

  @override
  State<ReportDateTimeScreen> createState() => _ReportDateTimeScreenState();
}

class _ReportDateTimeScreenState extends State<ReportDateTimeScreen> {
  late DateTime selectedDateTime;

  @override
  void initState() {
    super.initState();
    selectedDateTime = widget.draft.dateTime ?? DateTime.now();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: selectedDateTime,
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now(),
    );

    if (date != null) {
      setState(() {
        selectedDateTime = DateTime(
          date.year,
          date.month,
          date.day,
          selectedDateTime.hour,
          selectedDateTime.minute,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(selectedDateTime),
    );

    if (time != null) {
      setState(() {
        selectedDateTime = DateTime(
          selectedDateTime.year,
          selectedDateTime.month,
          selectedDateTime.day,
          time.hour,
          time.minute,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return ReportStepScaffold(
      step: 5,
      title: loc.whenDidItHappenTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(loc.adjustDateTimeHint),
          const SizedBox(height: 16),
          FadeInUp(
            child: _DateTimeCard(
              icon: PhosphorIconsRegular.calendar,
              label: loc.dateLabel,
              value:
                  '${selectedDateTime.day}/${selectedDateTime.month}/${selectedDateTime.year}',
              onTap: _pickDate,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FadeInUp(
            delay: const Duration(milliseconds: 80),
            child: _DateTimeCard(
              icon: PhosphorIconsRegular.clock,
              label: loc.timeLabel,
              value:
                  '${selectedDateTime.hour.toString().padLeft(2, '0')}:${selectedDateTime.minute.toString().padLeft(2, '0')}',
              onTap: _pickTime,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            loc.reportVisibilityNotice(
                AppConfig.incidentVisibilityDelay.inMinutes),
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                widget.draft.dateTime = selectedDateTime;

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReportSummaryScreen(draft: widget.draft),
                  ),
                );
              },
              child: Text(loc.confirmReport),
            ),
          ),
        ],
      ),
    );
  }
}

// ================= CARD =================

class _DateTimeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DateTimeCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: BeeAwareTheme.primary.withValues(alpha: 0.08),
            ),
            child: Icon(icon, size: 18, color: BeeAwareTheme.primary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: BeeAwareTheme.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Icon(PhosphorIconsRegular.caretRight,
              size: 20, color: BeeAwareTheme.textAux),
        ],
      ),
    );
  }
}
