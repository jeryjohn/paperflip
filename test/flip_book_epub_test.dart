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

/// Pumps until the EPUB has finished its measurement pass, or gives up.
///
/// Pagination runs one document per frame, so this needs many pumps rather
/// than pumpAndSettle (which would also fight the flip animation).
Future<bool> _settlePagination(
  WidgetTester tester,
  EpubController epub, {
  int maxFrames = 400,
}) async {
  for (var i = 0; i < maxFrames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (epub.pagination?.isComplete ?? false) return true;
  }
  return epub.pagination?.isComplete ?? false;
}

Widget _app({
  required Uint8List bytes,
  required FlipBookController flip,
  required EpubController epub,
  Size size = const Size(400, 700),
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
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
}

void main() {
  final bytes = _fixture('pg28885.epub');

  group('FlipBookEpub', () {
    testWidgets('loads a book and paginates it', (tester) async {
      if (bytes == null) {
        markTestSkipped('fixture pg28885.epub not present');
        return;
      }
      final flip = FlipBookController();
      final epub = EpubController();
      addTearDown(flip.dispose);
      addTearDown(epub.dispose);

      await tester.pumpWidget(_app(bytes: bytes, flip: flip, epub: epub));
      final done = await _settlePagination(tester, epub);

      expect(done, isTrue, reason: 'measurement pass did not complete');
      expect(epub.document, isNotNull);
      expect(epub.document!.spine, isNotEmpty);
      expect(
        epub.totalPages,
        greaterThan(epub.document!.spine.length),
        reason: 'documents should span more than one page each on average',
      );
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
    });

    testWidgets('turning a page updates the locator', (tester) async {
      if (bytes == null) {
        markTestSkipped('fixture pg28885.epub not present');
        return;
      }
      final flip = FlipBookController();
      final epub = EpubController();
      addTearDown(flip.dispose);
      addTearDown(epub.dispose);

      await tester.pumpWidget(_app(bytes: bytes, flip: flip, epub: epub));
      await _settlePagination(tester, epub);

      final startLocator = epub.locator;
      await flip.goToPage(epub.totalPages ~/ 2, animate: false);
      await tester.pump();
      await tester.pump();

      expect(epub.locator, isNot(startLocator));
      expect(epub.progress, greaterThan(0));
      await tester.pumpAndSettle();
    });

    testWidgets('increasing the font size reflows into more pages', (
      tester,
    ) async {
      if (bytes == null) {
        markTestSkipped('fixture pg28885.epub not present');
        return;
      }
      final flip = FlipBookController();
      final epub = EpubController(
        settings: const EpubReaderSettings(fontSize: 14),
      );
      addTearDown(flip.dispose);
      addTearDown(epub.dispose);

      await tester.pumpWidget(_app(bytes: bytes, flip: flip, epub: epub));
      await _settlePagination(tester, epub);
      final before = epub.totalPages;
      expect(before, greaterThan(0));

      epub.setFontSize(26);
      await tester.pump();
      final done = await _settlePagination(tester, epub);

      expect(done, isTrue, reason: 're-pagination did not complete');
      expect(
        epub.totalPages,
        greaterThan(before),
        reason: 'larger text must produce more pages, not a larger page',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
    });

    testWidgets('reading position is preserved across a reflow', (
      tester,
    ) async {
      if (bytes == null) {
        markTestSkipped('fixture pg28885.epub not present');
        return;
      }
      final flip = FlipBookController();
      final epub = EpubController(
        settings: const EpubReaderSettings(fontSize: 14),
      );
      addTearDown(flip.dispose);
      addTearDown(epub.dispose);

      await tester.pumpWidget(_app(bytes: bytes, flip: flip, epub: epub));
      await _settlePagination(tester, epub);

      // Move to the middle of the book.
      await flip.goToPage(epub.totalPages ~/ 2, animate: false);
      await tester.pump();
      await tester.pump();
      final spineBefore = epub.locator.spineIndex;

      epub.setFontSize(22);
      await tester.pump();
      await _settlePagination(tester, epub);
      // Give the post-frame restore a chance to run.
      await tester.pump();
      await tester.pump();

      expect(
        epub.locator.spineIndex,
        spineBefore,
        reason: 'the reader should still be in the same document',
      );
      await tester.pumpAndSettle();
    });

    testWidgets('a narrower viewport re-paginates', (tester) async {
      if (bytes == null) {
        markTestSkipped('fixture pg28885.epub not present');
        return;
      }
      final flip = FlipBookController();
      final epub = EpubController();
      addTearDown(flip.dispose);
      addTearDown(epub.dispose);

      await tester.pumpWidget(
        _app(bytes: bytes, flip: flip, epub: epub, size: const Size(600, 800)),
      );
      await _settlePagination(tester, epub);
      final wide = epub.totalPages;

      await tester.pumpWidget(
        _app(bytes: bytes, flip: flip, epub: epub, size: const Size(320, 500)),
      );
      final done = await _settlePagination(tester, epub);

      expect(done, isTrue);
      expect(
        epub.totalPages,
        greaterThan(wide),
        reason: 'a smaller viewport holds less text per page',
      );
      await tester.pumpAndSettle();
    });

    testWidgets('chapter navigation jumps to that document', (tester) async {
      if (bytes == null) {
        markTestSkipped('fixture pg28885.epub not present');
        return;
      }
      final flip = FlipBookController();
      final epub = EpubController();
      addTearDown(flip.dispose);
      addTearDown(epub.dispose);

      await tester.pumpWidget(_app(bytes: bytes, flip: flip, epub: epub));
      await _settlePagination(tester, epub);

      final target = epub.document!.spine.length - 1;
      epub.goToSpineIndex(target);
      await tester.pump();
      await tester.pump();

      expect(epub.locator.spineIndex, target);
      await tester.pumpAndSettle();
    });

    testWidgets('a bad source surfaces an error instead of throwing', (
      tester,
    ) async {
      final flip = FlipBookController();
      addTearDown(flip.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlipBook.epub(
              source: EpubSource.data(Uint8List.fromList(List.filled(32, 1))),
              controller: flip,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Could not open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
