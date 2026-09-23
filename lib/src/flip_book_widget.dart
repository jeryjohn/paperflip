import 'package:flutter/widgets.dart';

import 'package:flip_book/src/flip_book_controller.dart';
import 'package:flip_book/src/flip_settings.dart';
import 'package:flip_book/src/flip_corner.dart';
import 'package:flip_book/src/page_flip_painter.dart';
import 'package:flip_book/src/volume/volume_key_manager.dart';

/// Signature for a function that builds a single page widget.
///
/// [index] is the zero-based page index.
/// [constraints] are the [BoxConstraints] for the page area — useful for
/// sizing content relative to the available space.
typedef FlipPageBuilder = Widget Function(
  BuildContext context,
  int index,
  BoxConstraints constraints,
);

/// A realistic book page-flip widget.
///
/// Pages are built on demand via [pageBuilder]. The widget auto-detects
/// portrait (single page) vs. landscape (double-page spread) based on its
/// aspect ratio.
///
/// ```dart
/// FlipBookWidget(
///   pageCount: 20,
///   controller: _controller,
///   pageBuilder: (context, index, constraints) {
///     return Container(
///       color: Colors.white,
///       child: Center(child: Text('Page ${index + 1}')),
///     );
///   },
/// );
/// ```
@Deprecated('Use MeshFlipBook or FlipBook.custom instead. Will be removed in a future release.')
class FlipBookWidget extends StatefulWidget {
  const FlipBookWidget({
    super.key,
    required this.pageCount,
    required this.pageBuilder,
    this.controller,
    this.initialPage = 0,
    this.flip = const FlipSettings(),
    @Deprecated('Use flip: FlipSettings(duration: ...). Removed in 0.3.0.')
    this.flipDuration,
    @Deprecated('No longer used; a drag anywhere flips. Removed in 0.3.0.')
    this.hotZoneSize = 60.0,
    this.showPageIndicator = true,
    this.backgroundColor = const Color(0xFFE8E4DC),
    this.spineColor = const Color(0xFFBBB5A8),
    this.pageBackColor = const Color(0xFFF0EEE8),
    this.useVolumeKeys = false,
  });


  /// Total number of pages.
  final int pageCount;

  /// Builder called for each page. See [FlipPageBuilder].
  final FlipPageBuilder pageBuilder;

  /// Optional controller for programmatic control.
  final FlipBookController? controller;

  /// The page displayed on first build (zero-based).
  final int initialPage;

  /// Page-flip animation configuration.
  ///
  /// See [FlipSettings] for enabling/disabling the curl and tuning its
  /// duration, easing, shadow and back face.
  final FlipSettings flip;

  /// Duration of a single page-flip animation.
  @Deprecated('Use flip: FlipSettings(duration: ...). Removed in 0.3.0.')
  final Duration? flipDuration;

  /// Size in logical pixels of each hot-corner trigger zone.
  ///
  /// Unused: a horizontal drag anywhere on the book drives a flip.
  @Deprecated('No longer used; a drag anywhere flips. Removed in 0.3.0.')
  final double hotZoneSize;

  /// The settings actually in force, honouring the deprecated [flipDuration]
  /// when a caller still sets it.
  FlipSettings get effectiveFlip {
    // ignore: deprecated_member_use_from_same_package
    final legacy = flipDuration;
    if (legacy == null) return flip;
    return flip.copyWith(duration: legacy);
  }

  /// Whether to show the page number indicator at the bottom.
  final bool showPageIndicator;

  /// Background colour of the book widget (shows at the edges/spine).
  final Color backgroundColor;

  /// Colour of the centre spine divider in landscape mode.
  final Color spineColor;

  /// Colour shown on the back face of a curling page.
  final Color pageBackColor;

  /// Whether physical volume buttons navigate pages on supported devices (Android).
  final bool useVolumeKeys;

  @override
  State<FlipBookWidget> createState() => _FlipBookWidgetState();
}

