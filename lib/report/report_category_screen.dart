import 'package:flutter/material.dart';

import 'report_subcategory_screen.dart';
import 'report_draft.dart';
import 'report_icons.dart';
import 'report_labels.dart';
import 'report_step_scaffold.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_card.dart';
import '../theme/beeaware_theme.dart';
import '../theme/fade_in.dart';

class ReportCategoryScreen extends StatelessWidget {
  const ReportCategoryScreen({super.key});

  static final _categories = [
    'Harassment',
    'Suspicious activity',
    'Theft',
    'Violence',
    'Drugs',
    'Other',
  ].map((label) => _CategoryItem(label, ReportIcons.category(label))).toList();

  @override
  Widget build(BuildContext context) {
    return ReportStepScaffold(
      step: 1,
      title: AppLocalizations.of(context)!.whatHappenedTitle,
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 140,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.95,
        ),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final item = _categories[index];
          return FadeInUp(
            delay: Duration(milliseconds: 40 * index),
            child: _CategoryCard(
              item: item,
              onTap: () {
                final draft = ReportDraft()..category = item.label;

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReportSubcategoryScreen(draft: draft),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ================= CARD =================

class _CategoryCard extends StatelessWidget {
  final _CategoryItem item;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.item,
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
              item.icon,
              size: 22,
              color: BeeAwareTheme.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              ReportLabels.category(context, item.label),
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

// ================= MODEL =================

class _CategoryItem {
  final String label;
  final IconData icon;

  const _CategoryItem(this.label, this.icon);
}
