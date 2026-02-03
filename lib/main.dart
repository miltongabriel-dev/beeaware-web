import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'root/root_screen.dart';
import 'map/incident_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://brjzkdtkmewbodpqjhkj.supabase.co',
    anonKey: 'sb_publishable_2__zBOoc8qdvJfRz8ejagw_2vT8Ji3P',
  );

  // ✅ CARREGA INCIDENTES LOCAIS ANTES DO APP SUBIR
  await IncidentStore.init();

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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF59E0B),
          primary: const Color(0xFFF59E0B),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF59E0B),
            foregroundColor: Colors.black,
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
