import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:flip_book/src/flip_corner.dart';
import 'package:flip_book/src/flip_settings.dart';

/// Controls a flip-book programmatically.
///
/// Attach via the `controller` parameter. Dispose when no longer needed.
///
/// The controller stores navigation *intents* rather than trying to perform
/// animations itself. This keeps the document widget/rendering engine in
/// control of timing while allowing rapid API calls to be queued safely.
class FlipBookController extends ChangeNotifier {
  int _currentPage = 0;
  int _pageCount = 0;
  bool _isAnimating = false;

  /// Zero-based page currently committed by the reader.
  int get currentPage => _currentPage;

  /// Total number of pages in the attached reader.
  int get pageCount => _pageCount;

  /// Whether the reader is currently animating a turn.
  bool get isAnimating => _isAnimating;

  // Navigation intents are queued instead of stored in a single slot. A
  // multi-page journey therefore survives rapid button presses.
  final Queue<FlipIntent> _queue = Queue<FlipIntent>();

  /// The next intent awaiting consumption, or `null`.
  FlipIntent? get pendingIntent => _queue.isEmpty ? null : _queue.first;

  /// Whether any navigation intents remain queued.
  bool get hasPendingIntents => _queue.isNotEmpty;

  /// Called by the reader when it consumes the next intent.
  ///
  /// The target is retained as [_inFlightTarget] until the reader reports the
  /// committed page, so projected navigation remains correct during the
  /// animation itself.
  void clearIntent() {
    if (_queue.isEmpty) return;

    final target = _queue.removeFirst().targetPage;
    _inFlightTarget = target == _currentPage ? null : target;
  }

  /// Attaches the controller to a new reader.
  ///
  /// Attaching starts a new navigation context, so intents from the previous
  /// document are discarded.
  void attach(int pageCount, int initialPage) {
    final safeCount = _maxInt(pageCount, 0);
    _pageCount = safeCount;

    _currentPage = safeCount == 0
        ? 0
        : initialPage.clamp(0, safeCount - 1).toInt();

    final pending = _queue.isNotEmpty ? _queue.first : null;
    _queue.clear();
    if (pending != null && safeCount > 0) {
      _queue.add(
        pending.animate
            ? FlipIntent.animated(
                targetPage: pending.targetPage.clamp(0, safeCount - 1).toInt(),
                corner: pending.corner,
              )
            : FlipIntent.instant(
                targetPage: pending.targetPage.clamp(0, safeCount - 1).toInt(),
              ),
      );
    }
    _inFlightTarget = null;
    _completeJourney();

    if (_isAnimating) {
      _isAnimating = false;
      notifyListeners();
      return;
    }

    notifyListeners();
  }

  /// Updates the page count while keeping the current navigation context.
  ///
  /// This is important for EPUB re-pagination: queued requests remain valid,
  /// but their page targets are clamped to the new document bounds.
  void updatePageCount(int pageCount) {
    final safeCount = _maxInt(pageCount, 0);

    if (_pageCount == safeCount) {
      return;
    }

    _pageCount = safeCount;

    if (safeCount == 0) {
      _currentPage = 0;
      _queue.clear();
      _inFlightTarget = null;
      _completeJourney();
      notifyListeners();
      return;
    }

    final last = safeCount - 1;
    final oldPage = _currentPage;
    _currentPage = _currentPage.clamp(0, last).toInt();

    // Clamp queued intents so projectedPage never points outside the new
    // pagination range.
    if (_queue.isNotEmpty) {
      final clamped = Queue<FlipIntent>();

      for (final intent in _queue) {
        final target = intent.targetPage.clamp(0, last).toInt();

        // A clamped target equal to the immediately previous target is
        // redundant. Keeping the first request preserves journey ordering
        // without producing no-op flips.
        if (target == _currentPage) {
          continue;
        }

        if (clamped.isNotEmpty && clamped.last.targetPage == target) {
          continue;
        }

        clamped.add(
          intent.animate
              ? FlipIntent.animated(targetPage: target, corner: intent.corner)
              : FlipIntent.instant(targetPage: target),
        );
      }

      _queue
        ..clear()
        ..addAll(clamped);
    }

    if (_inFlightTarget != null) {
      _inFlightTarget = _inFlightTarget!.clamp(0, last).toInt();

      if (_inFlightTarget == _currentPage) {
        _inFlightTarget = null;
      }
    }

    if (_journeyTarget != null) {
      _journeyTarget = _journeyTarget!.clamp(0, last).toInt();

      if (_journeyTarget == _currentPage &&
          _queue.isEmpty &&
          _inFlightTarget == null) {
        _completeJourney();
      }
    }

    _maybeCompleteJourney();

    if (oldPage != _currentPage || _queue.isNotEmpty) {
      notifyListeners();
    } else {
      notifyListeners();
    }
  }

