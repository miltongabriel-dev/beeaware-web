import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../map/map_incident.dart'; // ✅ AQUI está o IncidentSeverity
import '../l10n/app_localizations.dart';
import '../theme/beeaware_theme.dart';
import '../theme/fade_in.dart';
import 'report_description_screen.dart';
import 'report_draft.dart';
import 'report_step_scaffold.dart';

class ReportSeverityScreen extends StatelessWidget {
  final ReportDraft draft;

  const ReportSeverityScreen({
    super.key,
    required this.draft,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final items = [
      _SeverityItem(
        description: loc.severityLowDesc,
        color: SeverityColors.low,
        icon: PhosphorIconsRegular.info,
        value: IncidentSeverity.low,
      ),
      _SeverityItem(
        description: loc.severityMediumDesc,
        color: SeverityColors.medium,
        icon: PhosphorIconsRegular.warningCircle,
        value: IncidentSeverity.medium,
      ),
      _SeverityItem(
        description: loc.severityHighDesc,
        color: SeverityColors.high,
        icon: PhosphorIconsRegular.warningOctagon,
        value: IncidentSeverity.high,
      ),
    ];

    return ReportStepScaffold(
      step: 3,
      title: loc.howSeriousWasItTitle,
      child: Column(
        children: items.asMap().entries.map((entry) {
          final item = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: FadeInUp(
              delay: Duration(milliseconds: 80 * entry.key),
              child: _SeverityCard(
                item: item,
                onTap: () {
                  // ✅ Grava severidade no draft
                  draft.severity = item.value.name;

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReportDescriptionScreen(draft: draft),
                    ),
                  );
                },
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ================= MODEL =================

class _SeverityItem {
  final String description;
  final Color color;
  final IconData icon;
  final IncidentSeverity value;

  const _SeverityItem({
    required this.description,
    required this.color,
    required this.icon,
    required this.value,
  });
}

// ================= CARD =================

class _SeverityCard extends StatelessWidget {
  final _SeverityItem item;
  final VoidCallback onTap;

  const _SeverityCard({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: onTap,
      child: Ink(
        height: 96,
        decoration: BoxDecoration(
          color: BeeAwareTheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: BeeAwareTheme.border),
          boxShadow: BeeAwareTheme.cardShadow,
        ),
        child: Row(
          children: [
            // COLOR BAR
            Container(
              width: 10,
              decoration: BoxDecoration(
                color: item.color,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(AppRadius.lg),
                ),
              ),
            ),
            const SizedBox(width: 16),

            Icon(item.icon, color: item.color, size: 26),
            const SizedBox(width: 12),

            // TEXT
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    SeverityColors.label(context, item.value),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.description,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}
