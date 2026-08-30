import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '/l10n/app_localizations.dart';
import '/map/map_incident.dart';
import '/report/report_icons.dart';
import '/report/report_labels.dart';
import '/theme/beeaware_theme.dart';
import '/utils/relative_time.dart';

class IncidentBottomSheet extends StatelessWidget {
  final MapIncident incident;

  const IncidentBottomSheet({
    super.key,
    required this.incident,
  });

  Color _severityColor() => SeverityColors.of(incident.severity);

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final categoryLabel = incident.isOfficial
        ? ReportLabels.officialCategory(context, incident.officialEventCategory)
        : ReportLabels.category(context, incident.category);
    // Official events prefer whatever `description` the source adapter
    // already built (e.g. UkPoliceApi bakes in street/outcome/month —
    // real specifics of what happened, not just a category). BrazilSecurityApi
    // deliberately leaves `description` empty and only supplies
    // officialCity/officialState, so for that source the sentence is
    // built here instead — same reasoning as categoryLabel above: the
    // "in"/"em" connector is locale-dependent. Checking both city AND
    // state are non-empty (not just non-null — BrazilSecurityApi defaults
    // missing fields to '', not null) avoids a broken "X in , ." sentence.
    final description = incident.isOfficial
        ? (incident.description.trim().isNotEmpty
            ? incident.description
            : (incident.officialCity != null &&
                    incident.officialState != null &&
                    incident.officialCity!.isNotEmpty &&
                    incident.officialState!.isNotEmpty
                ? loc.officialEventDescription(
                    incident.subcategory,
                    incident.officialCity!,
                    incident.officialState!,
                  )
                : ''))
        : incident.description;
    final hasExternalDescription = description.trim().isNotEmpty;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: const BoxDecoration(
          color: BeeAwareTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
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
                  color: BeeAwareTheme.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),

            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: BeeAwareTheme.primary.withValues(alpha: 0.08),
                  ),
                  child: incident.isApproximate
                      ? SvgPicture.asset(
                          // Deliberately not verified.svg: that checkmark
                          // reads as "confirmed record", which an
                          // approximate, news-derived pin isn't.
                          'assets/icons/source.svg',
                          width: 18,
                          height: 18,
                          colorFilter: const ColorFilter.mode(
                            BeeAwareTheme.primary,
                            BlendMode.srcIn,
                          ),
                        )
                      : incident.isOfficial
                          ? SvgPicture.asset(
                              'assets/icons/verified.svg',
                              width: 18,
                              height: 18,
                              colorFilter: const ColorFilter.mode(
                                BeeAwareTheme.primary,
                                BlendMode.srcIn,
                              ),
                            )
                          : Icon(
                              ReportIcons.category(incident.category),
                              size: 18,
                              color: BeeAwareTheme.primary,
                            ),
                ),
                const SizedBox(width: 10),

                // Title / category
                Expanded(
                  child: Text(
                    categoryLabel,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Meta info: severity chip + relative time
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color: _severityColor().withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    SeverityColors.label(context, incident.severity),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _severityColor(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  relativeTime(context, incident.dateTime),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: BeeAwareTheme.textSecondary,
                      ),
                ),
              ],
            ),

            // ---------------------------
            // DESCRIPTION (conditional)
            // ---------------------------
            if (hasExternalDescription) ...[
              const SizedBox(height: 12),
              Text(
                description,
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
                loc.sourceLabel(incident.source!),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: BeeAwareTheme.textSecondary,
                    ),
              ),
            ],

            // ---------------------------
            // APPROXIMATE LOCATION disclaimer + article link
            // (news-derived pins only — see MapIncident.isApproximate)
            // ---------------------------
            if (incident.isApproximate) ...[
              const SizedBox(height: 6),
              Text(
                loc.newsApproxLocation,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: BeeAwareTheme.textAux,
                      fontStyle: FontStyle.italic,
                    ),
              ),
              if (incident.articleUrl != null &&
                  incident.articleUrl!.isNotEmpty) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => launchUrl(
                    Uri.parse(incident.articleUrl!),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(
                    loc.readFullArticle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: BeeAwareTheme.primary,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                  ),
                ),
              ],
            ],

            const SizedBox(height: 16),

            // Footer disclaimer (discreto)
            Text(
              loc.incidentInfoDisclaimer,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: BeeAwareTheme.textAux,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
