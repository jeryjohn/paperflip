import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:flip_book/src/epub/epub_controller.dart';
import 'package:flip_book/src/epub/epub_reader_settings.dart';
import 'package:flip_book/src/epub/epub_source.dart';
import 'package:flip_book/src/epub/flip_book_epub.dart';
import 'package:flip_book/src/flip_book_controller.dart';
import 'package:flip_book/src/flip_book_pdf.dart';
import 'package:flip_book/src/flip_book_widget.dart';
import 'package:flip_book/src/flip_settings.dart';
import 'package:flip_book/src/mesh_flip_book.dart';

enum _FlipBookMode { pdf, epub, custom }

/// The entry point for building a book, whatever the content is.
///
/// ```dart
/// FlipBook.epub(
///   source: EpubSource.network('https://example.com/book.epub'),
/// )
///
/// FlipBook.pdf(
///   source: PdfDocumentRefAsset('assets/doc.pdf'),
/// )
///
/// FlipBook.custom(
///   pageCount: 20,
///   pageBuilder: (context, index, constraints) => MyPage(index),
/// )
/// ```
///
/// Each constructor delegates to the widget for that content type
/// ([FlipBookEpub], [FlipBookPdf], [MeshFlipBook]), which remain public and
/// can be used directly.
class FlipBook extends StatelessWidget {
  /// A PDF book. PDFs are fixed-layout: there is no font reflow.
  const FlipBook.pdf({
    super.key,
    required PdfDocumentRef source,
    this.controller,
    this.flip = const FlipSettings(),
    this.initialPage = 0,
    this.showPageIndicator = true,
    this.backgroundColor = const Color(0xFFE8E4DC),
    this.spineColor = const Color(0xFFBBB5A8),
    this.pageBackColor = const Color(0xFFF0EEE8),
    this.loadingBuilder,
    this.errorBuilder,
    this.onPageCountAvailable,
    this.useVolumeKeys = false,
  }) : _mode = _FlipBookMode.pdf,
       _pdfSource = source,
       _epubSource = null,
       _pageCount = null,
       _pageBuilder = null,
       epubController = null,
       reader = const EpubReaderSettings();

  /// A reflowable EPUB.
  ///
  /// Changing the reading size re-paginates the book rather than scaling the
  /// page, and the reader's place is preserved across the reflow.
  const FlipBook.epub({
    super.key,
    required EpubSource source,
    this.controller,
    this.epubController,
    this.flip = const FlipSettings(),
    this.reader = const EpubReaderSettings(),
    this.showPageIndicator = true,
    this.loadingBuilder,
    this.errorBuilder,
    this.useVolumeKeys = false,
  }) : _mode = _FlipBookMode.epub,
       _epubSource = source,
       _pdfSource = null,
       _pageCount = null,
       _pageBuilder = null,
       initialPage = 0,
       backgroundColor = const Color(0xFFE8E4DC),
       spineColor = const Color(0xFFBBB5A8),
       pageBackColor = const Color(0xFFF0EEE8),
       onPageCountAvailable = null;

  /// A book whose pages are arbitrary Flutter widgets.
  const FlipBook.custom({
    super.key,
    required int pageCount,
    required FlipPageBuilder pageBuilder,
    this.controller,
    this.flip = const FlipSettings(),
    this.initialPage = 0,
    this.showPageIndicator = true,
    this.backgroundColor = const Color(0xFFE8E4DC),
    this.spineColor = const Color(0xFFBBB5A8),
    this.pageBackColor = const Color(0xFFF0EEE8),
    this.useVolumeKeys = false,
  }) : _mode = _FlipBookMode.custom,
       _pageCount = pageCount,
       _pageBuilder = pageBuilder,
       _pdfSource = null,
       _epubSource = null,
       epubController = null,
       reader = const EpubReaderSettings(),
       loadingBuilder = null,
       errorBuilder = null,
       onPageCountAvailable = null;


  final _FlipBookMode _mode;
  final PdfDocumentRef? _pdfSource;
  final EpubSource? _epubSource;
  final int? _pageCount;
  final FlipPageBuilder? _pageBuilder;

  /// Page navigation and flip control.
  final FlipBookController? controller;

  /// EPUB typography, chapters and reading position. EPUB only.
  final EpubController? epubController;

  /// Flip animation configuration.
  final FlipSettings flip;

  /// EPUB typography and layout. EPUB only.
  final EpubReaderSettings reader;

  /// First page shown. Not used for EPUB, where position is a locator.
  final int initialPage;

  /// Whether to show the page-number overlay.
  final bool showPageIndicator;

  /// Background behind the book.
  final Color backgroundColor;

  /// Centre spine colour in landscape.
  final Color spineColor;

  /// Colour of a page's back face.
  final Color pageBackColor;

  /// Shown while the document loads. PDF and EPUB only.
  final Widget Function(BuildContext context)? loadingBuilder;

  /// Shown when the document fails to load. PDF and EPUB only.
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  /// Reports the page count once a PDF has opened.
  final void Function(int pageCount)? onPageCountAvailable;

  /// Whether physical volume buttons navigate pages on supported devices (Android).
  final bool useVolumeKeys;

  @override
  Widget build(BuildContext context) {
    switch (_mode) {
      case _FlipBookMode.pdf:
        return FlipBookPdf(
          source: _pdfSource!,
          controller: controller,
          flip: flip,
          initialPage: initialPage,
          showPageIndicator: showPageIndicator,
          backgroundColor: backgroundColor,
          spineColor: spineColor,
          pageBackColor: pageBackColor,
          loadingBuilder: loadingBuilder,
          errorBuilder: errorBuilder,
          onDocumentLoaded: onPageCountAvailable,
          useVolumeKeys: useVolumeKeys,
        );

      case _FlipBookMode.epub:
        return FlipBookEpub(
          source: _epubSource!,
          controller: controller,
          epubController: epubController,
          flip: flip,
          reader: epubController?.settings ?? reader,
          showPageIndicator: showPageIndicator,
          loadingBuilder: loadingBuilder,
          errorBuilder: errorBuilder,
          useVolumeKeys: useVolumeKeys,
        );

      case _FlipBookMode.custom:
        final flipBook = MeshFlipBook(
          pageCount: _pageCount!,
          pageBuilder: _pageBuilder!,
          controller: controller,
          flip: flip,
          initialPage: initialPage,
          backgroundColor: backgroundColor,
          pageBackColor: pageBackColor,
          useVolumeKeys: useVolumeKeys,
        );


        if (!showPageIndicator || controller == null) {
          return flipBook;
        }

        return Stack(
          children: [
            Positioned.fill(child: flipBook),
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: IgnorePointer(
                child: Center(
                  child: ListenableBuilder(
                    listenable: controller!,
                    builder: (context, _) => DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xAA000000),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Text(
                          '${controller!.currentPage + 1} / $_pageCount',
                          style: const TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }
}
