import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';

import 'root/root_screen.dart';
import 'map/incident_store.dart';
import 'state/token_state.dart';
import 'report/buy_tokens_screen.dart';
import 'report/search_address_screen.dart';
import 'package:flutter/foundation.dart';

bool _bonusChecked = false;

void setupAuthListener(BuildContext context) {
  Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
    final session = data.session;

    if (session != null && !_bonusChecked) {
      _bonusChecked = true;

      try {
        // 🔥 chama Edge Function
        await Supabase.instance.client.functions.invoke('onboarding-bonus');

        // 🔥 atualiza tokens
        await context.read<TokenState>().loadTokens();
      } catch (e) {
        debugPrint('Bonus error: $e');
      }
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  usePathUrlStrategy();

  try {
    await Supabase.initialize(
      url: 'https://brjzkdtkmewbodpqjhkj.supabase.co',
      anonKey: 'sb_publishable_2__zBOoc8qdvJfRz8ejagw_2vT8Ji3P',
    );

// ✅ FINALIZA LOGIN OAUTH NO WEB
    if (kIsWeb) {
      final uri = Uri.base;

      if (uri.queryParameters.containsKey('code')) {
        await Supabase.instance.client.auth
            .exchangeCodeForSession(uri.toString());
      }
    }

    await IncidentStore.init();
  } catch (e) {
    debugPrint("Backend init error: $e");
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => TokenState(),
      child: const BeeAwareApp(),
    ),
  );
}

class BeeAwareApp extends StatefulWidget {
  const BeeAwareApp({super.key});

  @override
  State<BeeAwareApp> createState() => _BeeAwareAppState();
}

class _BeeAwareAppState extends State<BeeAwareApp> {
  bool _bonusChecked = false;

  @override
  void initState() {
    super.initState();

    Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final session = data.session;

      if (session != null && !_bonusChecked) {
        _bonusChecked = true;

        try {
          await Supabase.instance.client.functions.invoke('onboarding-bonus');
          await context.read<TokenState>().loadTokens();
        } catch (e) {
          debugPrint('Bonus error: $e');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BeeAware',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF6F2E5),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF59E0B),
          primary: const Color(0xFFF59E0B),
          onPrimary: Colors.black,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.black,
            backgroundColor: const Color(0xFFF59E0B),
          ),
        ),
      ),
      home: const RootScreen(),
      routes: {
        '/buyTokens': (_) => const BuyTokensScreen(),
        '/searchAddress': (_) => const SearchAddressScreen(),
      },
    );
  }
}
