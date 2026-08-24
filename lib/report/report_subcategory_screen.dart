import 'package:flutter/material.dart';

import 'report_severity_screen.dart';
import 'report_draft.dart';
import 'report_icons.dart';
import 'report_labels.dart';
import 'report_step_scaffold.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_card.dart';
import '../theme/beeaware_theme.dart';
import '../theme/fade_in.dart';

class ReportSubcategoryScreen extends StatelessWidget {
  final ReportDraft draft;

  const ReportSubcategoryScreen({
    super.key,
    required this.draft,
  });

  @override
  Widget build(BuildContext context) {
    final subcategories = _getSubcategories(draft.category!);

    return ReportStepScaffold(
      step: 2,
      title: AppLocalizations.of(context)!.tellUsMoreTitle,
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 140,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.95,
        ),
        itemCount: subcategories.length,
        itemBuilder: (context, index) {
          final item = subcategories[index];
          return FadeInUp(
            delay: Duration(milliseconds: 40 * index),
            child: _SubcategoryCard(
              label: item,
              onTap: () {
                draft.subcategory = item;

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReportSeverityScreen(draft: draft),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  // ================= DATA =================

  List<String> _getSubcategories(String category) {
    switch (category) {
      case 'Harassment':
        return [
          'Verbal',
          'Physical',
          'Online',
          'Stalking',
          'Sexual',
          'Other',
        ];
      case 'Suspicious activity':
        return [
          'Loitering',
          'Following someone',
          'Looking into cars',
          'Checking doors',
          'Other',
        ];
      case 'Theft':
        return [
          'Pickpocketing',
          'Bike theft',
          'Car break-in',
          'Shoplifting',
          'Other',
        ];
      case 'Violence':
        return [
          'Fight',
          'Domestic',
          'Weapon involved',
          'Threats',
          'Other',
        ];
      case 'Drugs':
        return [
          'Use',
          'Dealing',
          'Suspicious exchange',
          'Needles found',
          'Other',
        ];
      default:
        return ['Other'];
    }
  }
}

// ================= CARD =================

class _SubcategoryCard extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SubcategoryCard({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: BeeAwareTheme.primary.withValues(alpha: 0.08),
            ),
            child: Icon(
              ReportIcons.subcategory(label),
              size: 22,
              color: BeeAwareTheme.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              ReportLabels.subcategory(context, label),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
