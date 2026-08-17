import 'package:flutter/material.dart';
import 'report_draft.dart';
import 'report_step_indicator.dart';
import 'report_summary_screen.dart';
import '../config/app_config.dart';
import '../l10n/app_localizations.dart';

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

    return Scaffold(
      appBar: AppBar(title: Text(loc.whenDidItHappenTitle)),
      body: Column(
        children: [
          const ReportStepIndicator(step: 5),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(loc.adjustDateTimeHint),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: Text(loc.dateLabel),
                    subtitle: Text(
                      '${selectedDateTime.day}/${selectedDateTime.month}/${selectedDateTime.year}',
                    ),
                    onTap: _pickDate,
                  ),
                  ListTile(
                    leading: const Icon(Icons.access_time),
                    title: Text(loc.timeLabel),
                    subtitle: Text(
                      '${selectedDateTime.hour.toString().padLeft(2, '0')}:${selectedDateTime.minute.toString().padLeft(2, '0')}',
                    ),
                    onTap: _pickTime,
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
                            builder: (_) =>
                                ReportSummaryScreen(draft: widget.draft),
                          ),
                        );
                      },
                      child: Text(loc.confirmReport),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
