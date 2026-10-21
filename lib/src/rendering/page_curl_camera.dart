import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// Perspective projection for the page mesh.
///
/// The camera looks straight down the `-z` axis with no roll or off-axis shift.
/// For that restricted camera model the perspective transform collapses to:
///
/// ```text
/// s  = eyeDistance / (eyeDistance - z)
/// sx = cx + (x - cx) * s
/// sy = cy + (y - cy) * s
/// ```
///
/// Keeping this explicit avoids a general matrix multiply in the hot path while
/// preserving the important invariant: when `z == 0`, `s == 1` and the flat
/// page maps exactly onto its logical rectangle.
@immutable
@internal
class PageCurlCamera {
  PageCurlCamera({required this.pageSize, required this.eyeDistance})
    : assert(
        pageSize.width > 0 && pageSize.height > 0,
        'pageSize must be non-empty',
      ),
      assert(
        pageSize.width.isFinite && pageSize.height.isFinite,
        'pageSize must be finite',
      ),
      assert(
        eyeDistance.isFinite && eyeDistance > 0,
        'eyeDistance must be finite and positive',
      );

  /// Builds a camera for [pageSize] with vertical field of view [fovY].
  factory PageCurlCamera.forPage(Size pageSize, {double fovY = defaultFovY}) {
    _validatePageSize(pageSize);

    final safeFov = fovY.isFinite
        ? fovY.clamp(_minFov, _maxFov).toDouble()
        : defaultFovY;

    final eye = eyeDistanceFor(pageSize.height, safeFov);

    return PageCurlCamera(pageSize: pageSize, eyeDistance: eye);
  }

  /// Mild perspective: enough to reveal lift without excessive corner splay.
  static const double defaultFovY = 0.62;

  static const double _minFov = 0.02;
  static const double _maxFov = 3.121592653589793;

  /// Distance from the eye to the `z = 0` page plane.
  ///
  /// Derived from the usual vertical-FOV relationship:
  ///
  /// `d = h / (2 * tan(fov / 2))`.
  static double eyeDistanceFor(double h, double fovY) {
    if (!h.isFinite || h <= 0) {
      throw ArgumentError.value(h, 'h', 'must be finite and greater than zero');
    }

    final safeFov = fovY.isFinite
        ? fovY.clamp(_minFov, _maxFov).toDouble()
        : defaultFovY;

    final half = safeFov * 0.5;
    final tangent = math.tan(half);

    if (!tangent.isFinite || tangent <= 0) {
      throw ArgumentError.value(
        fovY,
        'fovY',
        'produces an invalid perspective tangent',
      );
    }

    final eye = h / (2.0 * tangent);

    if (!eye.isFinite || eye <= 0) {
      throw StateError(
        'Calculated invalid eye distance $eye for height=$h and fovY=$fovY.',
      );
    }

    return eye;
  }

  /// The logical page rectangle the camera is calibrated against.
  final Size pageSize;

  /// Distance from the eye to the `z = 0` page plane.
  final double eyeDistance;

  /// Largest positive `z` that is projected directly.
  ///
  /// The eye itself is at `z == eyeDistance`. Keeping the safe limit below that
  /// point prevents the perspective denominator from approaching zero.
  ///
  /// At the current limit:
  ///
  /// `scale <= eyeDistance / (eyeDistance * 0.25) == 4`.
  double get maxSafeZ => eyeDistance * 0.75;

  /// Projects one 3D page-space point to screen space.
  ///
  /// A vertex above [maxSafeZ] is clamped. Non-finite input is repaired to the
  /// corresponding centre point, and the caller can use [projectBuffer]'s bad
  /// count to decide whether the frame should be rejected.
  Offset project(double x, double y, double z, {Offset origin = Offset.zero}) {
    final cx = pageSize.width * 0.5;
    final cy = pageSize.height * 0.5;
    final safeZ = _safeZ(z);
    final denominator = eyeDistance - safeZ;

    // maxSafeZ guarantees this remains positive, but keep the guard here so
    // this method remains robust if the safety policy changes later.
    if (!denominator.isFinite || denominator <= 0) {
      return Offset(origin.dx + cx, origin.dy + cy);
    }

    final scale = eyeDistance / denominator;

    final safeX = x.isFinite ? x : cx;
    final safeY = y.isFinite ? y : cy;

    return Offset(
      origin.dx + cx + (safeX - cx) * scale,
      origin.dy + cy + (safeY - cy) * scale,
    );
  }

