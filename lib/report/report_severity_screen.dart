import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../map/map_incident.dart'; // ✅ AQUI está o IncidentSeverity
import '../theme/beeaware_theme.dart';
import 'report_description_screen.dart';
import 'report_draft.dart';

class ReportSeverityScreen extends StatelessWidget {
  final ReportDraft draft;

  const ReportSeverityScreen({
    super.key,
    required this.draft,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _SeverityItem(
        label: 'Low',
        description: 'Uncomfortable but no immediate danger',
        color: BeeAwareTheme.severityLow,
        value: IncidentSeverity.low,
      ),
      _SeverityItem(
        label: 'Medium',
        description: 'Concerning and potentially unsafe',
        color: BeeAwareTheme.severityMedium,
        value: IncidentSeverity.medium,
      ),
      _SeverityItem(
        label: 'High',
        description: 'Serious risk or immediate danger',
        color: BeeAwareTheme.severityHigh,
        value: IncidentSeverity.high,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('How serious was it?'),
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
            child: Column(
              children: items.map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
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
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ================= MODEL =================

class _SeverityItem {
  final String label;
  final String description;
  final Color color;
  final IncidentSeverity value;

  const _SeverityItem({
    required this.label,
    required this.description,
    required this.color,
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
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Ink(
        height: 96,
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
        child: Row(
          children: [
            // COLOR BAR
            Container(
              width: 10,
              decoration: BoxDecoration(
                color: item.color,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(20),
                ),
              ),
            ),
            const SizedBox(width: 16),

            // TEXT
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
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
          ],
        ),
      ),
    );
  }
}
