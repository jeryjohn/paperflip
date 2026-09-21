import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flip_book/src/epub/epub_controller.dart';
import 'package:flip_book/src/epub/epub_document.dart';
import 'package:flip_book/src/epub/epub_pagination.dart';
import 'package:flip_book/src/epub/epub_reader_settings.dart';
import 'package:flip_book/src/epub/epub_renderer.dart';
import 'package:flip_book/src/epub/epub_source.dart';
import 'package:flip_book/src/flip_book_controller.dart';
import 'package:flip_book/src/flip_book_widget.dart';
import 'package:flip_book/src/flip_settings.dart';

/// A reflowable EPUB rendered through the page-flip engine.
///
/// ```dart
/// FlipBookEpub(
///   source: EpubSource.network('https://example.com/book.epub'),
/// )
/// ```
///
/// Content is laid out once per spine document at the current viewport width,
/// measured, and then sliced into viewport-sized pages. Changing the font size,
/// line height, margin or orientation re-measures and re-paginates, and the
/// reader's place is restored from an [EpubLocator] rather than a page number.
class FlipBookEpub extends StatefulWidget {
  const FlipBookEpub({
    super.key,
    required this.source,
    this.controller,
    this.epubController,
    this.flip = const FlipSettings(),
    this.reader = const EpubReaderSettings(),
    this.showPageIndicator = true,
    this.loadingBuilder,
    this.errorBuilder,
    this.onDocumentLoaded,
  });

  /// Where the book comes from.
  final EpubSource source;

  /// Controls page navigation and flip behaviour.
  final FlipBookController? controller;

  /// Controls typography, chapters and reading position.
  ///
  /// When supplied, its [EpubController.settings] take precedence over
  /// [reader], so runtime changes survive rebuilds.
  final EpubController? epubController;

  /// Page-flip animation configuration.
  final FlipSettings flip;

  /// Typography and layout, used when [epubController] is null.
  final EpubReaderSettings reader;

  /// Whether to show the page-number overlay.
  final bool showPageIndicator;

  /// Shown while the book downloads and parses.
  final Widget Function(BuildContext context)? loadingBuilder;

  /// Shown when the book cannot be loaded.
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  /// Called once the book is parsed.
  final void Function(EpubDocument document)? onDocumentLoaded;

  @override
  State<FlipBookEpub> createState() => _FlipBookEpubState();
}

class _FlipBookEpubState extends State<FlipBookEpub> {
  EpubDocument? _document;
  Object? _error;
  int _loadGeneration = 0;

  /// Measured natural height of each spine document at the current layout.
  final Map<int, double> _heights = {};

  /// The next document to measure, or null when measurement is complete.
  int? _measuring;

  Size? _contentSize;
  EpubReaderSettings? _laidOutWith;
  EpubPagination? _pagination;

  /// Position to restore once the new pagination is ready.
  EpubLocator? _restoreTo;

  /// Prepared chapter subtrees, keyed by spine index.
  ///
  /// The flip engine rebuilds its layers on every animation frame, and each
  /// layer asks for a page. Without this the chapter's HTML was re-parsed and
  /// its whole widget tree rebuilt ~20 times per page turn. Handing back the
  /// *same* Widget instance lets Flutter skip the subtree entirely.
  final Map<int, Widget> _chapterCache = {};

  /// How many chapters either side of the current one to keep prepared.
  static const int _chapterCacheRadius = 1;

  FlipBookController? _ownedFlipController;
  FlipBookController get _flipController =>
      widget.controller ?? (_ownedFlipController ??= FlipBookController());

  EpubReaderSettings get _settings =>
      widget.epubController?.settings ?? widget.reader;

