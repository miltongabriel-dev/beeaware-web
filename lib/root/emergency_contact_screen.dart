import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../backend/emergency_contact_api.dart';
import '../l10n/app_localizations.dart';
import '../theme/beeaware_theme.dart';

/// Perfil > "Contato de emergência" — register the one trusted contact
/// who can be notified over WhatsApp, with a live location link, from the
/// SOS sheet (see emergency_sos.dart). Reachable only when logged in
/// (ProfileScreen only shows the entry point then), same login gate the
/// user asked for.
class EmergencyContactScreen extends StatefulWidget {
  const EmergencyContactScreen({super.key});

  @override
  State<EmergencyContactScreen> createState() =>
      _EmergencyContactScreenState();
}

class _EmergencyContactScreenState extends State<EmergencyContactScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _hadContact = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final contact = await EmergencyContactApi.fetchMine();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _hadContact = contact != null;
      if (contact != null) {
        _nameController.text = contact.name;
        _phoneController.text = contact.phone;
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    if (name.isEmpty || phone.isEmpty) return;

    setState(() => _saving = true);
    final ok = await EmergencyContactApi.save(name: name, phone: phone);
    if (!mounted) return;
    setState(() => _saving = false);

    final loc = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(ok ? loc.emergencyContactSaved : loc.emergencyContactSaveError)),
    );
    if (ok) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    setState(() => _saving = true);
    final ok = await EmergencyContactApi.delete();
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop();
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: BeeAwareTheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: BeeAwareTheme.cardShadow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: BeeAwareTheme.background,
      appBar: AppBar(title: Text(loc.emergencyContactTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Text(
                    loc.emergencyContactExplanation,
                    style: const TextStyle(
                      fontSize: 13,
                      color: BeeAwareTheme.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _field(
                    controller: _nameController,
                    hint: loc.emergencyContactNameHint,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _field(
                    controller: _phoneController,
                    hint: loc.emergencyContactPhoneHint,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  ElevatedButton.icon(
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(PhosphorIconsRegular.check),
                    label: Text(loc.emergencyContactSave),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BeeAwareTheme.accent,
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _saving ? null : _save,
                  ),
                  if (_hadContact) ...[
                    const SizedBox(height: AppSpacing.sm),
                    TextButton.icon(
                      icon: const Icon(PhosphorIconsRegular.trash,
                          color: SeverityColors.high),
                      label: Text(
                        loc.emergencyContactRemove,
                        style: const TextStyle(color: SeverityColors.high),
                      ),
                      onPressed: _saving ? null : _delete,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
