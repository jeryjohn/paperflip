import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:flip_book/src/flip_book_controller.dart';
import 'package:flip_book/src/flip_book_widget.dart';
import 'package:flip_book/src/flip_settings.dart';

/// A [FlipBookWidget] that renders pages from a PDF document using `pdfrx`.
class FlipBookPdf extends StatefulWidget {
  const FlipBookPdf({
    super.key,
    required this.source,
    this.controller,
    this.initialPage = 0,
    this.flip = const FlipSettings(),
    @Deprecated('Use flip: FlipSettings(duration: ...). Removed in 0.3.0.')
    this.flipDuration,
    @Deprecated('No longer used; a drag anywhere flips. Removed in 0.3.0.')
    this.hotZoneSize = 60.0,
    this.showPageIndicator = false,
    this.backgroundColor = const Color(0xFFE8E4DC),
    this.spineColor = const Color(0xFFBBB5A8),
    this.pageBackColor = const Color(0xFFF0EEE8),
    this.loadingBuilder,
    this.errorBuilder,
    this.onDocumentLoaded,
  });

  final PdfDocumentRef source;

  final FlipBookController? controller;

  final int initialPage;

  final FlipSettings flip;

  @Deprecated('Use flip: FlipSettings(duration: ...). Removed in 0.3.0.')
  final Duration? flipDuration;

  @Deprecated('No longer used; a drag anywhere flips. Removed in 0.3.0.')
  final double hotZoneSize;

  /// Disabled by default so nothing appears underneath the PDF.
  final bool showPageIndicator;

  final Color backgroundColor;

  final Color spineColor;

  final Color pageBackColor;

  final WidgetBuilder? loadingBuilder;

  final Widget Function(BuildContext, Object error)? errorBuilder;

  final void Function(int pageCount)? onDocumentLoaded;

  @override
  State<FlipBookPdf> createState() => _FlipBookPdfState();
}

class _FlipBookPdfState extends State<FlipBookPdf> {
  PdfDocument? _document;
  Object? _error;

  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDocument());
  }

  @override
  void didUpdateWidget(covariant FlipBookPdf old) {
    super.didUpdateWidget(old);

    if (old.source != widget.source) {
      unawaited(_loadDocument());
    }
  }

  @override
  void dispose() {
    final document = _document;
    _document = null;

    if (document != null) {
      unawaited(document.dispose());
    }

    super.dispose();
  }

  Future<void> _loadDocument() async {
    final generation = ++_loadGeneration;

    final previous = _document;

    setState(() {
      _document = null;
      _error = null;
    });

    if (previous != null) {
      unawaited(previous.dispose());
    }

    try {
      final doc = await widget.source.loadDocument(
        (_, [__]) {},
      );

      if (!mounted || generation != _loadGeneration) {
        unawaited(doc.dispose());
        return;
      }

      setState(() {
        _document = doc;
      });

      widget.onDocumentLoaded?.call(
        doc.pages.length,
      );

      unawaited(
        doc.loadPagesProgressively(),
      );
    } catch (e) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }

      setState(() {
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.errorBuilder?.call(
            context,
            _error!,
          ) ??
          Center(
            child: Text(
              'Failed to load PDF:\n$_error',
              style: const TextStyle(
                color: Color(0xFFCC0000),
              ),
              textAlign: TextAlign.center,
            ),
          );
    }

    if (_document == null) {
      return widget.loadingBuilder?.call(
            context,
          ) ??
          const Center(
            child: _DefaultLoadingIndicator(),
          );
    }

    final document = _document!;
    final pageCount = document.pages.length;

    return Center(
      child: FlipBookWidget(
        pageCount: pageCount,
        controller: widget.controller,
        initialPage: widget.initialPage,
        flip: widget.flipDuration == null
            ? widget.flip
            : widget.flip.copyWith(
                duration: widget.flipDuration,
              ),
        showPageIndicator: false,
        backgroundColor: widget.backgroundColor,
        spineColor: widget.spineColor,
        pageBackColor: widget.pageBackColor,
        pageBuilder: (
          context,
          index,
          constraints,
        ) {
          return _PdfPageContent(
            document: document,
            pageIndex: index,
            constraints: constraints,
          );
        },
      ),
    );
  }
}

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
    if (pageIndex >= document.pages.length) {
      return const SizedBox.expand();
    }

    return SizedBox(
      width: constraints.maxWidth,
      height: constraints.maxHeight,
      child: PdfPageView(
        document: document,
        pageNumber: pageIndex + 1,
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
        style: TextStyle(
          color: Color(0xFF888888),
        ),
      ),
    );
  }
}