  @override
  void initState() {
    super.initState();
    widget.epubController?.addListener(_onEpubControllerChanged);
    _flipController.addListener(_onFlipPageChanged);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant FlipBookEpub old) {
    super.didUpdateWidget(old);

    if (old.epubController != widget.epubController) {
      old.epubController?.removeListener(_onEpubControllerChanged);
      widget.epubController?.addListener(_onEpubControllerChanged);
    }
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onFlipPageChanged);
      _flipController.addListener(_onFlipPageChanged);
    }
    if (old.source != widget.source) {
      unawaited(_load());
    } else if (old.reader != widget.reader &&
        widget.epubController == null &&
        widget.reader != _laidOutWith) {
      _scheduleRepagination();
    }
  }

  @override
  void dispose() {
    widget.epubController?.removeListener(_onEpubControllerChanged);
    widget.controller?.removeListener(_onFlipPageChanged);
    _ownedFlipController?.dispose();
    super.dispose();
  }

  // ── Loading ───────────────────────────────────────────────────────────────

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _document = null;
      _error = null;
      _heights.clear();
      _chapterCache.clear();
      _pagination = null;
      _measuring = null;
      _laidOutWith = null;
    });

    try {
      final document = await EpubDocument.open(widget.source);
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _document = document);
      widget.epubController?.attachDocument(document);
      widget.onDocumentLoaded?.call(document);
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = e);
    }
  }

  // ── Reflow ────────────────────────────────────────────────────────────────

  void _onEpubControllerChanged() {
    if (!mounted) return;

    final controller = widget.epubController!;

    // A chapter jump asked for while we are ready to act on it.
    final pending = controller.pendingSpineIndex;
    if (pending != null && _pagination != null) {
      controller.clearPendingSpineIndex();
      final page = _pagination!.startPageOf(pending);
      unawaited(_flipController.goToPage(page, animate: false));
    }

    if (controller.settings != _laidOutWith) {
      _scheduleRepagination();
    }
  }

  /// Drops measurements and starts a fresh pass, remembering where the reader
  /// was so their place can be restored afterwards.
  void _scheduleRepagination() {
    final pagination = _pagination;
    if (pagination != null) {
      _restoreTo = pagination.locatorAt(_flipController.currentPage);
    }
    setState(() {
      _heights.clear();
      _chapterCache.clear();
      _pagination = null;
      _measuring = null;
      _laidOutWith = null;
    });
  }

  void _onFlipPageChanged() {
    final pagination = _pagination;
    if (pagination == null) return;
    widget.epubController?.reportLocator(
      pagination.locatorAt(_flipController.currentPage),
    );
  }

  /// Records a measured document height and queues the next one.
  ///
  /// Measurement runs one document per frame. Text measurement cannot leave
  /// the UI isolate in Flutter, so doing the whole book in one pass would
  /// block for as long as it takes to lay out every chapter.
  void _onMeasured(int spineIndex, double height) {
    if (!mounted || _heights[spineIndex] == height) return;
    _heights[spineIndex] = height;

    final document = _document;
    if (document == null) return;

    final next = spineIndex + 1;
    setState(() {
      _measuring = next < document.spine.length ? next : null;
      _rebuildPagination();
    });
  }

  void _rebuildPagination() {
    final document = _document;
    final size = _contentSize;
    if (document == null || size == null || size.height <= 0) return;

    final pagination = EpubPagination(
      pageHeight: size.height,
      heights: Map<int, double>.from(_heights),
      spineLength: document.spine.length,
    );
    _pagination = pagination;
    _laidOutWith = _settings;
    widget.epubController?.attachPagination(pagination);

    // Restore the reading position once the pass that covers it is done.
    final restore = _restoreTo;
    if (restore != null && pagination.isComplete) {
      _restoreTo = null;
      final page = pagination.pageFor(restore);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_flipController.goToPage(page, animate: false));
        }
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return widget.errorBuilder?.call(context, error) ??
          _DefaultEpubError(error: error);
    }

    final document = _document;
    if (document == null) {
      return widget.loadingBuilder?.call(context) ??
          const _DefaultEpubLoading();
    }

    if (document.spine.isEmpty) {
      return widget.errorBuilder?.call(
            context,
            const EpubLoadException('The book has no readable content.'),
          ) ??
          const _DefaultEpubError(
            error: EpubLoadException('The book has no readable content.'),
          );
    }

    final settings = _settings;

    return LayoutBuilder(
      builder: (context, constraints) {
        final margin = settings.margin;
        final contentSize = Size(
          (constraints.maxWidth - margin * 2).clamp(1.0, double.infinity),
          (constraints.maxHeight - margin * 2).clamp(1.0, double.infinity),
        );

        // Viewport or typography changed: re-measure from scratch.
        if (_contentSize != contentSize || _laidOutWith != settings) {
          final sizeChanged =
              _contentSize != null && _contentSize != contentSize;
          _contentSize = contentSize;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (sizeChanged && _pagination != null && _restoreTo == null) {
              _restoreTo = _pagination!.locatorAt(_flipController.currentPage);
            }
            if (_laidOutWith != settings || _heights.isEmpty) {
              setState(() {
                _heights.clear();
                _chapterCache.clear();
                _pagination = null;
                _measuring = 0;
              });
            } else {
              setState(_rebuildPagination);
            }
          });
        }

        final pagination = _pagination;

        return Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: settings.theme.background,
                child: pagination == null
                    ? (widget.loadingBuilder?.call(context) ??
                          const _DefaultEpubLoading())
                    : FlipBookWidget(
                        pageCount: pagination.totalPages,
                        controller: _flipController,
                        flip: widget.flip,
                        showPageIndicator: widget.showPageIndicator,
                        backgroundColor: settings.theme.background,
                        pageBackColor: settings.theme.background,
                        pageBuilder: (context, index, pageConstraints) =>
                            _buildPage(
                              context,
                              document: document,
                              pagination: pagination,
                              settings: settings,
                              globalPage: index,
                              contentSize: contentSize,
                            ),
                      ),
              ),
            ),

            // Offstage measurement host. Laying the document out inside a
            // scroll view gives it unbounded height, so its natural height can
            // be read back.
            if (_measuring != null && _measuring! < document.spine.length)
              Positioned(
                left: -100000,
                top: 0,
                width: contentSize.width,
                height: contentSize.height,
                child: IgnorePointer(
                  child: _MeasureHost(
                    key: ValueKey(
                      'measure-$_measuring-${settings.fontSize}'
                      '-${settings.lineHeight}-${contentSize.width}',
                    ),
                    onMeasured: (height) => _onMeasured(_measuring!, height),
                    child: EpubRenderer(
                      document: document,
                      item: document.spine[_measuring!],
                      settings: settings,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Builds one page by translating the laid-out document so the requested
  /// slice sits in the viewport, then clipping to it.
  Widget _buildPage(
    BuildContext context, {
    required EpubDocument document,
    required EpubPagination pagination,
    required EpubReaderSettings settings,
    required int globalPage,
    required Size contentSize,
  }) {
    final ref = pagination.resolve(globalPage);
    final item = document.spine[ref.spineIndex];

    return ColoredBox(
      color: settings.theme.background,
      child: Padding(
        padding: EdgeInsets.all(settings.margin),
        child: ClipRect(
          child: SizedBox(
            width: contentSize.width,
            height: contentSize.height,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minHeight: 0,
              maxHeight: double.infinity,
              child: Transform.translate(
                offset: Offset(0, -ref.offsetFor(contentSize.height)),
                child: SizedBox(
                  width: contentSize.width,
                  child: _chapterFor(
                    document: document,
                    item: item,
                    settings: settings,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Returns the prepared subtree for a chapter, building it once.
  ///
  /// Returning an identical Widget instance is what makes repeated page builds
  /// cheap: Flutter skips updating a subtree whose widget is the same object
  /// it already holds.
  Widget _chapterFor({
    required EpubDocument document,
    required EpubSpineItem item,
    required EpubReaderSettings settings,
  }) {
    final cached = _chapterCache[item.index];
    if (cached != null) return cached;

    final built = RepaintBoundary(
      child: EpubRenderer(document: document, item: item, settings: settings),
    );
    _chapterCache[item.index] = built;
    _evictDistantChapters(item.index);
    return built;
  }

  /// Keeps only the chapters near the one being read.
  void _evictDistantChapters(int around) {
    if (_chapterCache.length <= _chapterCacheRadius * 2 + 1) return;
    _chapterCache.removeWhere(
      (index, _) => (index - around).abs() > _chapterCacheRadius,
    );
  }
}

/// Lays a child out at its natural height and reports it after layout.
class _MeasureHost extends StatefulWidget {
  const _MeasureHost({
    super.key,
    required this.child,
    required this.onMeasured,
  });

  final Widget child;
  final ValueChanged<double> onMeasured;

  @override
  State<_MeasureHost> createState() => _MeasureHostState();
}

class _MeasureHostState extends State<_MeasureHost> {
  final GlobalKey _key = GlobalKey();
  double? _reported;

  @override
  void initState() {
    super.initState();
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(covariant _MeasureHost old) {
    super.didUpdateWidget(old);
    _scheduleMeasure();
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) {
        // The HTML may still be building asynchronously; try again next frame.
        _scheduleMeasure();
        return;
      }
      final height = box.size.height;
      if (height <= 0) {
        _scheduleMeasure();
        return;
      }
      if (_reported == height) return;
      _reported = height;
      widget.onMeasured(height);
    });
  }

  @override
  Widget build(BuildContext context) {
    // A scroll view hands the child unbounded height so it lays out fully
    // rather than being clipped to the viewport.
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: KeyedSubtree(key: _key, child: widget.child),
    );
  }
}

class _DefaultEpubLoading extends StatelessWidget {
  const _DefaultEpubLoading();

  @override
  Widget build(BuildContext context) => const Center(
    child: Text(
      'Loading…',
      style: TextStyle(color: Color(0xFF888888), fontSize: 14),
    ),
  );
}

class _DefaultEpubError extends StatelessWidget {
  const _DefaultEpubError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'Could not open this book.\n\n$error',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFFCC0000), fontSize: 14),
      ),
    ),
  );
}
