import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:flip_book/src/flip_corner.dart';
import 'package:flip_book/src/flip_settings.dart';

/// Controls a [FlipBookWidget] or [FlipBookPdf] programmatically.
///
/// Attach via the `controller` parameter. Dispose when no longer needed.
///
/// ```dart
/// final controller = FlipBookController();
///
/// // Animated flips
/// controller.flipNext();
/// controller.flipPrev(corner: FlipCorner.bottomLeft);
///
/// // Jump to page 5 with intermediate animations
/// controller.goToPage(5);
///
/// // Instant jump (no animation)
/// controller.goToPage(5, animate: false);
///
/// // Non-animated page step
/// controller.nextPage();
/// controller.previousPage();
/// ```
class FlipBookController extends ChangeNotifier {
  int _currentPage = 0;
  int _pageCount = 0;
  bool _isAnimating = false;

  /// The zero-based index of the currently displayed page (or left-page of a spread).
  int get currentPage => _currentPage;

  /// Total number of pages.
  int get pageCount => _pageCount;

  /// Whether a flip animation is currently in progress.
  bool get isAnimating => _isAnimating;

  // Internal state subscribed to by the widget.
  //
  // Intents are queued rather than held in a single slot: a multi-page
  // [goToPage] enqueues one intent per page and the widget consumes only one
  // at a time (it must wait for each flip animation to finish). A single slot
  // silently dropped every intent after the first.
  final Queue<_FlipIntent> _queue = Queue<_FlipIntent>();

  /// The next intent awaiting consumption, or `null` when none is queued.
  _FlipIntent? get pendingIntent => _queue.isEmpty ? null : _queue.first;

  /// Whether any intents are still waiting to be consumed.
  bool get hasPendingIntents => _queue.isNotEmpty;

  /// Called by the widget once it has consumed the pending intent.
  ///
  /// The widget dequeues an intent when it *starts* the flip, so the target of
  /// that in-flight flip is retained here; otherwise [_projectedPage] would
  /// see an empty queue and a stale [currentPage] while the flip runs.
  void clearIntent() {
    if (_queue.isEmpty) return;
    final target = _queue.removeFirst().targetPage;
    _inFlightTarget = target == _currentPage ? null : target;
  }

  /// Called by the widget to initialise / update the page count.
  void attach(int pageCount, int initialPage) {
    _pageCount = pageCount;
    _currentPage = initialPage.clamp(0, pageCount - 1);
    // Intents queued against a previous book are meaningless now.
    _queue.clear();
    _inFlightTarget = null;
    _completeJourney();
  }

  /// Called by the widget when the page count changes without the book
  /// itself changing, e.g. an EPUB re-paginating after a font-size change.
  ///
  /// Unlike [attach] this keeps any queued intents, so a jump issued while
  /// pagination is still settling is not thrown away.
  void updatePageCount(int pageCount) {
    if (_pageCount == pageCount) return;
    _pageCount = pageCount;
    final last = pageCount <= 0 ? 0 : pageCount - 1;
    final clamped = _currentPage.clamp(0, last);
    if (clamped != _currentPage) _currentPage = clamped;
    notifyListeners();
  }

  /// Called by the widget whenever the current page changes.
  void reportPage(int page) {
    if (_currentPage != page) {
      _currentPage = page;
      notifyListeners();
    }
    if (_inFlightTarget == _currentPage) _inFlightTarget = null;
    if (_journeyTarget == _currentPage && _queue.isEmpty) {
      _completeJourney();
    }
  }

