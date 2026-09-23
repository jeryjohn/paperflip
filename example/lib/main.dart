import 'package:flutter/material.dart';

import 'splash.dart';

export 'common.dart';
export 'custom.dart';
export 'home.dart';
export 'pdf.dart';
export 'splash.dart';

void main() => runApp(const PaperFlipDemo());

/// Main demo application for PaperFlip.
class PaperFlipDemo extends StatelessWidget {
  const PaperFlipDemo({
    super.key,
    this.initialScreen,
  });

  /// Optional screen to start with (useful for tests or direct navigation).
  final Widget? initialScreen;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PaperFlip',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF355C4B),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F6F2),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF7F6F2),
          foregroundColor: Color(0xFF1C2923),
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: Color(0xFF1C2923),
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        dividerColor: const Color(0xFFE2E4DF),
      ),
      home: initialScreen ?? const SplashScreen(),
    );
  }
}