  /// Called by the reader whenever the committed page changes.
  void reportPage(int page) {
    if (_pageCount <= 0) {
      if (_currentPage != 0 || _inFlightTarget != null) {
        _currentPage = 0;
        _inFlightTarget = null;
        notifyListeners();
      }
      _maybeCompleteJourney();
      return;
    }

    final safePage = page.clamp(0, _pageCount - 1).toInt();

    if (_currentPage != safePage) {
      _currentPage = safePage;
      notifyListeners();
    }

    if (_inFlightTarget == _currentPage) {
      _inFlightTarget = null;
    }

    _maybeCompleteJourney();
  }

  /// Called by the reader when an animation starts/ends.
  void reportAnimating(bool value) {
    if (_isAnimating == value) return;

    _isAnimating = value;
    notifyListeners();
  }

  // ── Public navigation API ────────────────────────────────────────────────

  /// Animates a flip to the next page.
  ///
  /// Repeated calls queue one turn per call rather than collapsing onto a
  /// single target.
  void flipNext({FlipCorner corner = FlipCorner.bottomRight}) {
    final from = _projectedPage;

    if (_pageCount <= 0 || from >= _pageCount - 1) {
      return;
    }

    _enqueue(FlipIntent.animated(targetPage: from + 1, corner: corner));
  }

  /// Animates a flip to the previous page.
  void flipPrev({FlipCorner corner = FlipCorner.bottomLeft}) {
    final from = _projectedPage;

    if (_pageCount <= 0 || from <= 0) {
      return;
    }

    _enqueue(FlipIntent.animated(targetPage: from - 1, corner: corner));
  }

  /// Moves to [page].
  ///
  /// With [animate] true, every intermediate page is visited in sequence.
  /// With [animate] false, one instantaneous intent is queued.
  ///
  /// The returned future completes when the reader has committed the requested
  /// destination, or immediately when it is already there.
  Future<void> goToPage(int page, {bool animate = true}) {
    if (_pageCount <= 0) {
      _journeyTarget = page;
      final future = _journeyFuture();
      _queue.clear();
      _inFlightTarget = null;
      _enqueue(
        animate
            ? FlipIntent.animated(
                targetPage: page,
                corner: FlipCorner.bottomRight,
              )
            : FlipIntent.instant(targetPage: page),
      );
      return future;
    }

    final target = page.clamp(0, _pageCount - 1).toInt();

    final from = _projectedPage;

    if (target == from) {
      return Future<void>.value();
    }

    // The journey target is set before the synchronous notification so a
    // reader consuming the intent during the notification cannot observe a
    // half-created journey.
    _journeyTarget = target;
    final future = _journeyFuture();

    if (!animate) {
      _queue.add(FlipIntent.instant(targetPage: target));
      notifyListeners();
      return future;
    }

    final step = target > from ? 1 : -1;
    final corner = step > 0 ? FlipCorner.bottomRight : FlipCorner.bottomLeft;

    var cursor = from;

    while (cursor != target) {
      cursor += step;

      _queue.add(FlipIntent.animated(targetPage: cursor, corner: corner));
    }

    notifyListeners();
    return future;
  }

