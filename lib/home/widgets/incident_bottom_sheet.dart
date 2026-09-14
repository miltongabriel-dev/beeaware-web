import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '/backend/incident_api.dart';
import '/l10n/app_localizations.dart';
import '/map/map_incident.dart';
import '/report/report_icons.dart';
import '/report/report_labels.dart';
import '/theme/beeaware_theme.dart';
import '/utils/relative_time.dart';

class IncidentBottomSheet extends StatefulWidget {
  final MapIncident incident;

  const IncidentBottomSheet({
    super.key,
    required this.incident,
  });

  @override
  State<IncidentBottomSheet> createState() => _IncidentBottomSheetState();
}

class _IncidentBottomSheetState extends State<IncidentBottomSheet> {
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  MapIncident get incident => widget.incident;
  bool _reporting = false;

  // A freshly-submitted report is shown optimistically with a local,
  // non-UUID placeholder id (see ReportSummaryScreen) until the map
  // re-syncs with Supabase's real row. Reporting isn't meaningful yet
  // for that placeholder (it isn't persisted under that id, and it's
  // the user's own just-submitted content anyway), so the action is
  // hidden until a real UUID is available.
  bool get _canReport => _uuidPattern.hasMatch(incident.id);

  Color _severityColor() => SeverityColors.of(incident.severity);

  Future<void> _showReportDialog() async {
    final loc = AppLocalizations.of(context)!;
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        String? selected;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Widget option(String label, String value) {
              return RadioListTile<String>(
                title: Text(label),
                value: value,
                groupValue: selected,
                onChanged: (v) => setDialogState(() => selected = v),
              );
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              title: Text(loc.reportContentDialogTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(loc.reportContentDialogBody),
                  const SizedBox(height: 8),
                  option(loc.reportReasonFalse, 'false_information'),
                  option(loc.reportReasonInappropriate, 'inappropriate'),
                  option(loc.reportReasonSpam, 'spam'),
                  option(loc.reportReasonOther, 'other'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(loc.deleteAccountCancel),
                ),
                FilledButton(
                  onPressed: selected == null
                      ? null
                      : () => Navigator.pop(dialogContext, selected),
                  child: Text(loc.reportContentSubmit),
                ),
              ],
            );
          },
        );
      },
    );

    if (reason == null || !mounted) return;

    setState(() => _reporting = true);
    try {
      await IncidentApi.reportIncident(incident.id, reason: reason);
      if (!mounted) return;
      Navigator.of(context).maybePop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.reportContentSuccess)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.reportContentError)),
      );
    } finally {
      if (mounted) setState(() => _reporting = false);
    }
  }

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

            // ---------------------------
            // REPORT CONTENT (community reports only — official/news
            // pins aren't user-generated, so flagging them doesn't apply)
            // ---------------------------
            if (!incident.isOfficial && !incident.isApproximate && _canReport) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _reporting ? null : _showReportDialog,
                  icon: const Icon(Icons.flag_outlined, size: 16),
                  label: Text(loc.reportContent),
                  style: TextButton.styleFrom(
                    foregroundColor: BeeAwareTheme.textSecondary,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
