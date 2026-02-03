import 'package:flutter/material.dart';

import 'report_draft.dart';
import 'report_location_screen.dart';

class ReportDescriptionScreen extends StatefulWidget {
  final ReportDraft draft;

  const ReportDescriptionScreen({super.key, required this.draft});

  @override
  State<ReportDescriptionScreen> createState() =>
      _ReportDescriptionScreenState();
}

class _ReportDescriptionScreenState extends State<ReportDescriptionScreen> {
  late final TextEditingController _controller;
  bool _canContinue = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.draft.description ?? '');
    _canContinue = _controller.text.trim().isNotEmpty;

    _controller.addListener(() {
      setState(() {
        _canContinue = _controller.text.trim().isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _continue() {
    widget.draft.description = _controller.text.trim();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportLocationScreen(draft: widget.draft),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Describe what happened'),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // ===== BeeAware watermark (background) =====
          Positioned.fill(
            child: Opacity(
              opacity: 0.04,
              child: Center(
                child: Image.asset(
                  'assets/logo/beeaware_watermark.png',
                  width: 320,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),

          // ===== Content =====
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),

                Text(
                  'Add a short description',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  'This helps others understand the situation better.',
                  style: theme.textTheme.bodySmall,
                ),

                const SizedBox(height: 20),

                // ===== Text field =====
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _controller,
                      maxLines: null,
                      expands: true,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText:
                            'Example: A group of people acting suspiciously near the station...',
                        border: InputBorder.none,
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ===== Continue button =====
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _canContinue ? _continue : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      disabledBackgroundColor:
                          theme.colorScheme.primary.withOpacity(0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Continue',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
