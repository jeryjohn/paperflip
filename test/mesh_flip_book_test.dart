import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flip_book/flip_book.dart';

Widget _book({
  FlipBookController? controller,
  int pageCount = 8,
  Size size = const Size(300, 400),
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: MeshFlipBook(
            pageCount: pageCount,
            controller: controller,
            pageBuilder: (context, index, constraints) => ColoredBox(
              color: index.isEven ? Colors.white : Colors.amber,
              child: Center(child: Text('Page ${index + 1}')),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the current page as a live widget at rest',
      (tester) async {
    await tester.pumpWidget(_book());
    await tester.pumpAndSettle();
    // The live page and the capture host both mount page 1.
    expect(find.text('Page 1'), findsWidgets);
  });

  testWidgets('a drag turns the page', (tester) async {
    final controller = FlipBookController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_book(controller: controller));
    await tester.pumpAndSettle();
    expect(controller.currentPage, 0);

    // Drag left, well past the commit threshold.
    await tester.drag(find.byType(MeshFlipBook), const Offset(-260, 0));
    await tester.pumpAndSettle();

    expect(controller.currentPage, 1);
  });

  testWidgets('a short drag cancels back to the same page', (tester) async {
    final controller = FlipBookController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_book(controller: controller));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MeshFlipBook)),
    );
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.currentPage, 0);
  });

  testWidgets('a drag never leaves the sheet resting mid-turn', (tester) async {
    final controller = FlipBookController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_book(controller: controller));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MeshFlipBook)),
    );
    await gesture.moveBy(const Offset(-150, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.isAnimating, isFalse);
  });

  testWidgets('the controller flips programmatically', (tester) async {
    final controller = FlipBookController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_book(controller: controller));
    await tester.pumpAndSettle();

    controller.flipNext();
    await tester.pumpAndSettle();
    expect(controller.currentPage, 1);

    controller.flipPrev();
    await tester.pumpAndSettle();
    expect(controller.currentPage, 0);
  });

  testWidgets('repeated flips stack rather than collapsing', (tester) async {
    final controller = FlipBookController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_book(controller: controller));
    await tester.pumpAndSettle();

    controller.flipNext();
    controller.flipNext();
    controller.flipNext();
    await tester.pumpAndSettle();

    expect(controller.currentPage, 3);
  });

  testWidgets('goToPage resolves and lands on the right page', (tester) async {
    final controller = FlipBookController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_book(controller: controller));
    await tester.pumpAndSettle();

    var done = false;
    // Deliberately not awaited: if the journey future never resolves the test
    // must fail on the flag, not hang forever.
    unawaited(controller.goToPage(5).then((_) => done = true));
    await tester.pumpAndSettle();

    expect(controller.currentPage, 5);
    expect(done, isTrue);
  });

  testWidgets('it does not flip past the ends', (tester) async {
    final controller = FlipBookController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_book(controller: controller, pageCount: 2));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(MeshFlipBook), const Offset(260, 0));
    await tester.pumpAndSettle();
    expect(controller.currentPage, 0);

    await tester.drag(find.byType(MeshFlipBook), const Offset(-260, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(MeshFlipBook), const Offset(-260, 0));
    await tester.pumpAndSettle();
    expect(controller.currentPage, 1);
  });

  testWidgets('tearing down mid-flip does not throw', (tester) async {
    final controller = FlipBookController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_book(controller: controller));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MeshFlipBook)),
    );
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump(const Duration(milliseconds: 16));

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a resize does not throw', (tester) async {
    await tester.pumpWidget(_book(size: const Size(300, 400)));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_book(size: const Size(420, 300)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
