// Compile-checks the API surface the README documents. If the README and the
// code drift apart, this stops compiling.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:flip_book/flip_book.dart';

void main() {
  test('README examples compile', () {
    final controller = FlipBookController();
    final epub = EpubController(
      settings: const EpubReaderSettings(fontSize: 18, lineHeight: 1.6),
    );

    // Facade
    const FlipBook.epub(
      source: EpubSource.network('https://example.com/book.epub'),
    );
    FlipBook.pdf(source: PdfDocumentRefAsset('assets/doc.pdf'));
    FlipBook.custom(
      pageCount: 20,
      pageBuilder: (c, i, constraints) => const SizedBox.shrink(),
    );

    // Sources
    const EpubSource.network('u', headers: {'a': 'b'});
    const EpubSource.file('/tmp/a.epub');
    const EpubSource.asset('assets/a.epub');

    // EPUB controller surface
    epub.zoomIn();
    epub.zoomOut();
    epub.setFontSize(22);
    epub.setLineHeight(1.8);
    epub.setMargin(24);
    epub.setTheme(EpubTheme.sepia);
    epub.goToChapter(3);
    epub.nextChapter();
    epub.previousChapter();
    expect(epub.totalPages, isA<int>());
    expect(epub.progress, isA<double>());
    expect(epub.locator, isA<EpubLocator>());
    expect(epub.toc, isA<List<EpubTocEntry>>());

    // Flip controller surface
    controller.flipNext();
    controller.flipPrev();
    controller.nextPage();
    controller.previousPage();
    controller.goToPage(12);
    controller.goToPage(12, animate: false);
    controller.setFlipEnabled(false);
    controller.setFlipDuration(const Duration(milliseconds: 300));
    controller.clearFlipOverrides();
    expect(controller.currentPage, isA<int>());
    expect(controller.pageCount, isA<int>());
    expect(controller.isAnimating, isA<bool>());

    // FlipSettings surface
    const FlipSettings(
      enabled: true,
      duration: Duration(milliseconds: 450),
      curve: Curves.easeOut,
      settleCurve: Curves.easeOut,
      direction: FlipDirection.horizontal,
      showShadow: true,
      showBackFace: true,
    );

    // Lower tiers stay public
    FlipBookWidget(
      pageCount: 20,
      pageBuilder: (c, i, constraints) => const SizedBox.shrink(),
    );
    FlipBookPdf(
      source: PdfDocumentRefFile('/path/to/file.pdf'),
      onDocumentLoaded: (pageCount) {},
    );
    const FlipBookReader(title: 'My Document', pdfAssetPath: 'assets/d.pdf');
    const FlipBookEpub(source: EpubSource.network('https://e.com/b.epub'));

    controller.dispose();
    epub.dispose();
  });
}
