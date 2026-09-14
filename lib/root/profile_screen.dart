import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:pwa_install/pwa_install.dart' as pwa;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/login_screen.dart';
import '../config/app_config.dart';
import '../l10n/app_localizations.dart';
import '../report/buy_tokens_screen.dart';
import '../state/locale_state.dart';
import '../state/token_state.dart';
import '../theme/app_card.dart';
import '../theme/beeaware_theme.dart';
import 'emergency_contact_screen.dart';
import 'pwa_bridge_stub.dart'
    if (dart.library.js) 'pwa_bridge_web.dart' as pwa_bridge;

/// The "Perfil" tab. Surfaces the same account actions the map's own
/// hamburger menu already has (home_screen.dart's _buildMenuContent) as a
/// full page instead of a popup, plus the PWA-install affordance that used
/// to live in the map-only bottom bar — moved here since this is the one
/// tab that makes sense to keep reachable regardless of which one is
/// active.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _canInstall = false;
  Timer? _pwaTimer;
  bool _deletingAccount = false;

  @override
  void initState() {
    super.initState();
    _pwaTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final ok = pwa_bridge.isPwaInstallable();
      if (mounted && ok != _canInstall) {
        setState(() => _canInstall = ok);
      }
    });
  }

  @override
  void dispose() {
    _pwaTimer?.cancel();
    super.dispose();
  }

  void _installApp() {
    if (pwa_bridge.isPwaInstallable()) {
      pwa_bridge.triggerPwaInstall();
    } else {
      pwa.PWAInstall().promptInstall_();
    }
  }

  void _showLanguagePicker(BuildContext context) {
    final localeState = context.read<LocaleState>();

    showDialog(
      context: context,
      builder: (dialogContext) {
        final loc = AppLocalizations.of(dialogContext)!;

        Widget option(String label, Locale? value) {
          return RadioListTile<Locale?>(
            title: Text(label),
            value: value,
            groupValue: localeState.locale,
            onChanged: (selected) {
              localeState.setLocale(selected);
              Navigator.pop(dialogContext);
            },
          );
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          title: Text(loc.languageLabel),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              option(loc.languageAutomatic, null),
              option(loc.languagePortuguese, const Locale('pt')),
              option(loc.languageEnglish, const Locale('en')),
            ],
          ),
        );
      },
    );
  }

  Future<void> _signOut(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
    if (!context.mounted) return;
    context.read<TokenState>().clear();
    setState(() {});
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final loc = AppLocalizations.of(context)!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Text(loc.deleteAccountDialogTitle),
        content: Text(loc.deleteAccountDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(loc.deleteAccountCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(loc.deleteAccountConfirm),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    setState(() => _deletingAccount = true);
    try {
      // Runs server-side via the delete-account Edge Function (uses the
      // service role to remove the auth user + related rows —
      // emergency_contacts, user_tokens, token_transactions — none of
      // which auth clients can do with just the user's own JWT). See
      // Guideline 5.1.1(v): apps that support account creation must let
      // the user delete their account from inside the app.
      await Supabase.instance.client.functions.invoke('delete-account');
      await Supabase.instance.client.auth.signOut();
      if (!context.mounted) return;
      context.read<TokenState>().clear();
      setState(() => _deletingAccount = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.deleteAccountSuccess)),
      );
    } catch (_) {
      if (!context.mounted) return;
      setState(() => _deletingAccount = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.deleteAccountError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final user = Supabase.instance.client.auth.currentUser;
    final tokens = context.watch<TokenState>().tokens;

    return Scaffold(
      backgroundColor: BeeAwareTheme.background,
      appBar: AppBar(title: Text(loc.profileTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            AppCard(
              onTap: user == null
                  ? () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    )
                  : null,
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          BeeAwareTheme.accent,
                          const Color(0xFFFBBF24),
                        ],
                      ),
                    ),
                    child: Icon(
                      user == null
                          ? PhosphorIconsRegular.person
                          : PhosphorIconsRegular.sealCheck,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user == null
                              ? loc.signInToBeeAware
                              : (user.email ?? loc.signedIn),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        if (user == null || AppConfig.tokensEnabled)
                          Text(
                            user == null
                                ? loc.secureLoginGoogleEmail
                                : loc.tokensAvailable(tokens),
                            style: const TextStyle(
                              fontSize: 12,
                              color: BeeAwareTheme.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (user == null)
                    const Icon(PhosphorIconsRegular.caretRight,
                        size: 20, color: BeeAwareTheme.textAux),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            if (AppConfig.tokensEnabled) ...[
              _ProfileItem(
                icon: PhosphorIconsRegular.creditCard,
                label: loc.buyMoreCredits,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BuyTokensScreen()),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            _ProfileItem(
              icon: PhosphorIconsRegular.globe,
              label: loc.languageLabel,
              onTap: () => _showLanguagePicker(context),
            ),
            if (user != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _ProfileItem(
                icon: PhosphorIconsRegular.userFocus,
                label: loc.emergencyContactTitle,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const EmergencyContactScreen()),
                ),
              ),
            ],
            if (_canInstall) ...[
              const SizedBox(height: AppSpacing.sm),
              _ProfileItem(
                icon: PhosphorIconsRegular.downloadSimple,
                label: loc.installAppTooltip,
                onTap: _installApp,
              ),
            ],
            if (user != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _ProfileItem(
                icon: PhosphorIconsRegular.signOut,
                label: loc.signOut,
                onTap: () => _signOut(context),
              ),
              const SizedBox(height: AppSpacing.sm),
              _ProfileItem(
                icon: PhosphorIconsRegular.trash,
                label: loc.deleteAccount,
                onTap: _deletingAccount ? () {} : () => _deleteAccount(context),
                destructive: true,
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            Center(
              child: GestureDetector(
                onTap: () => launchUrl(
                  Uri.parse('https://jagolabs.tech'),
                  mode: LaunchMode.externalApplication,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/logo/jagolabs_symbol.png',
                      width: 14,
                      height: 14,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'developed by jagolabs.tech',
                      style: TextStyle(
                        fontSize: 12,
                        color: BeeAwareTheme.textAux,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const _ProfileItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Colors.red : BeeAwareTheme.textPrimary;
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: destructive ? Colors.red : null,
              ),
            ),
          ),
          const Icon(PhosphorIconsRegular.caretRight,
              size: 18, color: BeeAwareTheme.textAux),
        ],
      ),
    );
  }
}
