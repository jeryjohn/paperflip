import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flip_book/flip_book.dart';

Widget _book({
  FlipBookController? controller,
  int pageCount = 10,
  int initialPage = 0,
  bool showPageIndicator = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: FlipBookWidget(
        pageCount: pageCount,
        initialPage: initialPage,
        controller: controller,
        showPageIndicator: showPageIndicator,
        pageBuilder: (context, index, constraints) => ColoredBox(
          color: Colors.white,
          child: Center(child: Text('Page $index')),
        ),
      ),
    ),
  );
}

void main() {
  group('FlipBookWidget rendering', () {
    testWidgets('renders the initial page', (tester) async {
      await tester.pumpWidget(_book(initialPage: 2));
      expect(find.text('Page 2'), findsOneWidget);
    });

    testWidgets('works without a controller', (tester) async {
      await tester.pumpWidget(_book());
      expect(find.text('Page 0'), findsOneWidget);
    });

    testWidgets('clamps an out-of-range initialPage', (tester) async {
      await tester.pumpWidget(_book(pageCount: 3, initialPage: 42));
      expect(find.text('Page 2'), findsOneWidget);
    });

    testWidgets('shows the page indicator when enabled', (tester) async {
      await tester.pumpWidget(_book(showPageIndicator: true));
      expect(find.textContaining('1'), findsWidgets);
    });
  });

  group('FlipBookWidget drag', () {
    testWidgets('a swipe left settles forward one page', (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_book(controller: controller));
      expect(controller.currentPage, 0);

      // Drag most of the way across the book and release.
      await tester.drag(find.byType(FlipBookWidget), const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(controller.currentPage, 1);
    });

    testWidgets('a swipe right from page 0 stays at page 0', (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_book(controller: controller));

      await tester.drag(find.byType(FlipBookWidget), const Offset(600, 0));
      await tester.pumpAndSettle();

      expect(controller.currentPage, 0);
    });

    testWidgets('a settled drag never leaves a partial turn', (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_book(controller: controller, initialPage: 3));

      // A small drag that should snap back rather than complete.
      await tester.drag(find.byType(FlipBookWidget), const Offset(-20, 0));
      await tester.pumpAndSettle();

      // Either snapped back to 3 or completed to 4 -- never mid-turn.
      expect(controller.currentPage, anyOf(3, 4));
      expect(controller.isAnimating, isFalse);
    });

    testWidgets('a drag mid-book can go backwards', (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_book(controller: controller, initialPage: 5));

      await tester.drag(find.byType(FlipBookWidget), const Offset(600, 0));
      await tester.pumpAndSettle();

      expect(controller.currentPage, 4);
    });
  });

  group('FlipBookWidget lifecycle', () {
    testWidgets('disposing the widget leaves the controller usable',
        (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_book(controller: controller));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // Must not throw after the widget is gone.
      controller.flipNext();
      expect(controller.currentPage, 0);
    });

    testWidgets('swapping the controller re-attaches', (tester) async {
      final first = FlipBookController();
      final second = FlipBookController();
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      await tester.pumpWidget(_book(controller: first, pageCount: 6));
      expect(first.pageCount, 6);

      await tester.pumpWidget(_book(controller: second, pageCount: 6));
      await tester.pumpAndSettle();
      expect(second.pageCount, 6);

      second.flipNext();
      await tester.pumpAndSettle();
      expect(second.currentPage, 1);
    });

    testWidgets('a growing pageCount reaches the controller', (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_book(controller: controller, pageCount: 5));
      expect(controller.pageCount, 5);

      // An EPUB re-paginating grows the count without changing the book.
      await tester.pumpWidget(_book(controller: controller, pageCount: 400));
      await tester.pump();
      expect(controller.pageCount, 400);

      // The stale count used to clamp this jump to page 4.
      await controller.goToPage(380, animate: false);
      await tester.pump();
      expect(controller.currentPage, 380);
    });

    testWidgets('a shrinking pageCount clamps the current page',
        (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _book(controller: controller, pageCount: 10, initialPage: 8),
      );
      expect(controller.currentPage, 8);

      await tester.pumpWidget(
        _book(controller: controller, pageCount: 4, initialPage: 8),
      );
      await tester.pumpAndSettle();

      expect(controller.pageCount, 4);
      expect(controller.currentPage, lessThan(4));
    });
  });
}
