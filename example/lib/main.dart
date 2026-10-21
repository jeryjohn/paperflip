import 'package:flutter/material.dart';

import 'features/splash/splash_screen.dart';

export 'features/custom/custom_screen.dart';
export 'features/epub/epub_screen.dart';
export 'features/home/home_screen.dart';
export 'features/home/widgets/custom_card.dart';
export 'features/pdf/pdf_screen.dart';
export 'features/splash/splash_screen.dart';

void main() => runApp(const PaperFlipDemo());

/// Main demo application for PaperFlip.
class PaperFlipDemo extends StatelessWidget {
  const PaperFlipDemo({super.key, this.initialScreen});

  final Widget? initialScreen;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PaperFlip',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2C4239),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F8F7),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF111827),
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: Color(0xFF111827),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      home: initialScreen ?? const SplashScreen(),
    );
  }
}
