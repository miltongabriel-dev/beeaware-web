import 'package:flutter/material.dart';
import '../home/home_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../state/token_state.dart';

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  @override
  void initState() {
    super.initState();
    _initSession();
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
    return const HomeScreen();
  }
}
