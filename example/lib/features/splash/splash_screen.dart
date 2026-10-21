import 'dart:async';
import 'package:flutter/material.dart';

import '../home/home_screen.dart';

/// A simple, elegant splash screen showing only "PaperFlip".
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.autoTransition = true,
    this.transitionDelay = const Duration(milliseconds: 1200),
  });

  final bool autoTransition;
  final Duration transitionDelay;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();

    if (widget.autoTransition) {
      _timer = Timer(widget.transitionDelay, _goToHome);
    }
  }

  void _goToHome() {
    _timer?.cancel();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, animation, __) => const HomeScreen(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('splash_screen'),
      backgroundColor: const Color(0xFF1B2823),
      body: GestureDetector(
        key: const Key('enter_home_button'),
        behavior: HitTestBehavior.opaque,
        onTap: _goToHome,
        child: Center(
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _animController,
              curve: Curves.easeIn,
            ),
            child: const Text(
              'PaperFlip',
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: Color(0xFFF4F6F3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
