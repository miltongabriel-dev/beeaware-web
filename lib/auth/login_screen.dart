import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../state/token_state.dart';
import '../theme/beeaware_theme.dart';
import '../theme/bee_loader.dart';
import '../theme/fade_in.dart';

/// Random bytes for the Apple Sign In nonce (the plaintext half; Apple gets
/// the sha256 hash, Supabase verifies the ID token against the plaintext).
String _generateNonce([int length = 32]) {
  const charset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
  final random = Random.secure();
  return List.generate(length, (_) => charset[random.nextInt(charset.length)])
      .join();
}

String _sha256ofString(String input) {
  return sha256.convert(utf8.encode(input)).toString();
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loadingGoogle = false;
  bool _loadingApple = false;
  bool _loadingEmail = false;

  // Once a code has been emailed, the form switches from "enter your
  // email" to "enter the 6-digit code" — replaces the old click-a-link
  // magic link flow, which depended on the beeaware:// deep link
  // reopening the app reliably (same failure mode as the Google button).
  bool _otpSent = false;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();

    // Magic link / Google OAuth complete outside this screen (email app,
    // Safari) and reopen the app via the beeaware:// deep link. Without
    // this listener the screen just sits here after a successful login —
    // nothing else was popping it, which is the "stuck on a blank screen"
    // bug reported after logging in.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      // AuthChangeEvent.initialSession fires the instant this stream is
      // subscribed to, carrying whatever session was already restored
      // from local storage — NOT a fresh login. Reacting to it here was
      // popping this screen before the user even tapped anything if they
      // (or a tester) had a session persisted from a previous run.
      // Only a real signedIn event should close the screen.
      final isRealSignIn = data.event == AuthChangeEvent.signedIn;
      if (isRealSignIn && data.session != null && mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: BeeAwareTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: BeeAwareTheme.textPrimary,
      ),
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
                            loading: _loadingApple,
                            onTap: _loginApple,
                          ),

                        const SizedBox(height: 20),

                        const Divider(),

                        const SizedBox(height: 20),

                        TextField(
                          controller: _emailController,
                          enabled: !_otpSent,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            hintText: loc.enterYourEmail,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            prefixIcon:
                                const Icon(PhosphorIconsRegular.envelope),
                          ),
                        ),

                        if (_otpSent) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _codeController,
                            autofocus: true,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 6,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              hintText: loc.enterLoginCode,
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.md),
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 12),

                        ElevatedButton(
                          onPressed: _loadingEmail
                              ? null
                              : (_otpSent ? _verifyCode : _sendCode),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                          child: _loadingEmail
                              ? const BeeLoader(size: 18, color: Colors.white)
                              : Text(_otpSent
                                  ? loc.verifyCode
                                  : loc.sendLoginCode),
                        ),

                        if (_otpSent) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => setState(() {
                              _otpSent = false;
                              _codeController.clear();
                            }),
                            child: Text(loc.useDifferentEmail),
                          ),
                        ],
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
                    color: BeeAwareTheme.textAux,
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
        redirectTo: kIsWeb ? Uri.base.origin : 'beeaware://login-callback',
        // Default launch mode opens the external Safari app on iOS, which
        // doesn't reliably hand control back to BeeAware after Google
        // redirects to the beeaware:// scheme — that's the blank-screen-
        // then-manual-swipe bug. inAppWebView uses a sheet the OS closes
        // automatically the moment it sees the redirect, which is the
        // pattern Supabase's own docs recommend for native apps.
        authScreenLaunchMode:
            kIsWeb ? LaunchMode.platformDefault : LaunchMode.inAppWebView,
      );
      await context.read<TokenState>().loadTokens();
    } catch (e) {
      debugPrint('Google login error: $e');
    }

    if (!mounted) return;
    setState(() => _loadingGoogle = false);

    // 🔥 carregar tokens do usuário
    context.read<TokenState>().loadTokens();

    if (Supabase.instance.client.auth.currentSession != null && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _loginApple() async {
    setState(() => _loadingApple = true);

    try {
      final rawNonce = _generateNonce();
      final hashedNonce = _sha256ofString(rawNonce);

      // Native Apple Sign In (ASAuthorizationController) — no browser
      // redirect at all, so none of the beeaware:// deep-link handoff
      // issues that affect the Google button apply here.
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        throw const AuthException(
            'Apple sign-in did not return an identity token.');
      }

      await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );
      await context.read<TokenState>().loadTokens();
    } catch (e) {
      debugPrint('Apple login error: $e');
    }

    if (!mounted) return;
    setState(() => _loadingApple = false);

    if (Supabase.instance.client.auth.currentSession != null && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() => _loadingEmail = true);

    try {
      // No emailRedirectTo on native: without a redirect link, Supabase's
      // OTP email carries just the 6-digit code, which verifyOTP() below
      // checks directly — no deep link / app handoff involved at all.
      await Supabase.instance.client.auth.signInWithOtp(
        email: email,
        emailRedirectTo: kIsWeb ? Uri.base.origin : null,
      );

      if (!mounted) return;
      setState(() => _otpSent = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.checkEmailForCode),
        ),
      );
    } catch (e) {
      debugPrint('Send code error: $e');
    }

    if (!mounted) return;
    setState(() => _loadingEmail = false);
  }

  void _verifyCode() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    setState(() => _loadingEmail = true);

    try {
      await Supabase.instance.client.auth.verifyOTP(
        type: OtpType.email,
        email: email,
        token: code,
      );
      await context.read<TokenState>().loadTokens();
    } catch (e) {
      debugPrint('Verify code error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.invalidCodeError),
          ),
        );
      }
    }

    if (!mounted) return;
    setState(() => _loadingEmail = false);

    if (Supabase.instance.client.auth.currentSession != null && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
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
                color: BeeAwareTheme.border,
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