  /// Moves one page forward without a curl animation.
  void nextPage() {
    final from = _projectedPage;

    if (_pageCount <= 0 || from >= _pageCount - 1) {
      return;
    }

    _enqueue(FlipIntent.instant(targetPage: from + 1));
  }

  /// Moves one page backward without a curl animation.
  void previousPage() {
    final from = _projectedPage;

    if (_pageCount <= 0 || from <= 0) {
      return;
    }

    _enqueue(FlipIntent.instant(targetPage: from - 1));
  }

  // ── Runtime flip settings ────────────────────────────────────────────────

  bool? _enabledOverride;
  Duration? _durationOverride;

  /// Overrides the reader's `FlipSettings.enabled` value.
  void setFlipEnabled(bool? enabled) {
    if (_enabledOverride == enabled) return;

    _enabledOverride = enabled;
    notifyListeners();
  }

  /// Overrides the reader's `FlipSettings.duration` value.
  void setFlipDuration(Duration? duration) {
    if (_durationOverride == duration) return;

    _durationOverride = duration;
    notifyListeners();
  }

  /// Clears all runtime flip-setting overrides.
  void clearFlipOverrides() {
    if (_enabledOverride == null && _durationOverride == null) {
      return;
    }

    _enabledOverride = null;
    _durationOverride = null;
    notifyListeners();
  }

  /// Applies runtime overrides over the widget's baseline settings.
  FlipSettings applyFlipOverrides(FlipSettings base) {
    if (_enabledOverride == null && _durationOverride == null) {
      return base;
    }

    return base.copyWith(
      enabled: _enabledOverride,
      duration: _durationOverride,
    );
  }

  /// Returns the effective animation-enabled setting, if an override exists.
  ///
  /// Kept separate from [applyFlipOverrides] so internal renderers can inspect
  /// one value without rebuilding a whole settings object.
  bool? get flipEnabledOverride => _enabledOverride;

  /// Returns the effective duration override, if present.
  Duration? get flipDurationOverride => _durationOverride;

  // ── Internals ────────────────────────────────────────────────────────────

  Completer<void>? _journey;
  int? _journeyTarget;
  int? _inFlightTarget;

  /// Page reached after all currently queued/in-flight intents complete.
  int get _projectedPage {
    if (_queue.isNotEmpty) {
      return _queue.last.targetPage;
    }

    return _inFlightTarget ?? _currentPage;
  }

  Future<void> _journeyFuture() {
    final existing = _journey;
    if (existing != null) {
      return existing.future;
    }

    final created = Completer<void>();
    _journey = created;
    return created.future;
  }

  void _maybeCompleteJourney() {
    final target = _journeyTarget;

    if (target == null) return;
    if (_queue.isNotEmpty) return;
    if (_inFlightTarget != null) return;
    if (_currentPage != target) return;

    _completeJourney();
  }

  void _completeJourney() {
    _journeyTarget = null;

    final journey = _journey;
    _journey = null;

    if (journey != null && !journey.isCompleted) {
      journey.complete();
    }
  }

  void _enqueue(FlipIntent intent) {
    _queue.add(intent);
    notifyListeners();
  }

  @override
  void dispose() {
    _queue.clear();
    _inFlightTarget = null;
    _isAnimating = false;

    _completeJourney();

    super.dispose();
  }
}

/// Internal representation of a navigation request.
class FlipIntent {
  const FlipIntent.animated({
    required this.targetPage,
    required this.corner,
  }) : animate = true;

  const FlipIntent.instant({required this.targetPage})
    : animate = false,
      corner = FlipCorner.bottomRight;

  final int targetPage;
  final bool animate;
  final FlipCorner corner;
}

/// Avoids calling `clamp()` with an invalid negative upper bound.
int _maxInt(int value, int min) => value < min ? min : value;
