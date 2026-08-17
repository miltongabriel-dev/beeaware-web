import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../home/home_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../state/token_state.dart';
import '../theme/beeaware_theme.dart';

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    _initSession();

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showSplash = false);
    });
  }

  Future<void> _initSession() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user != null) {
      if (!mounted) return;
      await context.read<TokenState>().loadTokens();
    }

    Supabase.instance.client.auth.onAuthStateChange.listen((event) async {
      if (!mounted) return;

      final session = event.session;

      if (session != null) {
        await context.read<TokenState>().loadTokens();
      } else {}
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: _showSplash
          ? Container(
              key: const ValueKey('splash'),
              color: BeeAwareTheme.background,
              alignment: Alignment.center,
              child: Lottie.asset(
                'assets/lottie/beeaware_intro.json',
                width: 220,
                repeat: false,
              ),
            )
          : const HomeScreen(key: ValueKey('home')),
    );
  }
}
