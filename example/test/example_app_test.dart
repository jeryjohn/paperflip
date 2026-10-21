import 'package:paperflip_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaperFlip Example App Tests', () {
    testWidgets('SplashScreen displays branding and navigates to HomeScreen', (
      tester,
    ) async {
      await tester.pumpWidget(const PaperFlipDemo());

      // Splash screen should be visible with only PaperFlip
      expect(find.byKey(const Key('splash_screen')), findsOneWidget);
      expect(find.text('PaperFlip'), findsOneWidget);

      // Tap screen to navigate immediately to HomeScreen
      final enterButton = find.byKey(const Key('enter_home_button'));
      expect(enterButton, findsOneWidget);
      await tester.tap(enterButton);
      await tester.pumpAndSettle();

      // Should now be on HomeScreen
      expect(find.byKey(const Key('home_screen')), findsOneWidget);
      expect(find.byKey(const Key('home_common_tile')), findsOneWidget);
      expect(find.byKey(const Key('home_pdf_tile')), findsOneWidget);
      expect(find.byKey(const Key('home_custom_tile')), findsOneWidget);
    });

    testWidgets('SplashScreen auto-transitions after duration', (tester) async {
      await tester.pumpWidget(
        const PaperFlipDemo(
          initialScreen: SplashScreen(
            autoTransition: true,
            transitionDelay: Duration(milliseconds: 100),
          ),
        ),
      );

      expect(find.byKey(const Key('splash_screen')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();

      // Automatically reached HomeScreen
      expect(find.byKey(const Key('home_screen')), findsOneWidget);
    });

    testWidgets(
      'HomeScreen opens CustomScreen and interacts with pages and curl',
      (tester) async {
        await tester.pumpWidget(
          const PaperFlipDemo(initialScreen: HomeScreen()),
        );

        expect(find.byKey(const Key('home_screen')), findsOneWidget);

        // Tap Custom widgets tile
        await tester.tap(find.byKey(const Key('home_custom_tile')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('custom_screen')), findsOneWidget);
        expect(find.text('Page 1 of 8'), findsOneWidget);

        // Flip forward
        await tester.tap(find.byKey(const Key('custom_next_button')));
        await tester.pumpAndSettle();
        expect(find.text('Page 2 of 8'), findsOneWidget);

        // Flip backward
        await tester.tap(find.byKey(const Key('custom_prev_button')));
        await tester.pumpAndSettle();
        expect(find.text('Page 1 of 8'), findsOneWidget);

        // Toggle curl
        await tester.tap(find.byKey(const Key('custom_toggle_curl')));
        await tester.pumpAndSettle();

        // Pop back to home
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('home_screen')), findsOneWidget);
      },
    );

    testWidgets('HomeScreen opens PdfScreen and navigates back', (
      tester,
    ) async {
      await tester.pumpWidget(const PaperFlipDemo(initialScreen: HomeScreen()));

      // Tap PDF reader tile
      await tester.tap(find.byKey(const Key('home_pdf_tile')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const Key('pdf_screen')), findsOneWidget);

      // Pop back to home
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home_screen')), findsOneWidget);
    });

    testWidgets(
      'HomeScreen opens CommonScreen (EPUB) and opens settings modal',
      (tester) async {
        await tester.pumpWidget(
          const PaperFlipDemo(initialScreen: HomeScreen()),
        );

        // Tap Common (EPUB) tile
        await tester.tap(find.byKey(const Key('home_common_tile')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('common_screen')), findsOneWidget);

        // Toggle typography settings bar
        await tester.tap(find.byKey(const Key('common_settings_button')));
        await tester.pumpAndSettle();

        expect(find.text('Theme: '), findsOneWidget);
        expect(find.text('Sepia'), findsOneWidget);

        // Tap Sepia theme
        await tester.tap(find.text('Sepia'));
        await tester.pumpAndSettle();

        // Tap Dark theme
        await tester.tap(find.text('Dark'));
        await tester.pumpAndSettle();
      },
    );
  });
}
