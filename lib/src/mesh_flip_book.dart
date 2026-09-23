import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'package:flip_book/src/capture/widget_page_rasterizer.dart';
import 'package:flip_book/src/flip_book_controller.dart';
import 'package:flip_book/src/flip_book_widget.dart' show FlipPageBuilder;
import 'package:flip_book/src/flip_settings.dart';
import 'package:flip_book/src/pages/page_texture.dart';
import 'package:flip_book/src/rendering/curl_parameters.dart';
import 'package:flip_book/src/rendering/flip_scene.dart';
import 'package:flip_book/src/rendering/page_curl_camera.dart';
import 'package:flip_book/src/rendering/page_curl_geometry.dart';
import 'package:flip_book/src/rendering/page_curl_mesh.dart';
import 'package:flip_book/src/rendering/page_curl_renderer.dart';
import 'package:flip_book/src/rendering/sheet_atlas.dart';

/// A page-flip book rendered as a real texture-mapped 3D curl.
///
/// The page content is mapped onto a developable surface and follows it: text
/// bends with the paper rather than being reflected flat across a crease.
///
/// ```dart
/// MeshFlipBook(
///   pageCount: 20,
///   pageBuilder: (context, index, constraints) => MyPage(index),
/// )
/// ```
///
/// ## How it fits together
///
/// At rest the reader shows an ordinary live widget — real text, real
/// semantics, real interactivity. The curl surface is inert and paints nothing.
///
/// A turn swaps in a prepared texture for the moving sheet only. When it lands,
/// the live widget returns. The texture is an animation asset; it is never the
/// resting representation.
///
/// Pages are captured ahead of interaction into a bounded cache, so the first
/// pointer move never triggers a rasterisation.
class MeshFlipBook extends StatefulWidget {
  const MeshFlipBook({
    super.key,
    required this.pageCount,
    required this.pageBuilder,
    this.controller,
    this.initialPage = 0,
    this.flip = const FlipSettings(),
    this.backgroundColor = const Color(0xFFE8E4DC),
    this.pageBackColor = const Color(0xFFF0EEE8),
    this.showShadow = true,
    this.meshColumns = PageCurlMesh.defaultColumns,
    this.capturePixelRatio = 2.0,
    this.debugShowMesh = false,
    this.contentVersion = 0,
  });

  /// Total number of pages.
  final int pageCount;

  /// Builds each page. See [FlipPageBuilder].
  final FlipPageBuilder pageBuilder;

  /// Optional controller for programmatic flips.
  final FlipBookController? controller;

  /// The page shown on first build.
  final int initialPage;

  /// Flip timing and behaviour.
  final FlipSettings flip;

  /// Colour behind the book.
  final Color backgroundColor;

  /// Colour of the back of a turning sheet.
  final Color pageBackColor;

  /// Whether the lifted sheet casts a shadow.
  final bool showShadow;

  /// Mesh columns across the page; rows follow the aspect ratio.
  ///
  /// Higher is smoother and more expensive. The implementation plan's
  /// benchmark sweeps 24/32/42/48 before a default is settled on.
  final int meshColumns;

  /// Resolution multiplier used when capturing pages.
  final double capturePixelRatio;

  /// Draws the mesh wireframe over the page. Development aid only.
  final bool debugShowMesh;

  /// Identifies a change in the page content that should invalidate captured
  /// textures. Document sources such as EPUB should increment this when their
  /// pagination/layout changes.
  ///
  /// This is deliberately separate from widget identity because a page builder
  /// can remain the same function while the document it renders changes.
  final int contentVersion;

  @override
  State<MeshFlipBook> createState() => _MeshFlipBookState();
}

