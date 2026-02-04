import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:pwa_install/pwa_install.dart' as pwa; // Import do PWA

import 'root/root_screen.dart';
import 'map/incident_store.dart';

Future<void> main() async {
  // 1. Garante a inicialização dos widgets
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Configura o prompt de instalação do PWA (essencial para o banner)
  pwa.PWAInstall().setup();

  // 3. Remove o '#' da URL para um visual profissional
  usePathUrlStrategy();

  // 4. Inicializa o Backend
  await Supabase.initialize(
    url: 'https://brjzkdtkmewbodpqjhkj.supabase.co',
    anonKey: 'sb_publishable_2__zBOoc8qdvJfRz8ejagw_2vT8Ji3P',
  );

  // 5. Carrega os dados locais
  await IncidentStore.init();

  // 6. Roda o App (apenas uma vez)
  runApp(const BeeAwareApp());
}

class BeeAwareApp extends StatelessWidget {
  const BeeAwareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BeeAware',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF59E0B),
          primary: const Color(0xFFF59E0B),
          surface: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF59E0B),
            foregroundColor: Colors.black,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
      home: const RootScreen(),
    );
  }
}
