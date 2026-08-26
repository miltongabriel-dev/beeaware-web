import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../home/home_dashboard_screen.dart';
import '../home/home_screen.dart';
import '../report/report_category_screen.dart';
import '../state/token_state.dart';
import '../theme/beeaware_theme.dart';
import 'alerts_screen.dart';
import 'profile_screen.dart';
import 'widgets/app_bottom_nav.dart';

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _selectedIndex = 0;

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

  void _selectTab(int index) => setState(() => _selectedIndex = index);

  void _openReport() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReportCategoryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // IndexedStack keeps every tab mounted (map camera position, open
    // filters, etc. all survive switching tabs) — the same reason
    // HomeScreen's periodic incident sync keeps running regardless of
    // which tab is actually visible.
    return Scaffold(
      backgroundColor: BeeAwareTheme.background,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          HomeDashboardScreen(
            onOpenAlerts: () => _selectTab(2),
            onOpenMap: () => _selectTab(1),
          ),
          const HomeScreen(),
          const AlertsScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _selectedIndex,
        onTabSelected: _selectTab,
        onReport: _openReport,
      ),
    );
  }
}
