import 'package:flutter/foundation.dart';

import 'package:flip_book/src/rendering/curl_parameters.dart';
import 'package:flip_book/src/rendering/sheet_atlas.dart';

/// The mutable state the curl painter reads, and the only state that changes
/// on the paint-only frame path.
///
/// The scene is a [ChangeNotifier] passed to `CustomPaint(repaint: scene)`.
/// Updating it therefore invalidates painting without rebuilding or relaying
/// out the page widget tree.
///
/// The scene does not own the [SheetAtlas] it references. Atlas lifetime stays
/// with the flip-book/cache layer; the scene only keeps the reference required
/// for the current paint.
@internal
class FlipScene extends ChangeNotifier {
  FlipScene();

  CurlParameters _curl = CurlParameters.rest;
  SheetAtlas? _atlas;
  bool _active = false;

  /// The curl state to draw.
  CurlParameters get curl => _curl;

  /// The currently selected turning-sheet atlas, or `null` when unavailable.
  SheetAtlas? get atlas => _atlas;

  /// Whether the curl painter should draw the turning sheet.
  bool get active => _active;

  // Last state actually published to listeners. This keeps redundant controller
  // ticks and smoothing updates from scheduling an unnecessary paint.
  CurlParameters _painted = CurlParameters.rest;
  SheetAtlas? _paintedAtlas;
  bool _paintedActive = false;

  static const double _paintEpsilon = 1e-4;

  /// Publishes a new frame state.
  ///
  /// When [active] is false the atlas is intentionally discarded from the scene
  /// state. This prevents a stale/disposed atlas from remaining visible to a
  /// later paint after a turn has completed or the texture generation changes.
  ///
  /// The caller retains ownership of [atlas].
  void commit({
    required CurlParameters curl,
    required bool active,
    SheetAtlas? atlas,
  }) {
    final effectiveAtlas = active ? atlas : null;

    final unchanged =
        _paintedActive == active &&
        identical(_paintedAtlas, effectiveAtlas) &&
        (!active || _painted.distanceTo(curl) < _paintEpsilon);

    _curl = curl;
    _active = active;
    _atlas = effectiveAtlas;

    if (unchanged) return;

    _painted = curl;
    _paintedAtlas = effectiveAtlas;
    _paintedActive = active;

    notifyListeners();
  }

  /// Publishes a texture change without changing the geometric state.
  ///
  /// Useful when an atlas finishes preparing while a turn is already active:
  /// the mesh should begin painting the exact same curl state with the newly
  /// available texture.
  void commitAtlas(SheetAtlas? atlas) {
    if (!_active) return;
    if (identical(_atlas, atlas) && identical(_paintedAtlas, atlas)) return;

    _atlas = atlas;
    _paintedAtlas = atlas;
    _paintedActive = true;
    notifyListeners();
  }

  /// Returns the scene to rest.
  ///
  /// The atlas reference is removed from the scene immediately; ownership and
  /// disposal of the atlas remain with the caller.
  void rest() {
    commit(curl: CurlParameters.rest, active: false, atlas: null);
  }

  /// Clears the currently referenced atlas while keeping the scene inactive.
  ///
  /// This is useful when a capture/resize/content generation invalidates all
  /// prepared textures before the next frame is ready.
  void invalidateAtlas() {
    if (_atlas == null && _paintedAtlas == null) return;

    _atlas = null;
    _paintedAtlas = null;
    _active = false;
    _paintedActive = false;
    _curl = CurlParameters.rest;
    _painted = CurlParameters.rest;
    notifyListeners();
  }

  @override
  void dispose() {
    // The scene never owns atlas resources, so disposal only releases the
    // notifier itself and drops Dart references.
    _atlas = null;
    _paintedAtlas = null;
    super.dispose();
  }
}

/// Everything the flip needs to know about which pages are involved.
///
/// A turn always moves one physical sheet. Naming these roles explicitly keeps
/// portrait and spread logic consistent and makes the renderer independent of
/// document type.
@immutable
@internal
class SheetRoles {
  const SheetRoles({
    required this.turningFront,
    required this.revealed,
    required this.direction,
  });

  /// Page currently on the front of the physical sheet being moved.
  final int turningFront;

  /// Page exposed underneath as the sheet moves away.
  final int revealed;

  /// `1` forward, `-1` backward.
  final int direction;

  /// Resolves roles for a turn away from [currentPage].
  ///
  /// Forward: lift the current page and reveal the next.
  ///
  /// Backward: bring the previous page over the current page.
  factory SheetRoles.forTurn({
    required int currentPage,
    required bool forward,
  }) {
    return forward
        ? SheetRoles(
            turningFront: currentPage,
            revealed: currentPage + 1,
            direction: 1,
          )
        : SheetRoles(
            turningFront: currentPage - 1,
            revealed: currentPage,
            direction: -1,
          );
  }

  /// Page index on which the book lands when the turn completes.
  int get destination => direction > 0 ? revealed : turningFront;

  /// Whether the role data refers to a forward turn.
  bool get isForward => direction > 0;

  /// Whether the role data refers to a backward turn.
  bool get isBackward => direction < 0;

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
      'SheetRoles(front: $turningFront, '
      'revealed: $revealed, dir: $direction)';
}
