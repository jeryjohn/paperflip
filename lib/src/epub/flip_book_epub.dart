import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'package:flip_book/src/epub/epub_controller.dart';
import 'package:flip_book/src/epub/epub_document.dart';
import 'package:flip_book/src/epub/epub_pagination.dart';
import 'package:flip_book/src/epub/epub_reader_settings.dart';
import 'package:flip_book/src/epub/epub_renderer.dart';
import 'package:flip_book/src/epub/epub_source.dart';
import 'package:flip_book/src/flip_book_controller.dart';
import 'package:flip_book/src/flip_settings.dart';
import 'package:flip_book/src/mesh_flip_book.dart';

/// A reflowable EPUB rendered through the shared 3D mesh page-flip engine.
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
///
/// The EPUB renderer deliberately does not own a separate page-turn renderer.
/// It prepares normal Flutter page widgets and hands them to [MeshFlipBook],
/// which is the same 3D curl engine used by custom pages.
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
    this.useVolumeKeys = false,
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

  /// Whether physical volume buttons navigate pages on supported devices (Android).
  final bool useVolumeKeys;


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
  EpubReaderSettings? _layoutSettings;
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

  /// Last known logical reading position. This is more reliable than a partial
  /// page number when a resize/reflow happens while pagination is incomplete.
  EpubLocator? _lastLocator;

  FlipBookController? _ownedFlipController;
  FlipBookController? _listenedFlipController;
  late final ValueNotifier<int> _pageIndicatorPage = ValueNotifier<int>(0);
  bool _controllerMutationScheduled = false;

  /// Stable callback identity for MeshFlipBook. The callback reads current
  /// state from this State object, so it remains valid after re-pagination.
  late final Widget Function(BuildContext, int, BoxConstraints)
  _meshPageBuilder;

  /// Prevents repeated post-frame layout resets while a reset is already queued.
  bool _layoutResetScheduled = false;

  /// Invalidates a running measurement pass. Every _MeasureHost captures the
  /// generation that created it, so stale results cannot contaminate a new
  /// pagination pass.
  int _paginationGeneration = 0;

  /// Changes whenever a completely new pagination should receive a fresh
  /// MeshFlipBook state/cache.
  int _meshGeneration = 0;

  /// Page to show when the current complete pagination creates the mesh reader.
  int _initialMeshPage = 0;

  FlipBookController get _flipController =>
      widget.controller ?? (_ownedFlipController ??= FlipBookController());

  EpubReaderSettings get _settings =>
      widget.epubController?.settings ?? widget.reader;

  @override
  void initState() {
    super.initState();
    _meshPageBuilder = _buildMeshPage;
    _bindFlipController();
    _pageIndicatorPage.value = _flipController.currentPage;
    widget.epubController?.addListener(_onEpubControllerChanged);
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
      _rebindFlipController();
    }

    if (old.source != widget.source) {
      unawaited(_load());
      return;
    }

    if (old.reader != widget.reader &&
        widget.epubController == null &&
        widget.reader != _layoutSettings) {
      _scheduleRepagination();
    }
  }

  @override
  void dispose() {
    widget.epubController?.removeListener(_onEpubControllerChanged);
    _listenedFlipController?.removeListener(_onFlipPageChanged);
    _ownedFlipController?.dispose();
    _pageIndicatorPage.dispose();
    super.dispose();
  }

  // ── Controller binding ─────────────────────────────────────────────────────

  void _bindFlipController() {
    final controller = _flipController;
    if (_listenedFlipController == controller) return;

    _listenedFlipController?.removeListener(_onFlipPageChanged);
    _listenedFlipController = controller;
    controller.addListener(_onFlipPageChanged);
  }

  void _rebindFlipController() {
    _listenedFlipController?.removeListener(_onFlipPageChanged);
    _listenedFlipController = null;

    // The owned controller is no longer needed once the caller supplies an
    // external controller. Dispose it so its listener/resources do not linger.
    if (widget.controller != null && _ownedFlipController != null) {
      _ownedFlipController!.dispose();
      _ownedFlipController = null;
    }

    _bindFlipController();
    _pageIndicatorPage.value = _flipController.currentPage;
  }

  // ── Loading ─────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    final generation = ++_loadGeneration;

    _paginationGeneration++;
    _meshGeneration++;
    _layoutResetScheduled = false;
    _initialMeshPage = 0;
    _restoreTo = null;
    _lastLocator = null;

    if (!mounted) return;

    void resetBeforeLoad() {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _document = null;
        _error = null;
        _heights.clear();
        _chapterCache.clear();
        _pagination = null;
        _measuring = null;
        _contentSize = null;
        _layoutSettings = null;
      });
    }

    // `_load()` can be started from didUpdateWidget(), which runs during the
    // framework's update/build cycle. Never call setState synchronously from
    // there; defer only when Flutter is currently building.
    _scheduleControllerMutation(resetBeforeLoad);

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

  // ── Reflow ──────────────────────────────────────────────────────────────────

  void _onEpubControllerChanged() {
    if (!mounted) return;

    // Controller notifications can happen while a descendant such as
    // MeshFlipBook is being inserted during our own build. Do not mutate this
    // State synchronously from that notification; defer the side effect until
    // the current build has completed.
    _scheduleControllerMutation(() {
      if (!mounted) return;

      final controller = widget.epubController;
      if (controller == null) return;

      final pending = controller.pendingSpineIndex;
      final pagination = _pagination;

      if (pending != null && pagination != null && pagination.isComplete) {
        controller.clearPendingSpineIndex();
        final page = pagination
            .startPageOf(pending)
            .clamp(0, mathMaxPage(pagination.totalPages))
            .toInt();
        unawaited(_flipController.goToPage(page, animate: false));
        return;
      }

      if (controller.settings != _layoutSettings) {
        _scheduleRepagination();
      }
    });
  }

  /// Drops measurements and starts a fresh pass, remembering where the reader
  /// was so their place can be restored afterwards.
  void _scheduleRepagination() {
    final pagination = _pagination;
    if (pagination != null && pagination.isComplete) {
      _restoreTo ??=
          _lastLocator ?? pagination.locatorAt(_flipController.currentPage);
    }

    _paginationGeneration++;
    _meshGeneration++;
    _heights.clear();
    _chapterCache.clear();
    _pagination = null;
    _measuring = null;
    _layoutSettings = null;

    if (!mounted) return;

    _scheduleControllerMutation(() {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _onFlipPageChanged() {
    final pagination = _pagination;
    if (pagination != null && pagination.isComplete) {
      final page = _flipController.currentPage
          .clamp(0, mathMaxPage(pagination.totalPages))
          .toInt();
      _lastLocator = pagination.locatorAt(page);
      widget.epubController?.reportLocator(_lastLocator!);
    }

    // The page indicator listens directly to this notifier, so the parent
    // EpubReader state does not need to call setState from a controller
    // notification. This is especially important when MeshFlipBook attaches
    // the controller during its own insertion into the widget tree.
    _pageIndicatorPage.value = _flipController.currentPage;
  }

  void _scheduleControllerMutation(VoidCallback mutation) {
    if (!mounted) return;

    final phase = SchedulerBinding.instance.schedulerPhase;
    final duringBuild =
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks ||
        phase == SchedulerPhase.transientCallbacks;

    if (!duringBuild) {
      mutation();
      return;
    }

    if (_controllerMutationScheduled) return;
    _controllerMutationScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controllerMutationScheduled = false;
      if (!mounted) return;
      mutation();
    });
  }

  // ── Pagination ──────────────────────────────────────────────────────────────

  /// Records a measured document height and queues the next one.
  ///
  /// Measurement runs one document per frame. Text measurement cannot leave
  /// the UI isolate in Flutter, so doing the whole book in one pass would
  /// block for as long as it takes to lay out every chapter.
  void _onMeasured(int spineIndex, double height, int generation) {
    if (!mounted || generation != _paginationGeneration) return;
    if (_measuring != spineIndex || _heights[spineIndex] == height) return;

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
    final settings = _layoutSettings ?? _settings;

    if (document == null || size == null || size.height <= 0) return;

    final pagination = EpubPagination(
      pageHeight: size.height,
      heights: Map<int, double>.from(_heights),
      spineLength: document.spine.length,
    );

    _pagination = pagination;
    widget.epubController?.attachPagination(pagination);

    if (!pagination.isComplete) return;

    _flipController.updatePageCount(pagination.totalPages);

    final restore = _restoreTo;
    if (restore != null && pagination.isComplete) {
      _restoreTo = null;
      final page = pagination
          .pageFor(restore)
          .clamp(0, mathMaxPage(pagination.totalPages))
          .toInt();
      _initialMeshPage = page;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_flipController.goToPage(page, animate: false));
        }
      });
    }
    _layoutSettings = settings;

    // A pending chapter jump may have arrived while the document was still
    // being measured. Re-check it now that page numbers are stable.
    _onEpubControllerChanged();
  }

  // ── Build ───────────────────────────────────────────────────────────────────

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

        final needsLayoutReset =
            _contentSize != contentSize || _layoutSettings != settings;

        if (needsLayoutReset && !_layoutResetScheduled) {
          _layoutResetScheduled = true;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _layoutResetScheduled = false;

            // The requested layout may have changed again before this callback
            // ran. Use the latest values only.
            final latestSettings = _settings;
            final latestMargin = latestSettings.margin;
            final latestSize = Size(
              (constraints.maxWidth - latestMargin * 2).clamp(
                1.0,
                double.infinity,
              ),
              (constraints.maxHeight - latestMargin * 2).clamp(
                1.0,
                double.infinity,
              ),
            );

            if (_contentSize != null &&
                _pagination != null &&
                _pagination!.isComplete &&
                _restoreTo == null) {
              _restoreTo =
                  _lastLocator ??
                  _pagination!.locatorAt(_flipController.currentPage);
            }

            _paginationGeneration++;
            _meshGeneration++;
            _contentSize = latestSize;
            _layoutSettings = latestSettings;
            _heights.clear();
            _chapterCache.clear();
            _pagination = null;
            _measuring = 0;
            _initialMeshPage = 0;

            setState(() {});
          });
        }

        final pagination = _pagination;
        final pageReady =
            pagination != null &&
            pagination.isComplete &&
            pagination.totalPages > 0;

        final pageIndicator = pageReady && widget.showPageIndicator
            ? Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: IgnorePointer(
                  child: Center(
                    child: ValueListenableBuilder<int>(
                      valueListenable: _pageIndicatorPage,
                      builder: (context, currentPage, child) => _PageIndicator(
                        currentPage: currentPage,
                        pageCount: pagination.totalPages,
                      ),
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink();

        final measuringIndex = _measuring;
        final measurementGeneration = _paginationGeneration;

        return Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: settings.theme.background,
                child: pagination == null
                    ? (widget.loadingBuilder?.call(context) ??
                          const _DefaultEpubLoading())
                    : MeshFlipBook(
                        key: ValueKey(_meshGeneration),
                        controller: _flipController,
                        pageCount: pagination.totalPages,
                        initialPage: _initialMeshPage,
                        flip: widget.flip,
                        backgroundColor: settings.theme.background,
                        pageBackColor: settings.theme.background,
                        useVolumeKeys: widget.useVolumeKeys,
                        pageBuilder: _meshPageBuilder,
                      ),
              ),
            ),

            pageIndicator,

            // Offstage measurement host. Laying the document out inside a
            // scroll view gives it unbounded height, so its natural height can
            // be read back.
            if (!pageReady &&
                measuringIndex != null &&
                measuringIndex >= 0 &&
                measuringIndex < document.spine.length)
              Positioned(
                left: -100000,
                top: 0,
                width: contentSize.width,
                height: contentSize.height,
                child: IgnorePointer(
                  child: _MeasureHost(
                    key: ValueKey(
                      'measure-$measurementGeneration-$measuringIndex-'
                      '${settings.fontSize}-${settings.lineHeight}-'
                      '${settings.margin}-${contentSize.width}',
                    ),
                    onMeasured: (height) => _onMeasured(
                      measuringIndex,
                      height,
                      measurementGeneration,
                    ),
                    child: EpubRenderer(
                      document: document,
                      item: document.spine[measuringIndex],
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

  // ── Page construction ───────────────────────────────────────────────────────

  Widget _buildMeshPage(
    BuildContext context,
    int index,
    BoxConstraints pageConstraints,
  ) {
    final document = _document;
    final pagination = _pagination;
    if (document == null || pagination == null) {
      return const SizedBox.shrink();
    }

    return _buildPage(
      context,
      document: document,
      pagination: pagination,
      settings: _settings,
      globalPage: index,
      // Pagination is measured against the margin-reduced content viewport.
      // Do not pass the full MeshFlipBook viewport here or page offsets drift
      // by the reader margin on every page.
      contentSize: _contentSize ?? pageConstraints.biggest,
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
    if (globalPage < 0 || globalPage >= pagination.totalPages) {
      return ColoredBox(color: settings.theme.background);
    }

    final ref = pagination.resolve(globalPage);
    final item = document.spine[ref.spineIndex];

    final offset = ref.offsetFor(contentSize.height);

    return SizedBox(
      width: contentSize.width + settings.margin * 2,
      height: contentSize.height + settings.margin * 2,
      child: ColoredBox(
        color: settings.theme.background,
        child: Padding(
          padding: EdgeInsets.all(settings.margin),
          child: ClipRect(
            child: SizedBox(
              width: contentSize.width,
              height: contentSize.height,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: contentSize.width,
                maxWidth: contentSize.width,
                minHeight: 0,
                maxHeight: double.infinity,
                child: Transform.translate(
                  offset: Offset(0, -offset),
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
      ),
    );
  }

  /// Builds a chapter subtree for a page.
  ///
  /// No nested RepaintBoundary is used here so the chapter does not allocate an
  /// unbounded off-screen texture layer; the outer MeshFlipBook PageCaptureHost
  /// owns the page-sized boundary.
  Widget _chapterFor({
    required EpubDocument document,
    required EpubSpineItem item,
    required EpubReaderSettings settings,
  }) {
    final cached = _chapterCache[item.index];
    if (cached != null) return cached;

    final built = EpubRenderer(
      document: document,
      item: item,
      settings: settings,
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

int mathMaxPage(int pageCount) => pageCount <= 0 ? 0 : pageCount - 1;

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
    if (old.child.key != widget.child.key) {
      _reported = null;
    }
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

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.currentPage, required this.pageCount});

  final int currentPage;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    final page = (currentPage + 1).clamp(1, pageCount).toInt();

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
