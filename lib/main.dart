import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'root/root_screen.dart';
import 'map/incident_store.dart';

Future<void> main() async {
  // 1. Configuração básica (essencial ser await)
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Remove o '#' da URL (estratégia de navegação web)
  usePathUrlStrategy();

  // 3. Inicialização Assíncrona (Sem travar o runApp)
  // Removemos os 'await' para que o Flutter desenhe a interface
  // enquanto a conexão com o banco acontece em paralelo.
  try {
    Supabase.initialize(
      url: 'https://brjzkdtkmewbodpqjhkj.supabase.co',
      anonKey: 'sb_publishable_2__zBOoc8qdvJfRz8ejagw_2vT8Ji3P',
    ).catchError((e) => debugPrint("Supabase error: $e"));

    // Chamamos o init sem o await
    IncidentStore.init();
  } catch (e) {
    debugPrint("Backend init error: $e");
  }

  // 4. Lança o app imediatamente
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
        scaffoldBackgroundColor: const Color(0xFFF6F2E5),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF59E0B),
          primary: const Color(0xFFF59E0B),
        ),
      ),
      // AQUI: Troca RootScreen() por BeeAwareSplashScreen()
      home: const RootScreen(),
    );
  }
}
