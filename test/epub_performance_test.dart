import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:paperflip/paperflip.dart';

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

      final flip = PaperFlipController();
      final epub = EpubController();
      addTearDown(flip.dispose);
      addTearDown(epub.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 700,
              child: PaperFlip.epub(
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

      final flip = PaperFlipController();
      final epub = EpubController();
      addTearDown(flip.dispose);
      addTearDown(epub.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 700,
              child: PaperFlip.epub(
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

  group('EpubDataSource construction benchmark', () {
    test('measures source construction cost across 1MB, 5MB, and 10MB arrays', () {
      final sizes = [
        ('1 MB', 1 * 1024 * 1024),
        ('5 MB', 5 * 1024 * 1024),
        ('10 MB', 10 * 1024 * 1024),
      ];

      for (final (label, size) in sizes) {
        // Deterministic pseudo-random bytes
        final bytes = Uint8List(size);
        for (var i = 0; i < size; i++) {
          bytes[i] = (i * 31 + 17) & 0xFF;
        }

        // Warmup
        for (var i = 0; i < 5; i++) {
          EpubSource.data(bytes);
          EpubSource.data(bytes, id: 'warmup');
        }

        // Timed runs without explicit ID (Snapshot + Digest)
        final timesWithoutId = <double>[];
        for (var i = 0; i < 15; i++) {
          final sw = Stopwatch()..start();
          final src = EpubSource.data(bytes);
          sw.stop();
          expect(src.cacheKey, isNotEmpty);
          timesWithoutId.add(sw.elapsedMicroseconds / 1000.0);
        }
        timesWithoutId.sort();
        final medianWithoutId = timesWithoutId[timesWithoutId.length ~/ 2];
        final meanWithoutId =
            timesWithoutId.reduce((a, b) => a + b) / timesWithoutId.length;

        // Timed runs with explicit ID (Snapshot only, digest bypassed)
        final timesWithId = <double>[];
        for (var i = 0; i < 15; i++) {
          final sw = Stopwatch()..start();
          final src = EpubSource.data(bytes, id: 'v1');
          sw.stop();
          expect(src.cacheKey, isNotEmpty);
          timesWithId.add(sw.elapsedMicroseconds / 1000.0);
        }
        timesWithId.sort();
        final medianWithId = timesWithId[timesWithId.length ~/ 2];
        final meanWithId =
            timesWithId.reduce((a, b) => a + b) / timesWithId.length;

        debugPrint(
          '[Benchmark $label - $size bytes]\n'
          '  Without ID (Copy + Digest): min=${timesWithoutId.first.toStringAsFixed(2)}ms, '
          'median=${medianWithoutId.toStringAsFixed(2)}ms, '
          'mean=${meanWithoutId.toStringAsFixed(2)}ms, '
          'max=${timesWithoutId.last.toStringAsFixed(2)}ms\n'
          '  With ID (Copy only):        min=${timesWithId.first.toStringAsFixed(2)}ms, '
          'median=${medianWithId.toStringAsFixed(2)}ms, '
          'mean=${meanWithId.toStringAsFixed(2)}ms, '
          'max=${timesWithId.last.toStringAsFixed(2)}ms',
        );
      }
    });
  });
}
