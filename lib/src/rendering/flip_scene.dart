import 'package:flutter/foundation.dart';

import 'package:flip_book/src/rendering/curl_parameters.dart';
import 'package:flip_book/src/rendering/sheet_atlas.dart';

/// The mutable state the curl painter reads, and the only thing that changes
/// during a flip.
///
/// ## Why this is a [ChangeNotifier] and not widget state
///
/// A page turn updates on every frame. Routing that through `setState` rebuilds
/// the widget subtree sixty times a second, which in the previous renderer
/// meant rebuilding three or four full page subtrees per frame — and for a PDF,
/// re-rasterising the same page twice.
///
/// Instead the scene is a plain listenable handed to `CustomPaint(painter:
/// ...)` as its `repaint` argument. Writing to it marks the render object dirty
/// for *paint only*: no rebuild, no relayout, and repeated writes within one
/// frame coalesce into a single repaint. The widget tree is untouched for the
/// entire duration of a flip.
///
/// ## The frame filter
///
/// [commit] compares the incoming state against what was last painted and
/// stays silent when nothing visible changed. A finger held still, the first
/// tick of a settle that has not moved yet, a clamped overshoot — all of these
/// would otherwise schedule a full deform/project/sort pass to produce an
/// identical image.
@internal
class FlipScene extends ChangeNotifier {
  FlipScene();

  CurlParameters _curl = CurlParameters.rest;
  SheetAtlas? _atlas;
  bool _active = false;

  /// The curl state to draw.
  CurlParameters get curl => _curl;

  /// The packed front/back faces of the turning sheet, or `null` when no
  /// texture is ready. The painter draws nothing in that case rather than
  /// showing a blank sheet.
  SheetAtlas? get atlas => _atlas;

  /// Whether a turn is in progress. When false the reader shows its live page
  /// and the curl surface is inert.
  bool get active => _active;

  CurlParameters _painted = CurlParameters.rest;
  SheetAtlas? _paintedAtlas;
  bool _paintedActive = false;

  /// Publishes new state, notifying only if it would change the image.
  void commit({
    required CurlParameters curl,
    required bool active,
    SheetAtlas? atlas,
  }) {
    _curl = curl;
    _active = active;
    _atlas = atlas;

    final unchanged = _paintedActive == active &&
        identical(_paintedAtlas, atlas) &&
        (!active || _painted.distanceTo(curl) < 1e-4);
    if (unchanged) return;

    _painted = curl;
    _paintedAtlas = atlas;
    _paintedActive = active;
    notifyListeners();
  }

  /// Returns the sheet to rest without drawing a curl.
  void rest() => commit(curl: CurlParameters.rest, active: false);
}

/// Everything the flip needs to know about which pages are involved.
///
/// A turn always moves one physical sheet. Naming the roles explicitly — rather
/// than deriving them inline at three different call sites, as the previous
/// renderer did — is what keeps the spread and portrait paths in agreement.
@immutable
@internal
class SheetRoles {
  const SheetRoles({
    required this.turningFront,
    required this.revealed,
    required this.direction,
  });

  /// The page on the front of the sheet being turned.
  final int turningFront;

  /// The page exposed underneath as the sheet lifts away.
  final int revealed;

  /// `1` forward, `-1` backward.
  final int direction;

  /// Resolves the roles for a turn away from [currentPage].
  ///
  /// A forward turn lifts the current page to reveal the next. A backward turn
  /// brings the previous page back over the current one, so the sheet being
  /// moved is the *previous* one and what it reveals is the current page.
  factory SheetRoles.forTurn({
    required int currentPage,
    required bool forward,
  }) {
    if (forward) {
      return SheetRoles(
        turningFront: currentPage,
        revealed: currentPage + 1,
        direction: 1,
      );
    }
    return SheetRoles(
      turningFront: currentPage - 1,
      revealed: currentPage,
      direction: -1,
    );
  }

  /// The page index the book lands on when this turn completes.
  int get destination => direction > 0 ? revealed : turningFront;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SheetRoles &&
          other.turningFront == turningFront &&
          other.revealed == revealed &&
          other.direction == direction;

  @override
  int get hashCode => Object.hash(turningFront, revealed, direction);

  @override
  String toString() =>
      'SheetRoles(front: $turningFront, revealed: $revealed, dir: $direction)';
}
