import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../state/token_state.dart';
import '../theme/beeaware_theme.dart';
import '../theme/bee_loader.dart';
import '../theme/fade_in.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loadingGoogle = false;
  bool _loadingEmail = false;

  final TextEditingController _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: BeeAwareTheme.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                const SizedBox(height: 20),

                // LOGO
                FadeInUp(
                  child: SvgPicture.asset(
                    'assets/logo/beeaware_symbol.svg',
                    width: 70,
                  ),
                ),

                const SizedBox(height: 20),

                FadeInUp(
                  delay: const Duration(milliseconds: 150),
                  child: Text(
                    loc.loginHeadline,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: BeeAwareTheme.textPrimary,
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                FadeInUp(
                  delay: const Duration(milliseconds: 300),
                  child: Text(
                    loc.loginSubtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: BeeAwareTheme.textSecondary,
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),

                // CARD
                FadeInUp(
                  delay: const Duration(milliseconds: 450),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    decoration: BoxDecoration(
                      color: BeeAwareTheme.surface,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      boxShadow: BeeAwareTheme.cardShadow,
                    ),
                    child: Column(
                      children: [
                        // GOOGLE
                        _socialButton(
                          label: loc.continueWithGoogle,
                          icon: 'assets/icons/google_logo.svg',
                          loading: _loadingGoogle,
                          onTap: _loginGoogle,
                        ),

                        const SizedBox(height: 12),

                        // APPLE
                        if (!Theme.of(context)
                            .platform
                            .name
                            .contains('android'))
                          _socialButton(
                            label: loc.continueWithApple,
                            icon: 'assets/icons/apple_logo.svg',
                            loading: false,
                            onTap: () {},
                            enabled: false,
                          ),

                        const SizedBox(height: 6),
                        Text(
                          loc.appleSignInComingSoon,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),

                        const Divider(),

                        const SizedBox(height: 20),

                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            hintText: loc.enterYourEmail,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            prefixIcon: const Icon(Icons.email_outlined),
                          ),
                        ),

                        const SizedBox(height: 12),

                        ElevatedButton(
                          onPressed: _loadingEmail ? null : _magicLink,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                          child: _loadingEmail
                              ? const BeeLoader(size: 18, color: Colors.white)
                              : Text(loc.sendMagicLink),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                Text(
                  loc.privacyProtectedNotice,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===== LOGIN ACTIONS =====

  void _loginGoogle() async {
    setState(() => _loadingGoogle = true);

    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo:
            kIsWeb ? 'http://localhost:53755' : 'beeaware://login-callback',
      );
      await context.read<TokenState>().loadTokens();
    } catch (e) {
      debugPrint('Google login error: $e');
    }

    if (!mounted) return;
    setState(() => _loadingGoogle = false);

    // 🔥 carregar tokens do usuário
    context.read<TokenState>().loadTokens();
  }

  void _loginApple() {
    // TODO
  }

  void _magicLink() async {
    setState(() => _loadingEmail = true);

    try {
      final email = _emailController.text.trim();

      if (email.isEmpty) return;

      await Supabase.instance.client.auth.signInWithOtp(
        email: _emailController.text.trim(),
        emailRedirectTo: kIsWeb ? Uri.base.origin : null,
      );
      await context.read<TokenState>().loadTokens();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.checkEmailForLoginLink),
        ),
      );
    } catch (e) {
      debugPrint('Magic link error: $e');
    }

    if (!mounted) return;
    setState(() => _loadingEmail = false);

    context.read<TokenState>().loadTokens();
  }

  Widget _socialButton({
    required String label,
    required String icon,
    required bool loading,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled && !loading ? onTap : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: enabled ? 1 : 0.45,
          child: AnimatedContainer(
            constraints: const BoxConstraints(
              minHeight: 52,
            ),
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: BeeAwareTheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: const Color(0xFFE5E7EB),
              ),
              boxShadow: BeeAwareTheme.cardShadow,
            ),
            child: Row(
              children: [
                // ICON
                Flexible(
                  flex: 0,
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: SvgPicture.asset(icon),
                  ),
                ),

                const SizedBox(width: 12),

                // TEXT OR LOADING
                Expanded(
                  child: Center(
                    child: loading
                        ? const BeeLoader(size: 18)
                        : Text(
                            label,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),

                // 👉 subtle right spacer to keep balance
                const SizedBox(width: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
