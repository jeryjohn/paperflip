import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flip_book/src/flip_corner.dart';

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
  _FlipIntent? _pendingIntent;
  _FlipIntent? get pendingIntent => _pendingIntent;

  /// Called by the widget once it has consumed a pending intent.
  void clearIntent() {
    _pendingIntent = null;
  }

  /// Called by the widget to initialise / update the page count.
  void attach(int pageCount, int initialPage) {
    _pageCount = pageCount;
    _currentPage = initialPage.clamp(0, pageCount - 1);
  }

  /// Called by the widget whenever the current page changes.
  void reportPage(int page) {
    if (_currentPage != page) {
      _currentPage = page;
      notifyListeners();
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
  void flipNext({FlipCorner corner = FlipCorner.bottomRight}) {
    if (_currentPage >= _pageCount - 1) return;
    _enqueue(_FlipIntent.animated(
      targetPage: _currentPage + 1,
      corner: corner,
    ));
  }

  /// Animate a flip to the previous page.
  ///
  /// [corner] defaults to [FlipCorner.bottomLeft].
  void flipPrev({FlipCorner corner = FlipCorner.bottomLeft}) {
    if (_currentPage <= 0) return;
    _enqueue(_FlipIntent.animated(
      targetPage: _currentPage - 1,
      corner: corner,
    ));
  }

  /// Jump to [page] (zero-based).
  ///
  /// When [animate] is `true` (default), intermediate pages are queued so the
  /// user sees every page turn. When `false`, the jump is instant.
  Future<void> goToPage(int page, {bool animate = true}) async {
    final target = page.clamp(0, _pageCount - 1);
    if (target == _currentPage) return;

    if (!animate) {
      _enqueue(_FlipIntent.instant(targetPage: target));
      return;
    }

    // Queue each intermediate flip so the animation runs through every page.
    final step = target > _currentPage ? 1 : -1;
    final corner = step > 0 ? FlipCorner.bottomRight : FlipCorner.bottomLeft;

    // Use a completer-based queue so callers can await the whole journey.
    int from = _currentPage;
    while (from != target) {
      from += step;
      _enqueue(_FlipIntent.animated(targetPage: from, corner: corner));
      // Tiny yield so each intent can be picked up by the widget.
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  /// Move to the next page without animation (instant update).
  void nextPage() {
    if (_currentPage >= _pageCount - 1) return;
    _enqueue(_FlipIntent.instant(targetPage: _currentPage + 1));
  }

  /// Move to the previous page without animation (instant update).
  void previousPage() {
    if (_currentPage <= 0) return;
    _enqueue(_FlipIntent.instant(targetPage: _currentPage - 1));
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  void _enqueue(_FlipIntent intent) {
    _pendingIntent = intent;
    notifyListeners();
  }

  @override
  void dispose() {
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
