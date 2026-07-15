import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:flip_book/src/flip_book_controller.dart';
import 'package:flip_book/src/flip_book_widget.dart';

/// A [FlipBookWidget] that renders pages from a PDF document using `pdfrx`.
///
/// ```dart
/// FlipBookPdf(
///   source: PdfDocumentRef.file('/path/to/document.pdf'),
///   controller: _controller,
/// );
/// ```
///
/// Page images are rendered on demand and cached by [PdfPageView] internally.
/// The widget inherits all flip mechanics from [FlipBookWidget].
class FlipBookPdf extends StatefulWidget {
  const FlipBookPdf({
    super.key,
    required this.source,
    this.controller,
    this.initialPage = 0,
    this.flipDuration = const Duration(milliseconds: 600),
    this.hotZoneSize = 60.0,
    this.showPageIndicator = true,
    this.backgroundColor = const Color(0xFFE8E4DC),
    this.spineColor = const Color(0xFFBBB5A8),
    this.pageBackColor = const Color(0xFFF0EEE8),
    this.loadingBuilder,
    this.errorBuilder,
  });

  /// The PDF document source — file, asset, network, or data bytes.
  ///
  /// Construct with:
  /// ```dart
  /// PdfDocumentRef.file('/path/to/file.pdf')
  /// PdfDocumentRef.asset('assets/document.pdf')
  /// PdfDocumentRef.uri(Uri.parse('https://example.com/doc.pdf'))
  /// PdfDocumentRef.data(bytes)
  /// ```
  final PdfDocumentRef source;

  /// Optional controller for programmatic control.
  final FlipBookController? controller;

  /// The page displayed on first build (zero-based).
  final int initialPage;

  /// Duration of a single page-flip animation.
  final Duration flipDuration;

  /// Size in logical pixels of each hot-corner trigger zone.
  final double hotZoneSize;

  /// Whether to show the page number indicator at the bottom.
  final bool showPageIndicator;

  /// Background colour of the book widget.
  final Color backgroundColor;

  /// Colour of the centre spine divider in landscape mode.
  final Color spineColor;

  /// Colour shown on the back face of a curling page.
  final Color pageBackColor;

  /// Optional builder shown while the PDF is loading.
  final WidgetBuilder? loadingBuilder;

  /// Optional builder shown when the PDF fails to load.
  final Widget Function(BuildContext, Object error)? errorBuilder;

  @override
  State<FlipBookPdf> createState() => _FlipBookPdfState();
}

class _FlipBookPdfState extends State<FlipBookPdf> {
  PdfDocument? _document;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  @override
  void didUpdateWidget(covariant FlipBookPdf old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      _loadDocument();
    }
  }

  Future<void> _loadDocument() async {
    setState(() {
      _document = null;
      _error = null;
    });
    try {
      final doc = await widget.source.loadDocument((_, [__]) {});
      if (mounted) setState(() => _document = doc);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.errorBuilder?.call(context, _error!) ??
          Center(
            child: Text(
              'Failed to load PDF:\n$_error',
              style: const TextStyle(color: Color(0xFFCC0000)),
              textAlign: TextAlign.center,
            ),
          );
    }

    if (_document == null) {
      return widget.loadingBuilder?.call(context) ??
          const Center(child: _DefaultLoadingIndicator());
    }

    final pageCount = _document!.pages.length;

    return FlipBookWidget(
      pageCount: pageCount,
      controller: widget.controller,
      initialPage: widget.initialPage,
      flipDuration: widget.flipDuration,
      hotZoneSize: widget.hotZoneSize,
      showPageIndicator: widget.showPageIndicator,
      backgroundColor: widget.backgroundColor,
      spineColor: widget.spineColor,
      pageBackColor: widget.pageBackColor,
      pageBuilder: (context, index, constraints) {
        return _PdfPageContent(
          document: _document!,
          pageIndex: index,
          constraints: constraints,
        );
      },
    );
  }
}

/// Renders a single PDF page using [PdfPageView].
class _PdfPageContent extends StatelessWidget {
  const _PdfPageContent({
    required this.document,
    required this.pageIndex,
    required this.constraints,
  });

  final PdfDocument document;
  final int pageIndex;
  final BoxConstraints constraints;

  @override
  Widget build(BuildContext context) {
    if (pageIndex >= document.pages.length) return const SizedBox.expand();

    return SizedBox(
      width: constraints.maxWidth,
      height: constraints.maxHeight,
      child: PdfPageView(
        document: document,
        pageNumber: pageIndex + 1, // pdfrx uses 1-based page numbers
        alignment: Alignment.center,
      ),
    );
  }
}

class _DefaultLoadingIndicator extends StatelessWidget {
  const _DefaultLoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Loading…',
        style: TextStyle(color: Color(0xFF888888)),
      ),
    );
  }
}
