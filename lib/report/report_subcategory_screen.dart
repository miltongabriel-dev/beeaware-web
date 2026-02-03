import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'report_severity_screen.dart';
import 'report_draft.dart';

class ReportSubcategoryScreen extends StatelessWidget {
  final ReportDraft draft;

  const ReportSubcategoryScreen({
    super.key,
    required this.draft,
  });

  @override
  Widget build(BuildContext context) {
    final subcategories = _getSubcategories(draft.category!);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tell us more'),
      ),
      body: Stack(
        children: [
          // ================= WATERMARK =================
          Center(
            child: Opacity(
              opacity: 0.05,
              child: SvgPicture.asset(
                'assets/logo/beeaware_watermark.svg',
                width: MediaQuery.of(context).size.width * 0.9,
              ),
            ),
          ),

          // ================= CONTENT =================
          Padding(
            padding: const EdgeInsets.all(16),
            child: GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.95,
              children: subcategories.map((item) {
                return _SubcategoryCard(
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
                );
              }).toList(),
            ),
          ),
        ],
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

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