class _MeshFlipBookState extends State<MeshFlipBook>
    with TickerProviderStateMixin {
  final FlipScene _scene = FlipScene();
  final CurlSmoother _smoother = CurlSmoother();
  final PageTextureCache _cache = PageTextureCache();
  final Map<int, GlobalKey> _captureKeys = {};

  late WidgetPageRasterizer _rasterizer;
  late AnimationController _settle;
  Ticker? _ticker;

  PageCurlMesh? _mesh;
  PageCurlCamera? _camera;
  Size _pageSize = Size.zero;
  ui.Image? _paperImage;

  int _currentPage = 0;
  SheetRoles? _roles;

  /// Packed sheets, keyed by the page on the sheet's front.
  ///
  /// Built ahead of interaction, so a drag finds its atlas already there. A
  /// sheet assembled on drag *start* would not exist for the first few frames
  /// and the page would sit flat and then pop into a curl.
  final Map<int, SheetAtlas> _atlases = {};
  final Set<int> _packing = {};
  final Set<int> _capturing = {};

  /// Ensures build() can request capture work without stacking multiple
  /// post-frame callbacks for the same page window.
  bool _capturePassScheduled = false;

  /// When a spring ends, the geometry smoother can still be one or two frames
  /// behind the spring. We hold the logical settle result until the displayed
  /// curl has actually reached that target; this removes the final-frame snap.
  double? _settleCompletionTarget;

  /// Resize/page-count changes invalidate the current visual turn. Guard the
  /// animation status callback while the settle controller is stopped.
  bool _resettingLayout = false;

  /// Build-time changes are deferred until after the current build so neither
  /// the controller nor the paint-only scene can synchronously notify an
  /// ancestor while Flutter is laying out this widget.
  bool _layoutUpdateScheduled = false;
  Size? _pendingLayoutSize;

  /// Source/widget-property changes are coalesced into one post-frame reset.
  bool _sourceResetScheduled = false;
  bool _sourceResetPending = false;

  final PageCurlRenderer _renderer = PageCurlRenderer();

  SheetAtlas? get _atlas =>
      _roles == null ? null : _atlases[_roles!.turningFront];

  // Gesture state.
  Offset? _dragStart;
  bool _dragDecided = false;
  bool _dragging = false;
  double _grabV = 0.5;
  double _rawProgress = 0.0;

  Duration _lastTick = Duration.zero;
  int _captureGeneration = 0;

  double get _effectiveCapturePixelRatio =>
      widget.capturePixelRatio.isFinite && widget.capturePixelRatio > 0
      ? widget.capturePixelRatio
      : 1.0;

  FlipBookController? get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage
        .clamp(0, math.max(0, widget.pageCount - 1))
        .toInt();
    _rasterizer = WidgetPageRasterizer(pixelRatio: _effectiveCapturePixelRatio);
    _settle = AnimationController.unbounded(vsync: this)
      ..addListener(_onSettleTick)
      ..addStatusListener(_onSettleStatus);
    _ticker = createTicker(_onTick);
    _controller?.attach(widget.pageCount, _currentPage);
    _controller?.addListener(_onControllerUpdate);
  }

  @override
  void didUpdateWidget(covariant MeshFlipBook old) {
    super.didUpdateWidget(old);

    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onControllerUpdate);
      _controller?.addListener(_onControllerUpdate);

      _scheduleSourceReset(reattachController: true);
    }

    final pageCountChanged = old.pageCount != widget.pageCount;
    final captureRatioChanged =
        old.capturePixelRatio != widget.capturePixelRatio;
    final meshChanged = old.meshColumns != widget.meshColumns;
    final sourceChanged =
        old.pageBuilder != widget.pageBuilder ||
        old.contentVersion != widget.contentVersion;
    final pageBackChanged = old.pageBackColor != widget.pageBackColor;

    if (captureRatioChanged ||
        meshChanged ||
        sourceChanged ||
        pageBackChanged ||
        pageCountChanged) {
      _scheduleSourceReset(
        reattachController: old.controller != widget.controller,
      );
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerUpdate);
    _ticker?.dispose();
    _settle.dispose();
    _scene.dispose();
    for (final atlas in _atlases.values) {
      atlas.dispose();
    }
    _atlases.clear();
    _capturing.clear();
    _cache.clear();
    _paperImage?.dispose();
    super.dispose();
  }

  // ── Texture preparation ───────────────────────────────────────────────────

  /// Page indices worth having ready: the current page and its neighbours.
  List<int> get _window {
    final indices = <int>[];
    for (var offset = -1; offset <= 1; offset++) {
      final index = _currentPage + offset;
      if (index >= 0 && index < widget.pageCount) indices.add(index);
    }
    return indices;
  }

  PageTextureKey _keyFor(int index) => PageTextureKey(
    sourceId: identityHashCode(widget.pageBuilder),
    pageId: index,
    logicalSize: _pageSize,
    pixelRatio: _effectiveCapturePixelRatio,
    contentVersion: Object.hash(widget.contentVersion, _captureGeneration),
  );

  GlobalKey _captureKeyFor(int index) =>
      _captureKeys.putIfAbsent(index, GlobalKey.new);

  void _invalidateTextures() {
    _captureGeneration++;
    _capturing.clear();
    _cache.clear();
    for (final atlas in _atlases.values) {
      atlas.dispose();
    }
    _atlases.clear();
    _packing.clear();
  }

  /// Cancels a visual turn without changing the logical page. Used when the
  /// source changes underneath the renderer (for example, EPUB re-pagination)
  /// or when the viewport is resized.
  void _cancelActiveTurnForSourceChange({bool notify = true}) {
    _resettingLayout = true;
    try {
      if (_settle.isAnimating) {
        _settle.stop();
      }
    } finally {
      _resettingLayout = false;
    }

    _dragStart = null;
    _dragDecided = false;
    _dragging = false;
    _rawProgress = 0.0;
    _settleCompletionTarget = null;
    _roles = null;
    _smoother.reset(CurlParameters.rest);
    _stopTicking();

    if (notify) {
      _scene.rest();
      _controller?.reportAnimating(false);
    }
  }

  /// Defers source/layout mutation until after the current build.
  ///
  /// This is intentionally the single entry point for changes that can affect
  /// page count, textures, mesh size, controller attachment or paper colour.
  /// It prevents `notifyListeners()` from running inside LayoutBuilder or
  /// didUpdateWidget.
  void _scheduleSourceReset({bool reattachController = false}) {
    _sourceResetPending = true;
    if (_sourceResetScheduled) return;

    _sourceResetScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sourceResetScheduled = false;
      if (!mounted) return;

      _cancelActiveTurnForSourceChange(notify: false);

      if (widget.pageCount <= 0) {
        _currentPage = 0;
      } else {
        _currentPage = _currentPage.clamp(0, widget.pageCount - 1).toInt();
      }

      if (widget.capturePixelRatio != 0) {
        _rasterizer = WidgetPageRasterizer(
          pixelRatio: _effectiveCapturePixelRatio,
        );
      }

      if (_pageSize.isFinite && !_pageSize.isEmpty) {
        _mesh = PageCurlMesh.forPage(
          pageSize: _pageSize,
          columns: math.max(4, widget.meshColumns),
        );
        _camera = PageCurlCamera.forPage(_pageSize);
      }

      _paperImage?.dispose();
      _paperImage = null;

      _invalidateTextures();
      _sourceResetPending = false;

      if (reattachController) {
        _controller?.attach(widget.pageCount, _currentPage);
      } else {
        _controller?.updatePageCount(widget.pageCount);
        _controller?.reportPage(_currentPage);
      }

      _scene.rest();
      _controller?.reportAnimating(false);

      if (mounted) {
        setState(() {});
      }
    });
  }

  /// Defers a new finite page size until after the current LayoutBuilder build.
  void _scheduleLayoutUpdate(Size size) {
    _pendingLayoutSize = size;
    if (_layoutUpdateScheduled) return;

    _layoutUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _layoutUpdateScheduled = false;
      final pending = _pendingLayoutSize;
      _pendingLayoutSize = null;

      if (!mounted || pending == null) return;
      if (pending.isEmpty ||
          !pending.width.isFinite ||
          !pending.height.isFinite) {
        return;
      }

      _cancelActiveTurnForSourceChange(notify: false);

      _pageSize = pending;
      _mesh = PageCurlMesh.forPage(
        pageSize: pending,
        columns: math.max(4, widget.meshColumns),
      );
      _camera = PageCurlCamera.forPage(pending);

      _invalidateTextures();
      _sourceResetPending = false;

      _scene.rest();
      _controller?.reportAnimating(false);

      if (mounted) {
        setState(() {});
      }
    });
  }

  /// Schedules a single post-frame capture pass. build() can run many times
  /// during a Flutter frame, but only one capture request is allowed to enter
  /// the queue at a time.
  void _prepareTextures() {
    if (_sourceResetPending ||
        _pageSize.isEmpty ||
        !_pageSize.width.isFinite ||
        !_pageSize.height.isFinite ||
        _capturePassScheduled) {
      return;
    }

    _capturePassScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _capturePassScheduled = false;
      if (!mounted) return;
      unawaited(_captureOneTexture());
    });
  }

  /// Captures at most one missing page per pass. This keeps raster readback
  /// work predictable and prevents several builds from starting the same
  /// expensive capture concurrently.
  Future<void> _captureOneTexture() async {
    if (!mounted ||
        _sourceResetPending ||
        _pageSize.isEmpty ||
        !_pageSize.width.isFinite ||
        !_pageSize.height.isFinite) {
      return;
    }

    final generation = _captureGeneration;
    final window = _window;

    for (final index in window) {
      final key = _keyFor(index);
      if (_cache.contains(key) || _capturing.contains(index)) continue;

      _capturing.add(index);
      PageTexture? texture;
      try {
        texture = await _rasterizer.capture(
          _captureKeyFor(index),
          logicalSize: _pageSize,
          textureKey: key,
        );
      } finally {
        _capturing.remove(index);
      }

      if (!mounted || texture == null) return;

      // A resize/source update can invalidate a capture while it is in
      // flight. Never let a stale texture enter the cache.
      if (generation != _captureGeneration) {
        texture.dispose();
        _prepareTextures();
        return;
      }

      _cache.put(key, texture);
      _prepareAdjacentSheets();

      // Exactly one page per frame. The next pass is requested after the
      // current capture completes, so four pages do not all rasterise at once.
      _prepareTextures();
      return;
    }
  }

  /// A plain paper-coloured image, used for the back of a turning sheet.
  ///
  /// A reader shows one page per sheet face, so the back of the page being
  /// turned is blank stock — not the next page, which is revealed beneath it.
  /// Showing the next page on the back would display it twice at once.
  Future<ui.Image> _paperTexture() async {
    final existing = _paperImage;
    if (existing != null && !existing.debugDisposed) return existing;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 8, 8),
      Paint()..color = widget.pageBackColor,
    );
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(8, 8);
      _paperImage = image;
      return image;
    } finally {
      picture.dispose();
    }
  }

  /// Packs the sheet whose front is [index], if its texture has been captured.
  ///
  /// Idempotent and safe to call every frame: an already-packed or in-flight
  /// sheet is skipped.
  Future<void> _prepareSheet(int index) async {
    if (index < 0 || index >= widget.pageCount) return;
    if (_atlases.containsKey(index) || _packing.contains(index)) return;

    final front = _cache[_keyFor(index)];
    if (front == null) return; // not captured yet; retried next frame

    _packing.add(index);
    final generation = _captureGeneration;
    try {
      final paper = await _paperTexture();
      if (!mounted || generation != _captureGeneration) return;

      final atlas = await SheetAtlas.pack(
        PageFaceSet(
          front: front.share(),
          back: PageTexture(image: paper.clone(), logicalSize: _pageSize),
        ),
      );
      // A resize or rebuild while packing makes this sheet wrong for the
      // current layout, so drop it rather than let it reach the screen.
      if (!mounted || generation != _captureGeneration) {
        atlas.dispose();
        return;
      }
      _atlases[index] = atlas;
      _evictDistantSheets();
      if (_roles?.turningFront == index) {
        _scene.commit(curl: _scene.curl, active: true, atlas: atlas);
        // The live page is allowed to switch to the revealed page only after
        // the turning sheet exists. Otherwise the first drag frame can expose
        // the destination underneath a missing curl surface.
        if (mounted) setState(() {});
      }
      // A completed turn may have advanced the logical page while this sheet
      // was being packed. Keep the next forward/backward starting sheets warm.
      _prepareAdjacentSheets();
    } finally {
      _packing.remove(index);
    }
  }

  /// Keeps only the sheets either side of the current page.
  void _evictDistantSheets() {
    final keep = {_currentPage, _currentPage - 1, _currentPage + 1};
    final doomed = _atlases.keys.where((k) => !keep.contains(k)).toList();
    for (final key in doomed) {
      _atlases.remove(key)?.dispose();
    }
  }

  /// Keeps the sheets needed for both immediate directions, plus the next
  /// forward sheet, warm before the user can ask for it.
  void _prepareAdjacentSheets() {
    unawaited(_prepareSheet(_currentPage - 1));
    unawaited(_prepareSheet(_currentPage));
    unawaited(_prepareSheet(_currentPage + 1));
  }

  // ── Frame loop ────────────────────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 1 / 60
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;

    final changed = _smoother.advance(dt);
    final atlas = _atlas;
    if (changed && atlas != null) {
      _scene.commit(curl: _smoother.displayed, active: true, atlas: atlas);
    }

    final settleTarget = _settleCompletionTarget;
    if (settleTarget != null && !_settle.isAnimating && _smoother.isSettled) {
      _settleCompletionTarget = null;
      _finishSettle(settleTarget);
      return;
    }

    // Stop ticking once the display has caught up and nothing is driving it.
    if (_smoother.isSettled &&
        !_dragging &&
        !_settle.isAnimating &&
        _settleCompletionTarget == null) {
      _stopTicking();
    }
  }

  void _startTicking() {
    final ticker = _ticker;
    if (ticker == null || ticker.isActive) return;
    _lastTick = Duration.zero;
    ticker.start();
  }

  void _stopTicking() {
    _ticker?.stop();
    _lastTick = Duration.zero;
  }

  // ── Gestures ──────────────────────────────────────────────────────────────

  void _onPanStart(DragStartDetails details) {
    if (!widget.flip.enabled || _settle.isAnimating) return;
    _dragStart = details.localPosition;
    _dragDecided = false;
    _dragging = false;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!widget.flip.enabled || _settle.isAnimating) return;
    final start = _dragStart;
    if (start == null || _pageSize.isEmpty) return;

    if (!_dragDecided) {
      final dx = details.localPosition.dx - start.dx;
      if (dx.abs() < 6) return;
      final forward = dx < 0;
      if (forward && _currentPage >= widget.pageCount - 1) return;
      if (!forward && _currentPage <= 0) return;

      // The vertical grab position is what distinguishes a corner pull from a
      // centre pull, and it is the one thing the previous renderer discarded.
      _grabV = (start.dy / _pageSize.height).clamp(0.0, 1.0).toDouble();
      _dragDecided = true;
      _dragging = true;

      final roles = SheetRoles.forTurn(
        currentPage: _currentPage,
        forward: forward,
      );
      _roles = roles;
      _smoother.reset(_curlFor(0.0, roles.direction));
      // Normally already packed; this covers the first interaction after a
      // resize, when the capture may not have landed yet.
      unawaited(_prepareSheet(roles.turningFront));
      setState(() {}); // reveal the page beneath, once
      _startTicking();
    }

    if (!_dragging) return;
    final travelled = (details.localPosition.dx - start.dx).abs();
    _rawProgress = (travelled / _pageSize.width).clamp(0.0, 1.0).toDouble();
    _smoother.setTarget(_curlFor(_rawProgress, _roles!.direction));
  }

  void _onPanEnd(DragEndDetails details) {
    _dragStart = null;
    if (!_dragging) return;
    _dragging = false;

    final roles = _roles;
    if (roles == null) return;

    // Normalise by page width so the feel is the same on a phone and a tablet.
    final vx = details.velocity.pixelsPerSecond.dx;
    final signed = roles.direction > 0 ? -vx : vx;
    final normalised = _pageSize.width <= 0 ? 0.0 : signed / _pageSize.width;

    // Project where the gesture was heading rather than testing position
    // alone: a short fast flick should complete, a long slow drag should be
    // able to cancel.
    final projected = _rawProgress + normalised * 0.12;
    final complete = projected > 0.5 || normalised > 1.2;

    _settleTo(complete ? 1.0 : 0.0, velocity: normalised);
  }

  CurlParameters _curlFor(double progress, int direction) =>
      CurlParameters.forGesture(
        progress: progress,
        grabV: _grabV,
        direction: direction,
      );

  /// Springs the curl to [target], preserving the gesture's velocity.
  ///
  /// A critically damped spring rather than a tween: the sheet carries the
  /// momentum the finger gave it, so release feels continuous with the drag
  /// instead of restarting as a fresh animation.
  void _settleTo(double target, {double velocity = 0.0}) {
    final roles = _roles;
    if (roles == null) return;

    final from = _smoother.target.progress;
    _settleCompletionTarget = null;
    _controller?.reportAnimating(true);
    _startTicking();

    if ((target - from).abs() < 1e-3) {
      // Still let the display smoother consume the exact final target.
      _smoother.setTarget(_curlFor(target, roles.direction));
      _settleCompletionTarget = target;
      return;
    }

    _settle.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(mass: 1, stiffness: 220, ratio: 1.0),
        from,
        target,
        velocity,
        snapToEnd: true,
      ),
    );
  }

  void _onSettleTick() {
    final roles = _roles;
    if (roles == null) return;
    final progress = _settle.value.clamp(0.0, 1.0).toDouble();
    _smoother.setTarget(_curlFor(progress, roles.direction));
  }

  void _onSettleStatus(AnimationStatus status) {
    if (_resettingLayout) return;
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      final target = _settle.value.clamp(0.0, 1.0).toDouble();
      _settleCompletionTarget = target;
      _smoother.setTarget(_curlFor(target, _roles?.direction ?? 1));
      _startTicking();
    }
  }

  void _finishSettle(double target) {
    if (!mounted) return;

    final roles = _roles;
    _roles = null;
    _rawProgress = 0.0;
    _settleCompletionTarget = null;
    _smoother.reset(CurlParameters.rest);
    _scene.rest();

    if (roles != null && target >= 0.5) {
      final destination = roles.destination
          .clamp(0, math.max(0, widget.pageCount - 1))
          .toInt();
      if (destination != _currentPage) {
        _currentPage = destination;
        _controller?.reportPage(_currentPage);
        _evictDistantSheets();
      }
    }

    _prepareAdjacentSheets();
    _prepareTextures();
    _controller?.reportAnimating(false);
    if (mounted) setState(() {});
    _stopTicking();
    _drainIntents();
  }

  // ── Controller ────────────────────────────────────────────────────────────

  bool _draining = false;

  void _onControllerUpdate() => _drainIntents();

  void _drainIntents() {
    if (_draining) return;
    _draining = true;
    try {
      final controller = _controller;
      if (controller == null || !mounted) return;
      if (_dragging || _settle.isAnimating) return;

      while (true) {
        final intent = controller.pendingIntent;
        if (intent == null) return;
        controller.clearIntent();
        final target = intent.targetPage
            .clamp(0, math.max(0, widget.pageCount - 1))
            .toInt();
        if (target == _currentPage) continue;

        if (!intent.animate || !widget.flip.enabled) {
          setState(() => _currentPage = target);
          controller.reportPage(_currentPage);
          _evictDistantSheets();
          _prepareAdjacentSheets();
          _prepareTextures();
          continue;
        }

        final forward = target > _currentPage;
        final roles = SheetRoles.forTurn(
          currentPage: _currentPage,
          forward: forward,
        );
        _roles = roles;
        _grabV = 0.5;
        _smoother.reset(_curlFor(0.0, roles.direction));
        unawaited(_prepareSheet(roles.turningFront));
        setState(() {});
        _settleTo(1.0);
        return;
      }
    } finally {
      _draining = false;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        // LayoutBuilder can legally receive an unbounded axis from a parent
        // such as Column/ScrollView. Never feed an infinite Size into the mesh
        // or perspective camera.
        if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) {
          return ColoredBox(
            color: widget.backgroundColor,
            child: const SizedBox.shrink(),
          );
        }

        // Never mutate/listen-notify during this build. Let the post-frame
        // callback rebuild once with the new finite geometry.
        if (size != _pageSize || _mesh == null || _camera == null) {
          _scheduleLayoutUpdate(size);
          return ColoredBox(
            color: widget.backgroundColor,
            child: const SizedBox.shrink(),
          );
        }

        if (_sourceResetPending) {
          return ColoredBox(
            color: widget.backgroundColor,
            child: const SizedBox.shrink(),
          );
        }

        _prepareTextures();

        final roles = _roles;
        final pageConstraints = BoxConstraints.tight(size);

        return GestureDetector(
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: ColoredBox(
            color: widget.backgroundColor,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Capture host. Mounted and painting so it can be read
                //    back, and completely hidden by the layers above it.
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: IgnorePointer(
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          maxWidth: size.width,
                          maxHeight: size.height,
                          child: PageCaptureHost(
                            indices: _window,
                            keyFor: _captureKeyFor,
                            pageSize: size,
                            builder: (context, index) => widget.pageBuilder(
                              context,
                              index,
                              pageConstraints,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // 2. The live page. At rest this is the whole reader: real
                //    text, real semantics, real interaction. During a turn it
                //    is the page being revealed underneath the moving sheet.
                Positioned.fill(
                  child: _livePage(context, roles, pageConstraints),
                ),

                // 3. The curl surface. Paints nothing at rest, and repaints
                //    without rebuilding anything above.
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _CurlPainter(
                        scene: _scene,
                        mesh: _mesh!,
                        camera: _camera!,
                        showShadow: widget.showShadow,
                        debugShowMesh: widget.debugShowMesh,
                        renderer: _renderer,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _livePage(
    BuildContext context,
    SheetRoles? roles,
    BoxConstraints constraints,
  ) {
    // While a sheet is turning, what sits under it is the page being revealed.
    // Otherwise it is simply the current page.
    final turningAtlas = roles == null ? null : _atlases[roles.turningFront];
    final index = turningAtlas != null ? roles!.revealed : _currentPage;
    if (index < 0 || index >= widget.pageCount) {
      return ColoredBox(color: widget.pageBackColor);
    }
    return widget.pageBuilder(context, index, constraints);
  }
}

/// Paints the curl surface.
///
/// Repaints are driven by [FlipScene] rather than by widget rebuilds, so a
/// whole page turn touches nothing above this render object.
class _CurlPainter extends CustomPainter {
  _CurlPainter({
    required this.scene,
    required this.mesh,
    required this.camera,
    required this.showShadow,
    required this.debugShowMesh,
    required this.renderer,
  }) : super(repaint: scene);

  final FlipScene scene;
  final PageCurlMesh mesh;
  final PageCurlCamera camera;
  final bool showShadow;
  final bool debugShowMesh;
  final PageCurlRenderer renderer;

  static const PageCurlShadow _shadow = PageCurlShadow();
  static const PageCurlGeometry _geometry = PageCurlGeometry();

  @override
  void paint(Canvas canvas, Size size) {
    if (!scene.active) return;
    final atlas = scene.atlas;
    if (atlas == null) return;

    final curl = scene.curl;
    if (showShadow) {
      // Deform first so the shadow traces the real sheet, then let the
      // renderer redo it -- the shadow's outline must come from the same
      // geometry as the page, never from a straight-edged approximation.
      _geometry.deform(mesh, curl);
      camera.projectBuffer(
        mesh.worldPositions,
        mesh.positions,
        mesh.vertexCount,
      );
      _shadow.paint(canvas, mesh, curl, camera: camera);
    }

    renderer.paint(canvas, mesh, curl, atlas, camera: camera);

    if (debugShowMesh) _paintWireframe(canvas);
  }

  void _paintWireframe(Canvas canvas) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = const Color(0x6600E5FF);
    final path = Path();
    for (var row = 0; row <= mesh.rows; row++) {
      for (var col = 0; col <= mesh.columns; col++) {
        final i = mesh.vertexIndex(col, row);
        final x = mesh.positions[i * 2];
        final y = mesh.positions[i * 2 + 1];
        if (!x.isFinite || !y.isFinite) continue;
        if (col == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
    }
    for (var col = 0; col <= mesh.columns; col++) {
      for (var row = 0; row <= mesh.rows; row++) {
        final i = mesh.vertexIndex(col, row);
        final x = mesh.positions[i * 2];
        final y = mesh.positions[i * 2 + 1];
        if (!x.isFinite || !y.isFinite) continue;
        if (row == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CurlPainter old) =>
      old.mesh != mesh ||
      old.camera != camera ||
      old.showShadow != showShadow ||
      old.debugShowMesh != debugShowMesh ||
      old.renderer != renderer;
}
