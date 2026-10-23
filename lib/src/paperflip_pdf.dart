import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:paperflip/src/capture/widget_page_rasterizer.dart';
import 'package:paperflip/src/paperflip_controller.dart';
import 'package:paperflip/src/page_builder.dart';
import 'package:paperflip/src/flip_settings.dart';
import 'package:paperflip/src/mesh_paperflip.dart';

/// A PDF book viewer rendered using [MeshPaperFlip] and `pdfrx`.
class PaperFlipPdf extends StatefulWidget {
  const PaperFlipPdf({
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
    this.useVolumeKeys = false,
  });

  final PdfDocumentRef source;

  final PaperFlipController? controller;

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

  /// Whether physical volume buttons navigate pages on supported devices (Android).
  final bool useVolumeKeys;

  @override
  State<PaperFlipPdf> createState() => _PaperFlipPdfState();
}

class _PaperFlipPdfState extends State<PaperFlipPdf> {
  PdfDocument? _document;
  PdfPageImageCache? _imageCache;
  Object? _error;

  int _loadGeneration = 0;
  PaperFlipController? _internalController;
  int _lastPreloadedPage = -1;

  PaperFlipController get _effectiveController =>
      widget.controller ?? (_internalController ??= PaperFlipController());

  /// One builder for the lifetime of this state.
  ///
  /// [MeshPaperFlip] treats a new `pageBuilder` as new content: it cancels any
  /// turn in progress and throws away every captured page. An inline closure
  /// is a new object on every build, so any ancestor rebuild (PaperFlipReader
  /// calls setState after every page turn and when its controls auto-hide)
  /// was cancelling queued flips and forcing a full re-capture. A document
  /// change is signalled with `contentVersion` instead.
  late final FlipPageBuilder _pageBuilder = _buildPage;

  Widget _buildPage(
    BuildContext context,
    int index,
    BoxConstraints constraints,
  ) {
    final document = _document;
    final cache = _imageCache;
    if (document == null || cache == null) return const SizedBox.shrink();
    return PdfPageContent(
      document: document,
      pageIndex: index,
      constraints: constraints,
      cache: cache,
      backgroundColor: widget.backgroundColor,
    );
  }

  @override
  void initState() {
    super.initState();
    _effectiveController.addListener(_onControllerPageChange);
    unawaited(_loadDocument());
  }

  @override
  void didUpdateWidget(covariant PaperFlipPdf old) {
    super.didUpdateWidget(old);

    // Compare by key to avoid discarding loaded documents when callers
    // instantiate identical PdfDocumentRef objects during parent rebuilds.
    // If the previous attempt resulted in an error, allow rebuilds to re-trigger loading.
    if (old.source.key != widget.source.key ||
        (_error != null && _document == null)) {
      unawaited(_loadDocument());
    }

    if (old.controller != widget.controller) {
      final oldEffective = old.controller ?? _internalController;
      oldEffective?.removeListener(_onControllerPageChange);
      _effectiveController.addListener(_onControllerPageChange);
    }
  }

  @override
  void dispose() {
    final effective = widget.controller ?? _internalController;
    effective?.removeListener(_onControllerPageChange);
    _internalController?.dispose();
    _imageCache?.dispose();
    _imageCache = null;
    final document = _document;
    _document = null;

    if (document != null) {
      unawaited(document.dispose());
    }

    super.dispose();
  }

  void _onControllerPageChange() {
    final page = _effectiveController.currentPage;
    if (page != _lastPreloadedPage) {
      _lastPreloadedPage = page;
      _preloadForPage(page);
    }
  }

  void _preloadForPage(int page) {
    final cache = _imageCache;
    final doc = _document;
    if (cache == null || doc == null || doc.pages.isEmpty) return;

    for (final p in [page, page + 1, page - 1, page + 2]) {
      if (p >= 0 && p < doc.pages.length) {
        cache.preload(p);
      }
    }
  }