  /// Called by the widget when an animation starts or ends.
  void reportAnimating(bool value) {
    if (_isAnimating != value) {
      _isAnimating = value;
      notifyListeners();
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Animate a flip to the next page.
  ///
  /// [corner] determines which corner peels. Defaults to [FlipCorner.bottomRight].
  ///
  /// Repeated calls stack: tapping "next" three times in one frame queues three
  /// flips rather than three requests for the same page.
  void flipNext({FlipCorner corner = FlipCorner.bottomRight}) {
    final from = _projectedPage;
    if (from >= _pageCount - 1) return;
    _enqueue(_FlipIntent.animated(
      targetPage: from + 1,
      corner: corner,
    ));
  }

  /// Animate a flip to the previous page.
  ///
  /// [corner] defaults to [FlipCorner.bottomLeft].
  ///
  /// Repeated calls stack, as with [flipNext].
  void flipPrev({FlipCorner corner = FlipCorner.bottomLeft}) {
    final from = _projectedPage;
    if (from <= 0) return;
    _enqueue(_FlipIntent.animated(
      targetPage: from - 1,
      corner: corner,
    ));
  }

  /// Jump to [page] (zero-based).
  ///
  /// When [animate] is `true` (default), intermediate pages are queued so the
  /// user sees every page turn. When `false`, the jump is instant.
  ///
  /// The returned future completes once the book has actually reached [page].
  Future<void> goToPage(int page, {bool animate = true}) {
    if (_pageCount <= 0) return Future<void>.value();

    final target = page.clamp(0, _pageCount - 1);
    final from = _projectedPage;
    if (target == from) return Future<void>.value();

    if (!animate) {
      _journeyTarget = target;
      // Create the completer *before* notifying: _enqueue notifies
      // synchronously, so the widget may reach the target and try to complete
      // the journey before this method returns.
      final future = _journeyFuture();
      _enqueue(_FlipIntent.instant(targetPage: target));
      return future;
    }

    // Queue every intermediate flip up front. The widget consumes them one at
    // a time, starting the next only once the previous has committed, so
    // nothing is dropped.
    final step = target > from ? 1 : -1;
    final corner = step > 0 ? FlipCorner.bottomRight : FlipCorner.bottomLeft;

    int cursor = from;
    while (cursor != target) {
      cursor += step;
      _queue.add(_FlipIntent.animated(targetPage: cursor, corner: corner));
    }
    _journeyTarget = target;
    final future = _journeyFuture();
    notifyListeners();
    return future;
  }

  /// Move to the next page without animation (instant update).
  void nextPage() {
    final from = _projectedPage;
    if (from >= _pageCount - 1) return;
    _enqueue(_FlipIntent.instant(targetPage: from + 1));
  }

  /// Move to the previous page without animation (instant update).
  void previousPage() {
    final from = _projectedPage;
    if (from <= 0) return;
    _enqueue(_FlipIntent.instant(targetPage: from - 1));
  }

  // ── Flip behaviour overrides ──────────────────────────────────────────────

  bool? _enabledOverride;
  Duration? _durationOverride;

  /// Overrides [FlipSettings.enabled] at runtime, or clears the override when
  /// passed `null`.
  ///
  /// The widget's own `flip:` settings remain the baseline; this only changes
  /// the one field, so a host can toggle the animation without rebuilding.
  void setFlipEnabled(bool? enabled) {
    if (_enabledOverride == enabled) return;
    _enabledOverride = enabled;
    notifyListeners();
  }

  /// Overrides [FlipSettings.duration] at runtime, or clears the override when
  /// passed `null`.
  void setFlipDuration(Duration? duration) {
    if (_durationOverride == duration) return;
    _durationOverride = duration;
    notifyListeners();
  }

  /// Drops every runtime override, restoring the widget's own settings.
  void clearFlipOverrides() {
    if (_enabledOverride == null && _durationOverride == null) return;
    _enabledOverride = null;
    _durationOverride = null;
    notifyListeners();
  }

  /// Applies any runtime overrides on top of [base]. Called by the widget.
  FlipSettings applyFlipOverrides(FlipSettings base) {
    if (_enabledOverride == null && _durationOverride == null) return base;
    return base.copyWith(
      enabled: _enabledOverride,
      duration: _durationOverride,
    );
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  // Completes when a multi-step [goToPage] finally reaches its target.
  Completer<void>? _journey;
  int? _journeyTarget;

  // Target of the flip the widget is currently running, if any.
  int? _inFlightTarget;

  /// The page the book will show once every queued intent has been consumed.
  ///
  /// Stepping from here rather than from [currentPage] is what lets rapid
  /// repeated calls queue up instead of collapsing onto a single target.
  int get _projectedPage {
    if (_queue.isNotEmpty) return _queue.last.targetPage;
    return _inFlightTarget ?? _currentPage;
  }

  Future<void> _journeyFuture() =>
      (_journey ??= Completer<void>()).future;

  void _completeJourney() {
    _journeyTarget = null;
    final journey = _journey;
    _journey = null;
    if (journey != null && !journey.isCompleted) journey.complete();
  }

  void _enqueue(_FlipIntent intent) {
    _queue.add(intent);
    notifyListeners();
  }

  @override
  void dispose() {
    _queue.clear();
    _inFlightTarget = null;
    _completeJourney();
    super.dispose();
  }
}

/// Internal representation of a flip request.
class _FlipIntent {
  const _FlipIntent.animated({
    required this.targetPage,
    required FlipCorner this.corner,
  }) : animate = true;

  const _FlipIntent.instant({required this.targetPage})
      : animate = false,
        corner = FlipCorner.bottomRight;

  final int targetPage;
  final bool animate;
  final FlipCorner corner;
}
