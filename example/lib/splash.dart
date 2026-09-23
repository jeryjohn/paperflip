import 'dart:async';
import 'package:flutter/material.dart';

import 'home.dart';

/// The entry splash screen shown when PaperFlip starts.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.autoTransition = true,
    this.transitionDelay = const Duration(milliseconds: 1400),
  });

  /// Whether to automatically transition to [HomeScreen] after [transitionDelay].
  final bool autoTransition;

  /// Duration before automatic transition occurs.
  final Duration transitionDelay;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _scaleAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeIn),
    );

    _animController.forward();

    if (widget.autoTransition) {
      _timer = Timer(widget.transitionDelay, _goToHome);
    }
  }

  void _goToHome() {
    _timer?.cancel();
    _timer = null;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 350),
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
      body: SafeArea(
        child: Center(
          child: AnimatedBuilder(
            animation: _animController,
            builder: (context, child) {
              return FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: child,
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C4239),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                      border: Border.all(
                        color: const Color(0xFF5A7D6F),
                        width: 1.5,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.auto_stories,
                        size: 52,
                        color: Color(0xFFE2EEDF),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'PaperFlip',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: Color(0xFFF4F6F3),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '3D Mesh Page-Turning Engine',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFFA6BAAF),
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      _FeatureBadge(label: 'Common (EPUB)'),
                      _FeatureBadge(label: 'PDF'),
                      _FeatureBadge(label: 'Custom Widgets'),
                    ],
                  ),
                  const SizedBox(height: 48),
                  ElevatedButton.icon(
                    key: const Key('enter_home_button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE2EEDF),
                      foregroundColor: const Color(0xFF1B2823),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _goToHome,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: const Text(
                      'Enter Library',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureBadge extends StatelessWidget {
  const _FeatureBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF263931),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF3B564B)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFC7DACF),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
