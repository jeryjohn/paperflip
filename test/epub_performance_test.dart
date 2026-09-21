import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flip_book/flip_book.dart';

const _fixtureDir = String.fromEnvironment(
  'EPUB_FIXTURES',
  defaultValue: 'test/fixtures',
);

Uint8List? _fixture(String name) {
  final file = File('$_fixtureDir/$name');
  return file.existsSync() ? file.readAsBytesSync() : null;
}

void main() {
  final bytes = _fixture('pg28885.epub');

  group('EPUB page building cost', () {
    testWidgets('turning pages does not re-parse the chapter each frame', (
      tester,
    ) async {
      if (bytes == null) {
        markTestSkipped('fixture pg28885.epub not present');
        return;
      }

      final flip = FlipBookController();
      final epub = EpubController();
      addTearDown(flip.dispose);
      addTearDown(epub.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 700,
              child: FlipBook.epub(
                source: EpubSource.data(bytes),
                controller: flip,
                epubController: epub,
                showPageIndicator: false,
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 400; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (epub.pagination?.isComplete ?? false) break;
      }
      expect(epub.pagination?.isComplete, isTrue);

      // The flip engine rebuilds its layers every animation frame. Pages must
      // be served from prepared content, not rebuilt from HTML each time.
      EpubRenderer.debugBuildCount = 0;
      for (var i = 0; i < 5; i++) {
        flip.flipNext();
        await tester.pumpAndSettle();
      }

      // Before chapter subtrees were cached this was 100 -- roughly 20 full
      // chapter rebuilds per page turn.
      expect(
        EpubRenderer.debugBuildCount,
        lessThanOrEqualTo(30),
        reason: 'chapter content is being rebuilt per animation frame',
      );
    });

    testWidgets('only a bounded number of chapters stay live', (tester) async {
      if (bytes == null) {
        markTestSkipped('fixture pg28885.epub not present');
        return;
      }

      final flip = FlipBookController();
      final epub = EpubController();
      addTearDown(flip.dispose);
      addTearDown(epub.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 700,
              child: FlipBook.epub(
                source: EpubSource.data(bytes),
                controller: flip,
                epubController: epub,
                showPageIndicator: false,
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 400; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (epub.pagination?.isComplete ?? false) break;
      }

      // Walk across the book; the live chapter count must not grow with it.
      for (final page in [0, 100, 200, 300, epub.totalPages - 1]) {
        await flip.goToPage(page, animate: false);
        await tester.pumpAndSettle();
        expect(
          find.byType(EpubRenderer).evaluate().length,
          lessThanOrEqualTo(4),
          reason: 'too many chapter trees alive at page $page',
        );
      }
    });
  });
}
