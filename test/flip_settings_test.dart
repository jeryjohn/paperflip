import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flip_book/flip_book.dart';

Widget _book({
  required FlipBookController controller,
  FlipSettings flip = const FlipSettings(),
  int pageCount = 10,
  int initialPage = 0,
}) {
  return MaterialApp(
    home: Scaffold(
      body: FlipBookWidget(
        pageCount: pageCount,
        initialPage: initialPage,
        controller: controller,
        flip: flip,
        showPageIndicator: false,
        pageBuilder: (context, index, constraints) => ColoredBox(
          color: Colors.white,
          child: Center(child: Text('Page $index')),
        ),
      ),
    ),
  );
}

void main() {
  group('FlipSettings value semantics', () {
    test('instances with equal fields are equal', () {
      const a = FlipSettings(duration: Duration(milliseconds: 300));
      const b = FlipSettings(duration: Duration(milliseconds: 300));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differing fields are unequal', () {
      const a = FlipSettings();
      expect(a, isNot(const FlipSettings(enabled: false)));
      expect(a, isNot(const FlipSettings(showShadow: false)));
      expect(a, isNot(const FlipSettings(showBackFace: false)));
      expect(a, isNot(const FlipSettings(curve: Curves.linear)));
      expect(a, isNot(const FlipSettings(settleCurve: Curves.linear)));
      expect(a, isNot(const FlipSettings(duration: Duration(seconds: 9))));
    });

    test('copyWith replaces only the named field', () {
      const base = FlipSettings(duration: Duration(milliseconds: 250));
      final copy = base.copyWith(enabled: false);

      expect(copy.enabled, isFalse);
      expect(copy.duration, const Duration(milliseconds: 250));
      expect(copy.curve, base.curve);
      expect(base.enabled, isTrue, reason: 'must not mutate the original');
    });

    test('defaults match the original hard-coded behaviour', () {
      const defaults = FlipSettings();
      expect(defaults.enabled, isTrue);
      expect(defaults.duration, const Duration(milliseconds: 600));
      expect(defaults.curve, Curves.easeInOut);
      expect(defaults.settleCurve, Curves.easeOut);
      expect(defaults.showShadow, isTrue);
      expect(defaults.showBackFace, isTrue);
      expect(defaults.direction, FlipDirection.horizontal);
    });
  });

  group('FlipSettings.enabled', () {
    testWidgets('a disabled flip changes page within one frame', (
      tester,
    ) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _book(controller: controller, flip: const FlipSettings(enabled: false)),
      );

      controller.flipNext();
      await tester.pump();

      expect(controller.currentPage, 1);
      expect(controller.isAnimating, isFalse);
      expect(find.text('Page 1'), findsOneWidget);
    });

    testWidgets('a disabled multi-page goToPage still lands on target', (
      tester,
    ) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _book(controller: controller, flip: const FlipSettings(enabled: false)),
      );

      unawaited(controller.goToPage(6));
      await tester.pump();

      expect(controller.currentPage, 6);
    });

    testWidgets('swipe still turns pages with the curl disabled', (
      tester,
    ) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _book(controller: controller, flip: const FlipSettings(enabled: false)),
      );

      await tester.drag(find.byType(FlipBookWidget), const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(controller.currentPage, 1);
    });

    testWidgets('a tiny swipe below threshold does not turn the page', (
      tester,
    ) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _book(
          controller: controller,
          flip: const FlipSettings(enabled: false),
          initialPage: 3,
        ),
      );

      await tester.drag(find.byType(FlipBookWidget), const Offset(-10, 0));
      await tester.pumpAndSettle();

      expect(controller.currentPage, 3);
    });

    testWidgets('toggling enabled off mid-flip does not strand a turn', (
      tester,
    ) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_book(controller: controller));
      controller.flipNext();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.isAnimating, isTrue);

      await tester.pumpWidget(
        _book(controller: controller, flip: const FlipSettings(enabled: false)),
      );
      await tester.pumpAndSettle();

      expect(controller.isAnimating, isFalse);
      expect(controller.currentPage, 1);
    });
  });

  group('FlipSettings animation tuning', () {
    testWidgets('a long duration is honoured and not capped at 600ms', (
      tester,
    ) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _book(
          controller: controller,
          flip: const FlipSettings(duration: Duration(milliseconds: 1500)),
        ),
      );

      controller.flipNext();
      await tester.pump();
      // Well past the old 600ms cap but short of 1500ms.
      await tester.pump(const Duration(milliseconds: 900));
      expect(
        controller.isAnimating,
        isTrue,
        reason: 'a 1500ms flip should still be running at 900ms',
      );

      await tester.pumpAndSettle();
      expect(controller.currentPage, 1);
    });

    testWidgets('a short duration completes quickly', (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _book(
          controller: controller,
          flip: const FlipSettings(duration: Duration(milliseconds: 100)),
        ),
      );

      controller.flipNext();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(controller.currentPage, 1);
    });

    testWidgets('changing the curve at runtime does not throw', (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_book(controller: controller));
      await tester.pumpWidget(
        _book(
          controller: controller,
          flip: const FlipSettings(curve: Curves.linear),
        ),
      );
      await tester.pumpAndSettle();

      controller.flipNext();
      await tester.pumpAndSettle();
      expect(controller.currentPage, 1);
    });
  });

  group('FlipSettings shadow and back face', () {
    testWidgets('showBackFace: false still renders a flip', (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _book(
          controller: controller,
          flip: const FlipSettings(showBackFace: false),
        ),
      );

      controller.flipNext();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(controller.currentPage, 1);
    });

    testWidgets('showShadow: false still renders a flip', (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _book(
          controller: controller,
          flip: const FlipSettings(showShadow: false),
        ),
      );

      controller.flipNext();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(controller.currentPage, 1);
    });
  });

  group('PageFlipPainter.shouldRepaint', () {
    test('repaints when a visual flag or colour changes', () {
      const base = PageFlipPainter(
        progress: 0.5,
        corner: FlipCorner.bottomRight,
        isForward: true,
      );

      expect(
        base.shouldRepaint(
          const PageFlipPainter(
            progress: 0.5,
            corner: FlipCorner.bottomRight,
            isForward: true,
            showShadow: false,
          ),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          const PageFlipPainter(
            progress: 0.5,
            corner: FlipCorner.bottomRight,
            isForward: true,
            pageBackColor: Color(0xFF123456),
          ),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          const PageFlipPainter(
            progress: 0.5,
            corner: FlipCorner.bottomRight,
            isForward: true,
          ),
        ),
        isFalse,
      );
    });
  });

  group('FlipBookController runtime overrides', () {
    testWidgets('setFlipEnabled(false) disables the curl without a rebuild', (
      tester,
    ) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_book(controller: controller));

      controller.setFlipEnabled(false);
      await tester.pump();

      controller.flipNext();
      await tester.pump();

      // Instant: no animation frames needed.
      expect(controller.currentPage, 1);
      expect(controller.isAnimating, isFalse);
    });

    testWidgets('clearFlipOverrides restores the widget settings', (
      tester,
    ) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_book(controller: controller));

      controller.setFlipEnabled(false);
      await tester.pump();
      controller.clearFlipOverrides();
      await tester.pump();

      controller.flipNext();
      await tester.pump();
      // Animation is back, so the page has not committed yet.
      expect(controller.isAnimating, isTrue);

      await tester.pumpAndSettle();
      expect(controller.currentPage, 1);
    });

    testWidgets('setFlipDuration overrides the widget duration', (
      tester,
    ) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _book(
          controller: controller,
          flip: const FlipSettings(duration: Duration(milliseconds: 100)),
        ),
      );

      controller.setFlipDuration(const Duration(milliseconds: 1200));
      await tester.pump();

      controller.flipNext();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        controller.isAnimating,
        isTrue,
        reason: 'the 1200ms override should outlast the widget 100ms',
      );

      await tester.pumpAndSettle();
      expect(controller.currentPage, 1);
    });

    testWidgets('disabling mid-flip via the controller commits the turn', (
      tester,
    ) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_book(controller: controller));

      controller.flipNext();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.isAnimating, isTrue);

      controller.setFlipEnabled(false);
      await tester.pumpAndSettle();

      expect(controller.isAnimating, isFalse);
      expect(controller.currentPage, 1);
    });

    testWidgets('an override applies to a controller attached later', (
      tester,
    ) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      controller.setFlipEnabled(false);
      await tester.pumpWidget(_book(controller: controller));

      controller.flipNext();
      await tester.pump();

      expect(controller.currentPage, 1);
      expect(controller.isAnimating, isFalse);
    });
  });
}
