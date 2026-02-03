import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class IntroScreen extends StatefulWidget {
  final VoidCallback onFinished;

  const IntroScreen({
    super.key,
    required this.onFinished,
  });

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Lottie.asset(
          'assets/lottie/beeaware_intro.json',
          controller: _controller,
          repeat: false,
          onLoaded: (composition) {
            _controller.duration = composition.duration;
            _controller.forward().whenComplete(widget.onFinished);
          },
        ),
      ),
    );
  }
}
