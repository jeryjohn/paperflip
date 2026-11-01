import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperflip_example/main.dart';

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

    group('Volume Button Platform Visibility', () {
      testWidgets(
        'CommonScreen (EPUB) shows volume button toggle and explanatory text on Android',
        (tester) async {
          try {
            debugDefaultTargetPlatformOverride = TargetPlatform.android;

            await tester.pumpWidget(
              const PaperFlipDemo(initialScreen: CommonScreen()),
            );
            await tester.pumpAndSettle();

            // Open settings modal
            await tester.tap(find.byKey(const Key('common_settings_button')));
            await tester.pumpAndSettle();

            // Volume keys option and explanatory text must be visible on Android
            expect(find.text('Use volume button'), findsOneWidget);
            expect(
              find.text('Turn pages using hardware volume keys'),
              findsOneWidget,
            );

            // Verify toggle interaction
            final switchTile = find.widgetWithText(
              SwitchListTile,
              'Use volume button',
            );
            expect(switchTile, findsOneWidget);
            expect(tester.widget<SwitchListTile>(switchTile).value, isFalse);

            await tester.tap(switchTile);
            await tester.pumpAndSettle();

            expect(tester.widget<SwitchListTile>(switchTile).value, isTrue);
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );

      for (final platform in [
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        testWidgets(
          'CommonScreen (EPUB) hides volume button option on ${platform.name}',
          (tester) async {
            try {
              debugDefaultTargetPlatformOverride = platform;

              await tester.pumpWidget(
                const PaperFlipDemo(initialScreen: CommonScreen()),
              );
              await tester.pumpAndSettle();

              // Open settings modal
              await tester.tap(find.byKey(const Key('common_settings_button')));
              await tester.pumpAndSettle();

              // Volume keys option and explanatory text must be hidden on non-Android platforms
              expect(find.text('Use volume button'), findsNothing);
              expect(
                find.text('Turn pages using hardware volume keys'),
                findsNothing,
              );
            } finally {
              debugDefaultTargetPlatformOverride = null;
            }
          },
        );
      }

      testWidgets(
        'CustomScreen shows volume action on Android and toggles state',
        (tester) async {
          try {
            debugDefaultTargetPlatformOverride = TargetPlatform.android;

            await tester.pumpWidget(
              const PaperFlipDemo(initialScreen: CustomScreen()),
            );
            await tester.pumpAndSettle();

            expect(find.byTooltip('Volume keys disabled'), findsOneWidget);
            await tester.tap(find.byTooltip('Volume keys disabled'));
            await tester.pumpAndSettle();
            expect(find.byTooltip('Volume keys enabled'), findsOneWidget);
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );

      for (final platform in [
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        testWidgets('CustomScreen hides volume action on ${platform.name}', (
          tester,
        ) async {
          try {
            debugDefaultTargetPlatformOverride = platform;

            await tester.pumpWidget(
              const PaperFlipDemo(initialScreen: CustomScreen()),
            );
            await tester.pumpAndSettle();

            expect(find.byTooltip('Volume keys disabled'), findsNothing);
            expect(find.byTooltip('Volume keys enabled'), findsNothing);
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        });
      }

      testWidgets('PdfScreen shows volume action on Android', (tester) async {
        try {
          debugDefaultTargetPlatformOverride = TargetPlatform.android;

          await tester.pumpWidget(
            const PaperFlipDemo(initialScreen: PdfScreen()),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          expect(find.byTooltip('Volume keys disabled'), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      for (final platform in [
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        testWidgets('PdfScreen hides volume action on ${platform.name}', (
          tester,
        ) async {
          try {
            debugDefaultTargetPlatformOverride = platform;

            await tester.pumpWidget(
              const PaperFlipDemo(initialScreen: PdfScreen()),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 200));

            expect(find.byTooltip('Volume keys disabled'), findsNothing);
            expect(find.byTooltip('Volume keys enabled'), findsNothing);
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        });
      }
    });
  });
}
