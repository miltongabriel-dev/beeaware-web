import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'report_subcategory_screen.dart';
import 'report_draft.dart';

class ReportCategoryScreen extends StatelessWidget {
  const ReportCategoryScreen({super.key});

  static const _categories = [
    _CategoryItem('Harassment', Icons.warning_amber_rounded),
    _CategoryItem('Suspicious activity', Icons.remove_red_eye_outlined),
    _CategoryItem('Theft', Icons.lock_outline),
    _CategoryItem('Violence', Icons.report_gmailerrorred),
    _CategoryItem('Drugs', Icons.medical_services_outlined),
    _CategoryItem('Other', Icons.more_horiz),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('What happened?'),
      ),
      body: Stack(
        children: [
          // ================= WATERMARK =================
          Center(
            child: Opacity(
              opacity: 0.05, // Apple-level
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
              children: _categories.map((item) {
                return _CategoryCard(
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
                );
              }).toList(),
            ),
          ),
        ],
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              item.icon,
              size: 28,
              color: const Color(0xFF2F3A4A),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                item.label,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
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
