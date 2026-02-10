import 'package:flutter/material.dart';
import '/map/map_incident.dart';

class IncidentBottomSheet extends StatelessWidget {
  final MapIncident incident;

  const IncidentBottomSheet({
    super.key,
    required this.incident,
  });

  Color _severityColor() {
    switch (incident.severity) {
      case IncidentSeverity.high:
        return const Color(0xFFF44336);
      case IncidentSeverity.medium:
        return const Color(0xFFFF9800);
      case IncidentSeverity.low:
      default:
        return const Color(0xFFFFC107);
    }
  }

  String _severityLabel() {
    switch (incident.severity) {
      case IncidentSeverity.high:
        return 'High severity';
      case IncidentSeverity.medium:
        return 'Medium severity';
      case IncidentSeverity.low:
      default:
        return 'Low severity';
    }
  }

  String _relativeTime(BuildContext context) {
    final now = DateTime.now();
    final diff = now.difference(incident.dateTime);

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} hours ago';
    } else {
      return '${diff.inDays} days ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasExternalDescription =
        incident.isOfficial && incident.description.trim().isNotEmpty; // NEW

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Severity dot
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _severityColor(),
                  ),
                ),
                const SizedBox(width: 10),

                // Title / category
                Expanded(
                  child: Text(
                    incident.category,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            // Meta info
            Text(
              '${_severityLabel()} • ${_relativeTime(context)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),

            // ---------------------------
            // DESCRIPTION (conditional)
            // ---------------------------
            if (hasExternalDescription) ...[
              const SizedBox(height: 12),
              Text(
                incident.description,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],

            // ---------------------------
            // SOURCE (external only)
            // ---------------------------
            if (incident.isOfficial &&
                incident.source != null &&
                incident.source!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Source: ${incident.source}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
            ],

            const SizedBox(height: 16),

            // Footer disclaimer (discreto)
            Text(
              'Information from publicly available sources and community reports. For awareness only.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