class _FlipBookWidgetState extends State<FlipBookWidget>
    with TickerProviderStateMixin
    implements VolumeKeyClient {

  late int _currentPage;
  late AnimationController _animCtrl;
  late CurvedAnimation _curvedAnim;

  FlipCorner _activeCorner = FlipCorner.bottomRight;
  bool _isDragging = false;
  double _dragProgress = 0.0;

  // Drag distance as a 0..1 fraction, tracked even when the curl is disabled
  // so the release threshold still has something to test.
  double _rawDragProgress = 0.0;
  bool _isForward = true;

  // Drag gesture state.
  Offset? _dragStart;
  bool _dragDecided = false;

  // Settling a released drag to exactly 0 or 1. The controller is long-lived:
  // it used to be allocated per drag and disposed from inside its own status
  // listener, which is fragile and can assert in debug builds.
  late final AnimationController _settleCtrl;
  late CurvedAnimation _settleCurve;
  double _settleFrom = 0.0;
  double _settleTarget = 0.0;
  bool _isSettling = false;

  // Re-entrancy guard for _drainIntents.
  bool _draining = false;

  /// Settings currently in force: the widget's own, with any runtime overrides
  /// from the controller applied on top.
  late FlipSettings _flip;

  FlipSettings get _resolvedFlip {
    final base = widget.effectiveFlip;
    final controller = _controller;
    return controller == null ? base : controller.applyFlipOverrides(base);
  }

  /// Re-resolves the settings and re-syncs anything derived from them.
  void _syncFlip() {
    final next = _resolvedFlip;
    final previous = _flip;
    if (next == previous) return;
    _flip = next;

    _animCtrl.duration = next.duration;
    if (previous.curve != next.curve) {
      _curvedAnim.dispose();
      _curvedAnim = CurvedAnimation(parent: _animCtrl, curve: next.curve);
    }
    if (previous.settleCurve != next.settleCurve) {
      _settleCurve.dispose();
      _settleCurve =
          CurvedAnimation(parent: _settleCtrl, curve: next.settleCurve);
    }
    // Disabling mid-flight must not strand a half-turned sheet.
    if (!next.enabled) _abortInFlightFlip();
    if (mounted) setState(() {});
  }

  FlipBookController? get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage.clamp(0, widget.pageCount - 1);

    _flip = _resolvedFlip;
    final flip = _flip;

    _animCtrl = AnimationController(
      vsync: this,
      duration: flip.duration,
    )..addStatusListener(_onAnimStatus);

    _curvedAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: flip.curve,
    );

    _settleCtrl = AnimationController(
      vsync: this,
      duration: flip.duration,
    )
      ..addListener(_onSettleTick)
      ..addStatusListener(_onSettleStatus);
    _settleCurve = CurvedAnimation(
      parent: _settleCtrl,
      curve: flip.settleCurve,
    );

    _controller?.attach(widget.pageCount, _currentPage);
    _controller?.addListener(_onControllerUpdate);
    if (widget.useVolumeKeys) {
      VolumeKeyManager.instance.registerClient(this);
    }
  }

  @override
  void didUpdateWidget(covariant FlipBookWidget old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onControllerUpdate);
      _controller?.attach(widget.pageCount, _currentPage);
      _controller?.addListener(_onControllerUpdate);
    } else if (old.pageCount != widget.pageCount) {
      // The book kept its identity but grew or shrank -- an EPUB
      // re-paginating, say. Without this the controller keeps the old count
      // and clamps goToPage against it.
      final last = widget.pageCount <= 0 ? 0 : widget.pageCount - 1;
      final clamped = _currentPage.clamp(0, last);
      if (clamped != _currentPage) {
        _currentPage = clamped;
        _controller?.reportPage(_currentPage);
      }
      _controller?.updatePageCount(widget.pageCount);
    }
    if (old.useVolumeKeys != widget.useVolumeKeys) {
      if (widget.useVolumeKeys) {
        VolumeKeyManager.instance.registerClient(this);
      } else {
        VolumeKeyManager.instance.unregisterClient(this);
      }
    }
    _syncFlip();
  }

  @override
  void dispose() {
    VolumeKeyManager.instance.unregisterClient(this);
    _controller?.removeListener(_onControllerUpdate);
    // A CurvedAnimation must be disposed before the parent it listens to.
    _settleCurve.dispose();
    _settleCtrl.dispose();
    _curvedAnim.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  void onVolumeUp() {
    _controller?.flipNext();
  }

  @override
  void onVolumeDown() {
    _controller?.flipPrev();
  }


  // ── Controller integration ────────────────────────────────────────────────

  void _onControllerUpdate() {
    // The controller can carry runtime flip overrides as well as intents.
    _syncFlip();
    _drainIntents();
  }

  /// Consumes queued controller intents.
  ///
  /// Only one animated flip can be in flight at a time, so this stops as soon
  /// as it starts one, and is called again from [_onAnimStatus] once that flip
  /// commits. Instant intents are applied in a loop since they cost no time.
  void _drainIntents() {
    // Committing a flip notifies the controller, which re-enters here. Without
    // this guard the nested call starts the next flip and the outer
    // _animCtrl.reset() immediately kills it, stalling the queue forever.
    if (_draining) return;
    _draining = true;
    try {
      _drainIntentsInner();
    } finally {
      _draining = false;
    }
  }

  void _drainIntentsInner() {
    final controller = _controller;
    if (controller == null || !mounted) return;

    // A flip or a released drag is already running; we are called again when
    // it commits.
    if (_animCtrl.isAnimating || _isSettling || _isDragging) return;

    while (true) {
      final intent = controller.pendingIntent;
      if (intent == null) return;
      controller.clearIntent();

      final target = intent.targetPage.clamp(0, widget.pageCount - 1);
      if (target == _currentPage) continue; // nothing to do; try the next one

      if (!intent.animate) {
        setState(() => _currentPage = target);
        controller.reportPage(_currentPage);
        continue;
      }

      if (!_flip.enabled) {
        setState(() => _currentPage = target);
        controller.reportPage(_currentPage);
        continue;
      }

      _startAnimatedFlip(
        toPage: target,
        corner: intent.corner,
      );
      return;
    }
  }

  // ── Animation ─────────────────────────────────────────────────────────────

  void _startAnimatedFlip({
    required int toPage,
    required FlipCorner corner,
  }) {
    if (_animCtrl.isAnimating) return;
    if (toPage == _currentPage) return;

    if (!_flip.enabled) {
      setState(() => _currentPage = toPage.clamp(0, widget.pageCount - 1));
      _controller?.reportPage(_currentPage);
      return;
    }

    setState(() {
      _activeCorner = corner;
      _isForward = toPage > _currentPage;
    });

    _animCtrl.forward(from: 0).then((_) {
      // Committed after animation ends via _onAnimStatus.
    });
    _controller?.reportAnimating(true);
  }

  void _onAnimStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      // A button-driven flip ran to completion via _animCtrl.
      //
      // Reset before committing: _commitFlip notifies the controller, and a
      // re-entrant drain that started a new flip would be clobbered by a
      // reset() issued afterwards.
      _animCtrl.reset();
      _commitFlip(_isForward);
      _controller?.reportAnimating(false);
      // Pick up the next queued intent, if any (e.g. a multi-page goToPage).
      _drainIntents();
    }
  }

  /// Stops any flip in progress and commits it, so switching
  /// [FlipSettings.enabled] to `false` mid-turn cannot strand a half-turned
  /// sheet on screen.
  void _abortInFlightFlip() {
    if (_animCtrl.isAnimating) {
      _animCtrl.stop();
      _animCtrl.reset();
      _commitFlip(_isForward);
      _controller?.reportAnimating(false);
    }
    if (_isSettling) {
      _finishSettle(_settleTarget);
    }
  }

  /// Advances [_currentPage] by one step in the given direction and notifies
  /// the controller. Called when any flip (drag or animated) fully completes.
  void _commitFlip(bool forward) {
    setState(() {
      _currentPage = (forward ? _currentPage + 1 : _currentPage - 1)
          .clamp(0, widget.pageCount - 1);
    });
    _controller?.reportPage(_currentPage);
  }

  // ── Drag handling ─────────────────────────────────────────────────────────
  //
  // A horizontal swipe anywhere on the book drives a flip. Swipe direction
  // decides forward/back; the corner the gesture starts near decides which
  // corner peels (top vs. bottom) for a natural look. On release the flip
  // always settles to fully-open or fully-closed via a single tween so it can
  // never freeze mid-turn.

  void _onPanStart(DragStartDetails details, Size size) {
    if (_animCtrl.isAnimating || _isSettling) return;
    _dragStart = details.localPosition;
    _dragDecided = false;
    _isDragging = false;
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    if (_animCtrl.isAnimating || _isSettling) return;
    final start = _dragStart;
    if (start == null) return;

    // Decide direction on the first meaningful horizontal movement.
    if (!_dragDecided) {
      final dx = details.localPosition.dx - start.dx;
      if (dx.abs() < 6) return; // ignore tiny jitters / vertical scrolls
      final forward = dx < 0; // swipe left → next page
      // Respect page bounds — don't start a flip past the ends.
      if (forward && _currentPage >= widget.pageCount - 1) return;
      if (!forward && _currentPage <= 0) return;

      final fromTop = start.dy < size.height / 2;
      setState(() {
        _dragDecided = true;
        _isDragging = true;
        _isForward = forward;
        _activeCorner = forward
            ? (fromTop ? FlipCorner.topRight : FlipCorner.bottomRight)
            : (fromTop ? FlipCorner.topLeft : FlipCorner.bottomLeft);
        _dragProgress = 0.0;
      });
      _rawDragProgress = 0.0;
    }

    if (!_isDragging) return;
    // Progress is the horizontal distance travelled across the page width.
    final travelled = (details.localPosition.dx - start.dx).abs();
    final progress = (travelled / size.width).clamp(0.0, 1.0);
    _rawDragProgress = progress;
    // With the curl disabled the page must not visibly move; the release
    // threshold reads _rawDragProgress instead.
    if (!_flip.enabled) return;
    setState(() => _dragProgress = progress);
  }

  void _onPanEnd(DragEndDetails details, Size size) {
    _dragStart = null;
    if (!_isDragging) return;
    _isDragging = false;

    // Fling velocity also counts toward committing the flip.
    final vx = details.velocity.pixelsPerSecond.dx;
    final flung = _isForward ? vx < -250 : vx > 250;
    final shouldComplete = _rawDragProgress > 0.35 || flung;
    _rawDragProgress = 0.0;

    if (!_flip.enabled) {
      if (shouldComplete) _commitFlip(_isForward);
      _drainIntents();
      return;
    }

    _settleTo(shouldComplete ? 1.0 : 0.0);
  }

  /// Animates [_dragProgress] from its current value to [target] (0 or 1) with
  /// a single controller, then commits the page (if target == 1) and clears the
  /// drag state. Guarantees the flip never rests at a partial value.
  void _settleTo(double target) {
    if (!_flip.enabled) {
      _finishSettle(target);
      return;
    }
    final from = _dragProgress;
    final distance = (target - from).abs();
    if (distance < 0.001) {
      _finishSettle(target);
      return;
    }

    _settleFrom = from;
    _settleTarget = target;
    _isSettling = true;
    final total = _flip.duration.inMilliseconds;
    _settleCtrl.duration = Duration(
      // Proportional to the remaining travel, with a floor so a tiny
      // correction still reads as motion. Derived from the configured
      // duration rather than a fixed 120..600 window, which used to cap it.
      milliseconds: (total * distance).round().clamp(
            (total ~/ 5).clamp(1, 120),
            total <= 0 ? 1 : total,
          ),
    );
    _controller?.reportAnimating(true);
    _settleCtrl.forward(from: 0.0);
  }

  void _onSettleTick() {
    if (!_isSettling) return;
    final t = _settleCurve.value;
    setState(() {
      _dragProgress = _settleFrom + (_settleTarget - _settleFrom) * t;
    });
  }

  void _onSettleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _isSettling) {
      _finishSettle(_settleTarget);
    }
  }

  void _finishSettle(double target) {
    _isSettling = false;
    _settleCtrl.stop();
    _settleCtrl.value = 0.0;
    if (target >= 1.0) {
      _commitFlip(_isForward);
    }
    setState(() => _dragProgress = 0.0);
    _controller?.reportAnimating(false);
    // A drag may have raced queued controller intents; resume them now.
    _drainIntents();
  }

  // ── Layout ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final isLandscape = constraints.maxWidth > constraints.maxHeight;
      return Stack(
        children: [
          _buildBook(constraints, isLandscape),
          if (widget.showPageIndicator) _buildIndicator(),
        ],
      );
    });
  }

  Widget _buildBook(BoxConstraints constraints, bool isLandscape) {
    return GestureDetector(
      onPanStart: (d) =>
          _onPanStart(d, Size(constraints.maxWidth, constraints.maxHeight)),
      onPanUpdate: (d) =>
          _onPanUpdate(d, Size(constraints.maxWidth, constraints.maxHeight)),
      onPanEnd: (d) =>
          _onPanEnd(d, Size(constraints.maxWidth, constraints.maxHeight)),
      child: Container(
        color: widget.backgroundColor,
        width: constraints.maxWidth,
        height: constraints.maxHeight,
        child: isLandscape
            ? _buildSpread(constraints)
            : _buildSinglePage(constraints),
      ),
    );
  }

  Widget _buildSinglePage(BoxConstraints constraints) {
    return AnimatedBuilder(
      animation: _animCtrl,
      builder: (context, _) {
        final progress =
            _animCtrl.isAnimating ? _curvedAnim.value : _dragProgress;

        final flip = _flip;

        // The flip always turns one physical sheet. Forward turns the current
        // page; backward turns the previous page back into view. In both cases
        // the turning sheet's front is `baseIndex` and the page exposed beneath
        // it is `baseIndex + 1`.
        final baseIndex = _isForward ? _currentPage : _currentPage - 1;
        final turningIndex = baseIndex;
        final settledIndex = baseIndex;
        final revealedIndex = baseIndex + 1;

        if (progress <= 0.0) {
          return _page(context, _currentPage, constraints);
        }

        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return _FlipLayers(
          size: size,
          progress: progress,
          corner: _activeCorner,
          isForward: _isForward,
          pageBackColor: widget.pageBackColor,
                    showShadow: flip.showShadow,
                    showBackFace: flip.showBackFace,
          // Bottom: the page revealed as the current page lifts away.
          revealed: _page(context, revealedIndex, constraints),
          // Stationary remainder of the current page (un-turned part).
          stationary: _page(context, settledIndex, constraints),
          // Front face of the turning page (mirrored onto the flap).
          turningFront: _page(context, turningIndex, constraints),
        );
      },
    );
  }

  /// Builds a single page, or a blank back-colour panel for out-of-range indices.
  Widget _page(BuildContext context, int index, BoxConstraints constraints) {
    if (index < 0 || index >= widget.pageCount) {
      return ColoredBox(
        color: widget.pageBackColor,
        child: const SizedBox.expand(),
      );
    }
    return widget.pageBuilder(context, index, constraints);
  }

  Widget _buildSpread(BoxConstraints constraints) {
    return AnimatedBuilder(
      animation: _animCtrl,
      builder: (context, _) {
        final progress =
            _animCtrl.isAnimating ? _curvedAnim.value : _dragProgress;

        // In landscape each "page" is half the width.
        final halfW = constraints.maxWidth / 2;
        final pageConstraints = BoxConstraints.tight(
          Size(halfW, constraints.maxHeight),
        );

        final flip = _flip;

        // Even pages sit on the left, odd on the right.
        final leftIndex = _currentPage.isEven ? _currentPage : _currentPage - 1;
        final rightIndex = leftIndex + 1;

        // Which half is turning, and what it reveals.
        final halfSize = Size(halfW, constraints.maxHeight);

        Widget half(int index) => SizedBox(
              width: halfW,
              height: constraints.maxHeight,
              child: _page(context, index, pageConstraints),
            );

        Widget turningHalf;
        Widget staticHalf;
        if (_isForward) {
          // Right page turns left over the spine, revealing the next spread's
          // left page (rightIndex + 1). Left page stays put.
          staticHalf = half(leftIndex);
          turningHalf = SizedBox(
            width: halfW,
            height: constraints.maxHeight,
            child: progress > 0
                ? _FlipLayers(
                    size: halfSize,
                    progress: progress,
                    corner: _activeCorner,
                    isForward: true,
                    pageBackColor: widget.pageBackColor,
                    showShadow: flip.showShadow,
                    showBackFace: flip.showBackFace,
                    revealed: _page(context, rightIndex + 1, pageConstraints),
                    stationary: _page(context, rightIndex, pageConstraints),
                    turningFront:
                        _page(context, rightIndex, pageConstraints),
                  )
                : _page(context, rightIndex, pageConstraints),
          );
          return _spreadRow(constraints, staticHalf, turningHalf);
        } else {
          // Left page turns right over the spine, revealing the previous
          // spread's right page (leftIndex - 1). Right page stays put.
          staticHalf = half(rightIndex);
          turningHalf = SizedBox(
            width: halfW,
            height: constraints.maxHeight,
            child: progress > 0
                ? _FlipLayers(
                    size: halfSize,
                    progress: progress,
                    corner: _activeCorner,
                    isForward: false,
                    pageBackColor: widget.pageBackColor,
                    showShadow: flip.showShadow,
                    showBackFace: flip.showBackFace,
                    revealed: _page(context, leftIndex - 1, pageConstraints),
                    stationary: _page(context, leftIndex, pageConstraints),
                    turningFront: _page(context, leftIndex, pageConstraints),
                  )
                : _page(context, leftIndex, pageConstraints),
          );
          return _spreadRow(constraints, turningHalf, staticHalf);
        }
      },
    );
  }

  Widget _spreadRow(BoxConstraints constraints, Widget left, Widget right) {
    return Row(
      children: [
        Expanded(child: left),
        Container(width: 2, color: widget.spineColor),
        Expanded(child: right),
      ],
    );
  }

  Widget _buildIndicator() {
    return Positioned(
      bottom: 8,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0x88000000),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${_currentPage + 1} / ${widget.pageCount}',
            style: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

/// Stacks the three live page widgets that make up a curling page and shades
/// the curl, all driven by a shared [PageFoldGeometry] so the clipped content
/// and painted lighting line up exactly.
///
/// Layer order (bottom → top):
///   1. [revealed]   — the page exposed as the current page lifts away.
///   2. [stationary] — the un-turned remainder of the current page.
///   3. curl shading — [PageFlipPainter] (shadow, back-face tint, highlight).
///   4. [turningFront] reflected onto the lifted flap, clipped to it.
class _FlipLayers extends StatelessWidget {
  const _FlipLayers({
    required this.size,
    required this.progress,
    required this.corner,
    required this.isForward,
    required this.pageBackColor,
    required this.showShadow,
    required this.showBackFace,
    required this.revealed,
    required this.stationary,
    required this.turningFront,
  });

  final Size size;
  final double progress;
  final FlipCorner corner;
  final bool isForward;
  final Color pageBackColor;
  final bool showShadow;
  final bool showBackFace;
  final Widget revealed;
  final Widget stationary;
  final Widget turningFront;

  @override
  Widget build(BuildContext context) {
    final geo = PageFoldGeometry(
      size: size,
      corner: corner,
      progress: progress,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Revealed page beneath.
        revealed,

        // 2. Stationary part of the current page (clipped to un-turned region).
        ClipPath(
          clipper: _PathClipper(geo.stationaryPath),
          child: stationary,
        ),

        // 3. Curl lighting (shadow on stationary, flap back-face, highlight).
        CustomPaint(
          size: size,
          painter: PageFlipPainter(
            progress: progress,
            corner: corner,
            isForward: isForward,
            pageBackColor: pageBackColor,
            showShadow: showShadow,
          ),
        ),

        // 4. Front of the turning page, mirrored onto the flap and clipped to
        //    it. When the back face is off, the painter's paper gradient (drawn
        //    in layer 3) is left showing through instead.
        if (showBackFace)
          ClipPath(
            clipper: _PathClipper(geo.flapPath),
            child: Transform(
              transform: geo.flapReflection,
              child: turningFront,
            ),
          ),
      ],
    );
  }
}

/// Clips a child to an arbitrary pre-computed [Path] (in child coordinates).
class _PathClipper extends CustomClipper<Path> {
  const _PathClipper(this.path);

  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(covariant _PathClipper old) => old.path != path;
}