  /// Projects a packed `[x, y, z, ...]` buffer into `[x, y, ...]`.
  ///
  /// No temporary Dart collections are allocated. The return value counts
  /// vertices that were repaired or clamped so the renderer can reject a
  /// severely unhealthy frame instead of submitting stretched geometry.
  int projectBuffer(
    List<double> world,
    List<double> screen,
    int vertexCount, {
    Offset origin = Offset.zero,
  }) {
    final availableWorldVertices = world.length ~/ 3;
    final availableScreenVertices = screen.length ~/ 2;

    final count = vertexCount
        .clamp(0, math.min(availableWorldVertices, availableScreenVertices))
        .toInt();

    final cx = pageSize.width * 0.5;
    final cy = pageSize.height * 0.5;
    final ox = origin.dx;
    final oy = origin.dy;
    final eye = eyeDistance;
    final limit = maxSafeZ;

    var bad = 0;

    for (var i = 0; i < count; i++) {
      final worldOffset = i * 3;
      final screenOffset = i * 2;

      final x = world[worldOffset];
      final y = world[worldOffset + 1];
      var z = world[worldOffset + 2];

      var repaired = false;

      var safeX = x;
      var safeY = y;

      if (!safeX.isFinite) {
        safeX = cx;
        repaired = true;
      }

      if (!safeY.isFinite) {
        safeY = cy;
        repaired = true;
      }

      if (!z.isFinite) {
        z = 0.0;
        repaired = true;
      } else if (z > limit) {
        z = limit;
        repaired = true;
      }

      final denominator = eye - z;

      if (!denominator.isFinite || denominator <= 0) {
        z = math.min(0.0, limit);
        repaired = true;
      }

      final scale = eye / (eye - z);

      screen[screenOffset] = ox + cx + (safeX - cx) * scale;
      screen[screenOffset + 1] = oy + cy + (safeY - cy) * scale;

      if (!screen[screenOffset].isFinite ||
          !screen[screenOffset + 1].isFinite) {
        screen[screenOffset] = ox + cx;
        screen[screenOffset + 1] = oy + cy;
        repaired = true;
      }

      if (repaired) bad++;
    }

    // A mismatched buffer length is itself a bad frame. Clamp-and-draw would
    // leave the remaining output positions untouched from a previous frame,
    // which can be much harder to diagnose than a rejected frame.
    if (count != vertexCount) {
      bad += (vertexCount - count).abs();
    }

    return bad;
  }

  /// Perspective scale applied at depth [z].
  ///
  /// Exactly `1.0` on the page plane.
  double scaleAt(double z) {
    final safeZ = _safeZ(z);
    final denominator = eyeDistance - safeZ;

    if (!denominator.isFinite || denominator <= 0) {
      return 1.0;
    }

    final scale = eyeDistance / denominator;
    return scale.isFinite && scale > 0 ? scale : 1.0;
  }

  PageCurlCamera copyWith({Size? pageSize, double? eyeDistance}) =>
      PageCurlCamera(
        pageSize: pageSize ?? this.pageSize,
        eyeDistance: eyeDistance ?? this.eyeDistance,
      );

  double _safeZ(double z) {
    if (!z.isFinite) return 0.0;
    return math.min(z, maxSafeZ);
  }

  static void _validatePageSize(Size pageSize) {
    if (!pageSize.width.isFinite ||
        !pageSize.height.isFinite ||
        pageSize.width <= 0 ||
        pageSize.height <= 0) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'must be finite and non-empty',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PageCurlCamera &&
          other.pageSize == pageSize &&
          other.eyeDistance == eyeDistance;

  @override
  int get hashCode => Object.hash(pageSize, eyeDistance);

  @override
  String toString() =>
      'PageCurlCamera(page: $pageSize, '
      'eye: ${eyeDistance.toStringAsFixed(1)})';
}