  Future<void> _loadDocument() async {
    final generation = ++_loadGeneration;

    final previous = _document;
    final previousCache = _imageCache;

    setState(() {
      _document = null;
      _imageCache = null;
      _error = null;
    });

    previousCache?.dispose();
    if (previous != null) {
      unawaited(previous.dispose());
    }

    try {
      final doc = await widget.source.loadDocument((_, [__]) {});

      if (!mounted || generation != _loadGeneration) {
        unawaited(doc.dispose());
        return;
      }

      final cache = PdfPageImageCache(document: doc);

      setState(() {
        _document = doc;
        _imageCache = cache;
      });

      widget.onDocumentLoaded?.call(doc.pages.length);

      unawaited(doc.loadPagesProgressively());
      _preloadForPage(widget.initialPage);
    } catch (e) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }

      setState(() {
        _error = e;
      });
    }
  }

  Widget _buildIndicator(int page, int pageCount) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xAA000000),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          '$page / $pageCount',
          style: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
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

    if (_document == null || _imageCache == null) {
      return widget.loadingBuilder?.call(context) ??
          const Center(child: _DefaultLoadingIndicator());
    }

    final document = _document!;
    final pageCount = document.pages.length;

    final effectiveController =
        widget.controller ??
        (widget.showPageIndicator
            ? (_internalController ??= PaperFlipController())
            : null);

    final paperFlip = MeshPaperFlip(
      pageCount: pageCount,
      controller: effectiveController,
      initialPage: widget.initialPage,
      flip: widget.flipDuration == null
          ? widget.flip
          : widget.flip.copyWith(duration: widget.flipDuration),
      backgroundColor: widget.backgroundColor,
      pageBackColor: widget.pageBackColor,
      useVolumeKeys: widget.useVolumeKeys,
      pageBuilder: _pageBuilder,
      contentVersion: _loadGeneration,
    );

    if (!widget.showPageIndicator || effectiveController == null) {
      return Center(child: paperFlip);
    }

    return Center(
      child: Stack(
        children: [
          Positioned.fill(child: paperFlip),
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: IgnorePointer(
              child: Center(
                child: ListenableBuilder(
                  listenable: effectiveController,
                  builder: (context, _) => _buildIndicator(
                    effectiveController.currentPage + 1,
                    pageCount,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Visible for deterministic testing of widget image handle ownership.
@visibleForTesting
class PdfPageContent extends StatefulWidget {
  const PdfPageContent({
    super.key,
    required this.document,
    required this.pageIndex,
    required this.constraints,
    required this.cache,
    required this.backgroundColor,
  });

  final PdfDocument document;
  final int pageIndex;
  final BoxConstraints constraints;
  final PdfPageImageCache cache;
  final Color backgroundColor;

  @override
  State<PdfPageContent> createState() => _PdfPageContentState();
}

class _PdfPageContentState extends State<PdfPageContent> {
  ui.Image? _image;
  bool _isLoading = false;
  int _activeRequestId = 0;

  @visibleForTesting
  ui.Image? get debugImage => _image;

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant PdfPageContent old) {
    super.didUpdateWidget(old);
    if (old.pageIndex != widget.pageIndex ||
        old.document != widget.document ||
        old.cache != widget.cache) {
      _activeRequestId++;
      _isLoading = false;
      _setImage(null);
      _resolveImage();
    } else if (old.constraints.biggest != widget.constraints.biggest) {
      _resolveImage();
    }
  }

  @override
  void dispose() {
    _activeRequestId++;
    final old = _image;
    _image = null;
    old?.dispose();
    super.dispose();
  }

  void _setImage(ui.Image? newImage) {
    if (_image == newImage) return;
    final old = _image;
    _image = newImage;
    old?.dispose();
    if (mounted) {
      setState(() {});
    }
  }

  void _resolveImage() {
    if (widget.pageIndex < 0 ||
        widget.pageIndex >= widget.document.pages.length) {
      _setImage(null);
      return;
    }

    final cached = widget.cache.getImageSync(widget.pageIndex);
    if (cached != null) {
      _setImage(cached.clone());
      return;
    }

    unawaited(_fetchImage());
  }

  Future<void> _fetchImage() async {
    if (_isLoading) return;
    _isLoading = true;
    final requestId = ++_activeRequestId;

    try {
      final targetPixelSize = _calculateTargetPixelSize();
      final img = await widget.cache.loadPage(
        widget.pageIndex,
        fullWidth: targetPixelSize.width,
        fullHeight: targetPixelSize.height,
      );

      if (!mounted || requestId != _activeRequestId) return;
      _setImage(img?.clone());

      if (img != null) {
        PageReadyNotification(pageIndex: widget.pageIndex).dispatch(context);
      }
    } catch (_) {
      // Keep loading state from being stuck permanently on render failure.
    } finally {
      if (requestId == _activeRequestId) {
        _isLoading = false;
      }
    }
  }

  Size _calculateFitSize() {
    if (widget.pageIndex >= widget.document.pages.length) {
      return widget.constraints.biggest;
    }
    final page = widget.document.pages[widget.pageIndex];
    final w = page.width <= 0 ? 1.0 : page.width;
    final h = page.height <= 0 ? 1.0 : page.height;
    final pageAspect = w / h;

    final maxW = widget.constraints.maxWidth;
    final maxH = widget.constraints.maxHeight;
    if (maxW <= 0 || maxH <= 0 || !maxW.isFinite || !maxH.isFinite) {
      return const Size(100, 100);
    }

    final containerAspect = maxW / maxH;
    if (containerAspect > pageAspect) {
      return Size(maxH * pageAspect, maxH);
    } else {
      return Size(maxW, maxW / pageAspect);
    }
  }

  Size _calculateTargetPixelSize() {
    final fitSize = _calculateFitSize();
    final dpr = math.max(
      1.0,
      View.maybeOf(context)?.devicePixelRatio ??
          MediaQuery.maybeOf(context)?.devicePixelRatio ??
          2.0,
    );
    final scale = (dpr * 1.5).clamp(1.5, 300.0 / 72.0);
    return Size(
      math.max(1.0, fitSize.width * scale),
      math.max(1.0, fitSize.height * scale),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pageIndex >= widget.document.pages.length) {
      return const SizedBox.expand();
    }

    final fitSize = _calculateFitSize();
    final image = _image;
    final isReady = image != null;

    return PageCaptureGuard(
      isReady: isReady,
      child: Container(
        color: widget.backgroundColor,
        alignment: Alignment.center,
        child: SizedBox(
          width: fitSize.width,
          height: fitSize.height,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Color(0xFFFFFFFF),
              boxShadow: [
                BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: isReady
                ? RawImage(
                    image: image,
                    width: fitSize.width,
                    height: fitSize.height,
                    fit: BoxFit.fill,
                  )
                : const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _PdfPageImageCache {
  _PdfPageImageCache({
    required this.document,
    this.renderOverride,
    @visibleForTesting this.createImageOverride,
  });

  final PdfDocument document;
  final Future<ui.Image?> Function(
    int pageIndex,
    double fullWidth,
    double fullHeight,
  )?
  renderOverride;

  @visibleForTesting
  final Future<ui.Image> Function(PdfImage pdfImage)? createImageOverride;

  static const int _maxEntries = 8;

  bool _isDisposed = false;
  bool get isDisposed => _isDisposed;

  final Map<int, ui.Image> _images = {};
  final Map<int, Future<ui.Image?>> _inFlight = {};
  final List<int> _lru = [];
  Size? _lastPixelSize;

  ui.Image? getImageSync(int pageIndex) {
    if (_isDisposed) return null;
    final img = _images[pageIndex];
    if (img != null) {
      _touch(pageIndex);
      return img;
    }
    return null;
  }

  void _touch(int pageIndex) {
    _lru.remove(pageIndex);
    _lru.add(pageIndex);
  }

  Future<ui.Image?> loadPage(
    int pageIndex, {
    required double fullWidth,
    required double fullHeight,
  }) async {
    if (_isDisposed) return null;
    if (pageIndex < 0 || pageIndex >= document.pages.length) return null;

    _lastPixelSize = Size(fullWidth, fullHeight);

    final existing = _images[pageIndex];
    if (existing != null) {
      _touch(pageIndex);
      return existing;
    }

    final inFlight = _inFlight[pageIndex];
    if (inFlight != null) {
      return inFlight;
    }

    final future = _render(pageIndex, fullWidth, fullHeight);
    _inFlight[pageIndex] = future;

    try {
      final img = await future;
      if (_isDisposed) {
        img?.dispose();
        return null;
      }
      if (img != null) {
        final oldImg = _images[pageIndex];
        if (oldImg != null && oldImg != img) {
          oldImg.dispose();
        }
        _images[pageIndex] = img;
        _touch(pageIndex);
        _trim();
      }
      return img;
    } finally {
      unawaited(_inFlight.remove(pageIndex));
    }
  }

  Future<ui.Image?> _render(
    int pageIndex,
    double fullWidth,
    double fullHeight,
  ) async {
    if (_isDisposed) return null;
    try {
      if (renderOverride != null) {
        return await renderOverride!(pageIndex, fullWidth, fullHeight);
      }
      if (pageIndex < 0 || pageIndex >= document.pages.length) return null;
      final page = document.pages[pageIndex];
      final pdfImage = await page.render(
        fullWidth: fullWidth,
        fullHeight: fullHeight,
      );
      if (pdfImage == null) return null;
      if (_isDisposed) {
        pdfImage.dispose();
        return null;
      }
      ui.Image image;
      try {
        image = await (createImageOverride != null
            ? createImageOverride!(pdfImage)
            : pdfImage.createImage());
      } finally {
        pdfImage.dispose();
      }
      if (_isDisposed) {
        image.dispose();
        return null;
      }
      return image;
    } catch (_) {
      return null;
    }
  }

  void preload(int pageIndex) {
    if (_isDisposed) return;
    if (pageIndex < 0 ||
        pageIndex >= document.pages.length ||
        _images.containsKey(pageIndex) ||
        _inFlight.containsKey(pageIndex)) {
      return;
    }

    final page = document.pages[pageIndex];
    final defaultW = _lastPixelSize?.width ?? (page.width * 2.0);
    final defaultH = _lastPixelSize?.height ?? (page.height * 2.0);

    unawaited(loadPage(pageIndex, fullWidth: defaultW, fullHeight: defaultH));
  }

  void _trim() {
    while (_lru.length > _maxEntries) {
      final oldest = _lru.removeAt(0);
      final img = _images.remove(oldest);
      img?.dispose();
    }
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _inFlight.clear();
    for (final img in _images.values) {
      img.dispose();
    }
    _images.clear();
    _lru.clear();
  }
}

/// Internal image cache for rendered PDF pages.
///
/// Marked [visibleForTesting] so its disposal and asynchronous loading lifecycle
/// can be directly validated without depending on hardware PDF rendering.
@visibleForTesting
class PdfPageImageCache extends _PdfPageImageCache {
  PdfPageImageCache({
    required super.document,
    super.renderOverride,
    @visibleForTesting super.createImageOverride,
  });

  @visibleForTesting
  int get cachedCount => _images.length;

  @visibleForTesting
  bool hasPageCached(int pageIndex) => _images.containsKey(pageIndex);

  @visibleForTesting
  bool hasInFlight(int pageIndex) => _inFlight.containsKey(pageIndex);
}

class _DefaultLoadingIndicator extends StatelessWidget {
  const _DefaultLoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Loading…', style: TextStyle(color: Color(0xFF888888))),
    );
  }
}
