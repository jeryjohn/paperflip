import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flip_book/flip_book.dart';

final _boundaryKey = GlobalKey();

Widget _book(FlipBookController controller) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: _boundaryKey,
            child: SizedBox(
              width: 300,
              height: 400,
              child: MeshFlipBook(
                pageCount: 6,
                controller: controller,
                showShadow: false,
                pageBuilder: (context, index, constraints) => ColoredBox(
                  // Strongly distinct pages, so a curl that samples the wrong
                  // one is obvious in the pixel counts.
                  color: index.isEven
                      ? const Color(0xFFFFFFFF)
                      : const Color(0xFF102030),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 120,
                        color: index.isEven
                            ? const Color(0xFF102030)
                            : const Color(0xFFFFFFFF),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

Future<List<int>> _pixels(WidgetTester tester) async {
  // `toImage` and `toByteData` hand work to the raster thread. Inside
  // `testWidgets`' fake async zone those futures never complete and the test
  // hangs rather than failing, so the capture must run in a real zone.
  final pixels = await tester.runAsync(() async {
    final boundary = _boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List().toList();
    } finally {
      image.dispose();
    }
  });
  return pixels!;
}

/// Lets the widget's own page captures complete.
///
/// Capturing a page is asynchronous and needs a real zone, so a few real
/// frames have to elapse before any texture exists to draw.
Future<void> _settleCaptures(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

int _differingPixels(List<int> a, List<int> b) {
  var count = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) {
      count++;
    }
  }
  return count;
}

void main() {
  testWidgets('the curl actually renders: mid-drag pixels differ from rest',
      (tester) async {
    final controller = FlipBookController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_book(controller));
    await tester.pumpAndSettle();
    await _settleCaptures(tester);

    final atRest = await _pixels(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MeshFlipBook)),
    );
    // Drag roughly halfway, where the sheet is most curled.
    await gesture.moveBy(const Offset(-150, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    final midDrag = await _pixels(tester);
    final changed = _differingPixels(atRest, midDrag);
    final total = atRest.length ~/ 4;

    // A real textured mesh repaints a large fraction of the page. The old
    // renderer would also change pixels, so this is a floor, not a proof of
    // correctness -- the geometry tests carry that.
    expect(
      changed / total,
      greaterThan(0.15),
      reason: 'mid-drag frame is nearly identical to rest: the mesh is '
          'probably not drawing at all ($changed of $total pixels changed)',
    );

    await gesture.up();
    await tester.pumpAndSettle();

    // And it must come all the way back to a flat, live page.
    final afterCancelOrCommit = await _pixels(tester);
    expect(
      _differingPixels(afterCancelOrCommit, midDrag) / total,
      greaterThan(0.05),
      reason: 'the sheet appears stuck mid-turn after release',
    );
  });

  testWidgets('a landed page is pixel-identical to the live page',
      (tester) async {
    final controller = FlipBookController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_book(controller));
    await tester.pumpAndSettle();
    await _settleCaptures(tester);

    // Jump to page 2 without any curl, to get the reference image.
    controller.nextPage();
    await tester.pumpAndSettle();
    expect(controller.currentPage, 1);
    final reference = await _pixels(tester);

    // Now go back and turn to the same page with a full animated flip.
    controller.previousPage();
    await tester.pumpAndSettle();
    controller.flipNext();
    await tester.pumpAndSettle();
    expect(controller.currentPage, 1);
    final afterFlip = await _pixels(tester);

    // The whole point of the lighting going to exactly 1.0 at rest: once the
    // sheet lands there must be no residue of the curl.
    expect(
      _differingPixels(reference, afterFlip),
      0,
      reason: 'the landed page differs from the live page -- the flip surface '
          'is leaving something behind',
    );
  });
}
