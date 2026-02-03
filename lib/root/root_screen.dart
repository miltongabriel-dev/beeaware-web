import 'package:aware/intro/intro_overlay.dart';
import 'package:flutter/material.dart';
import '../home/home_screen.dart';

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  bool _showIntro = true;

  void _handleIntroFinished() {
    setState(() => _showIntro = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const HomeScreen(), // mapa já ativo

        if (_showIntro)
          IntroScreen(
            onFinished: _handleIntroFinished,
          ),
      ],
    );
  }
}
