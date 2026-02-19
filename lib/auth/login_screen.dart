import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../state/token_state.dart';

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
    return Scaffold(
      backgroundColor: const Color(0xFFF6F2E5),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                const SizedBox(height: 20),

                // LOGO
                SvgPicture.asset(
                  'assets/logo/beeaware_logo.svg',
                  width: 70,
                ),

                const SizedBox(height: 20),

                const Text(
                  'Stay aware.\nStay safe.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2F3A4A),
                  ),
                ),

                const SizedBox(height: 14),

                const Text(
                  'Private by design. No personal data required.\nCommunity and official data to help you make safer decisions.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                  ),
                ),

                const SizedBox(height: 30),

                // CARD
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // GOOGLE
                      _socialButton(
                        label: 'Continue with Google',
                        icon: 'assets/icons/google_logo.svg',
                        loading: _loadingGoogle,
                        onTap: _loginGoogle,
                      ),

                      const SizedBox(height: 12),

                      // APPLE
                      if (!Theme.of(context).platform.name.contains('android'))
                        _socialButton(
                          label: 'Continue with Apple',
                          icon: 'assets/icons/apple_logo.svg',
                          loading: false,
                          onTap: () {},
                          enabled: false,
                        ),

                      const SizedBox(height: 6),
                      const Text(
                        'Apple sign-in coming soon',
                        style: TextStyle(
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
                          hintText: 'Enter your email',
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
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Send magic link'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                const Text(
                  'Your privacy is protected. No personal data required.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Check your email for the login link'),
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFE5E7EB),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
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
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
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
