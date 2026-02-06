import 'package:flutter/material.dart';
import '../home/home_screen.dart';

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  // Removemos a lógica do _showIntro daqui

  @override
  Widget build(BuildContext context) {
    // Agora retornamos apenas a HomeScreen diretamente
    return const HomeScreen();
  }
}
