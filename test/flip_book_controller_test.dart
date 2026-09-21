import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flip_book/flip_book.dart';

/// Tracks completion of [future] without awaiting it.
///
/// Awaiting a library future directly inside `testWidgets` hangs forever if it
/// never completes; asserting on the flag fails the test instead.
({bool Function() didComplete}) _track(Future<void> future) {
  var completed = false;
  unawaited(future.then((_) => completed = true));
  return (didComplete: () => completed);
}

/// Builds a minimal book whose pages are identifiable by text.
Widget _book({
  required FlipBookController controller,
  int pageCount = 10,
  int initialPage = 0,
}) {
  return MaterialApp(
    home: Scaffold(
      body: FlipBookWidget(
        pageCount: pageCount,
        initialPage: initialPage,
        controller: controller,
        pageBuilder: (context, index, constraints) => ColoredBox(
          color: Colors.white,
          child: Center(child: Text('Page $index')),
        ),
      ),
    ),
  );
}

void main() {
  group('FlipBookController navigation', () {
    testWidgets(
      'goToPage animates through every page and lands on the target',
      (tester) async {
        final controller = FlipBookController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(_book(controller: controller));
        expect(controller.currentPage, 0);

        final journey = _track(controller.goToPage(6));
        await tester.pumpAndSettle();

        expect(controller.currentPage, 6);
        expect(
          journey.didComplete(),
          isTrue,
          reason: 'goToPage future should complete once the target is reached',
        );
      },
    );

    testWidgets('goToPage backwards lands on the target', (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_book(controller: controller, initialPage: 8));
      expect(controller.currentPage, 8);

      final journey = _track(controller.goToPage(2));
      await tester.pumpAndSettle();

      expect(controller.currentPage, 2);
      expect(journey.didComplete(), isTrue);
    });

    testWidgets('goToPage(animate: false) jumps instantly', (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_book(controller: controller));

      final journey = _track(controller.goToPage(7, animate: false));
      await tester.pump();

      expect(controller.currentPage, 7);
      expect(journey.didComplete(), isTrue);
    });

    testWidgets('goToPage clamps beyond the last page', (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_book(controller: controller, pageCount: 5));

      final journey = _track(controller.goToPage(99));
      await tester.pumpAndSettle();

      expect(controller.currentPage, 4);
      expect(journey.didComplete(), isTrue);
    });

    testWidgets('goToPage to the current page is a no-op', (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_book(controller: controller, initialPage: 3));

      // Already on page 3: completes immediately, nothing queued.
      final journey = _track(controller.goToPage(3));
      await tester.pumpAndSettle();

      expect(controller.currentPage, 3);
      expect(journey.didComplete(), isTrue);
    });

    testWidgets('flipNext advances exactly one page', (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_book(controller: controller));

      controller.flipNext();
      await tester.pumpAndSettle();

      expect(controller.currentPage, 1);
    });

    testWidgets('flipPrev retreats exactly one page', (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_book(controller: controller, initialPage: 4));

      controller.flipPrev();
      await tester.pumpAndSettle();

      expect(controller.currentPage, 3);
    });

    testWidgets('flipNext at the last page does nothing', (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _book(controller: controller, pageCount: 3, initialPage: 2),
      );

      controller.flipNext();
      await tester.pumpAndSettle();

      expect(controller.currentPage, 2);
    });

    testWidgets('flipPrev at the first page does nothing', (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_book(controller: controller));

      controller.flipPrev();
      await tester.pumpAndSettle();

      expect(controller.currentPage, 0);
    });

    testWidgets('nextPage / previousPage step without animating', (
      tester,
    ) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_book(controller: controller));

      controller.nextPage();
      await tester.pump();
      expect(controller.currentPage, 1);
      expect(controller.isAnimating, isFalse);

      controller.previousPage();
      await tester.pump();
      expect(controller.currentPage, 0);
      expect(controller.isAnimating, isFalse);
    });

    testWidgets('consecutive flipNext calls are not dropped', (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_book(controller: controller));

      // Queued back-to-back inside one frame, while no animation has started.
      controller.flipNext();
      controller.flipNext();
      controller.flipNext();
      await tester.pumpAndSettle();

      expect(controller.currentPage, 3);
    });

    testWidgets('isAnimating returns to false once the journey ends', (
      tester,
    ) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_book(controller: controller));

      final journey = _track(controller.goToPage(3));
      await tester.pumpAndSettle();

      expect(controller.isAnimating, isFalse);
      expect(journey.didComplete(), isTrue);
    });
  });

  group('FlipBookController attach', () {
    testWidgets('reports the page count from the widget', (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_book(controller: controller, pageCount: 12));

      expect(controller.pageCount, 12);
    });

    testWidgets('clamps an out-of-range initialPage', (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _book(controller: controller, pageCount: 4, initialPage: 99),
      );

      expect(controller.currentPage, 3);
    });
  });
}
