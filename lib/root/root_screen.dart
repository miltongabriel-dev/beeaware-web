import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
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

  // Set when the Início dashboard's map preview is tapped with a
  // manually-picked address active — HomeScreen (the Mapa tab) otherwise
  // has no idea a non-GPS location was chosen there, since it stays
  // mounted independently via IndexedStack and does its own geolocation
  // on first load.
  LatLng? _mapFocusLocation;

  // Bumped by the Início dashboard's "Mind the Path" card — see
  // HomeScreen.routeModeRequestId for why a plain bool can't signal a
  // repeat tap.
  int _routeModeRequestId = 0;

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

  void _openMapAt(LatLng? point) {
    setState(() {
      _mapFocusLocation = point;
      _selectedIndex = 1;
    });
  }

  void _openRouteMode() {
    setState(() {
      _selectedIndex = 1;
      _routeModeRequestId++;
    });
  }

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
            onOpenMap: _openMapAt,
            onOpenRoute: _openRouteMode,
          ),
          HomeScreen(
            focusLocation: _mapFocusLocation,
            routeModeRequestId: _routeModeRequestId,
          ),
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
