import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// Perspective projection for the page mesh.
///
/// ## Why this is not a `Matrix4`
///
/// The camera looks straight down the `-z` axis at the centre of the page, with
/// no roll, no off-axis shift and no model transform. A full
/// `perspective · view` matrix multiply for that configuration collapses
/// algebraically to a single divide per vertex:
///
/// ```text
/// s  = eyeDistance / (eyeDistance - z)
/// sx = cx + (x - cx) * s
/// sy = cy + (y - cy) * s
/// ```
///
/// where `(cx, cy)` is the page centre. That is 1 divide and 2 fused
/// multiply-adds per vertex instead of a 16-multiply 4×4 transform plus a
/// perspective divide, and it removes the `vector_math` dependency from the hot
/// path entirely. The reference implementation builds the matrix; the result is
/// identical, and this form makes the two properties we actually care about
/// self-evident:
///
///   * **At `z == 0`, `s == 1`,** so the flat page maps *pixel-exactly* onto its
///     own rectangle. This is what stops the first frame of a curl from
///     jumping, and it is the single most important property of the camera.
///   * **`s` grows as `z` grows** toward the viewer, so a lifted sheet reads as
///     nearer. The divide is the only thing that can misbehave, and [project]
///     guards it explicitly.
///
/// ## Calibrating the eye distance
///
/// [eyeDistanceFor] uses the same relationship as a vertical-FOV perspective
/// matrix, `d = h / (2 tan(fov / 2))`, so the field of view remains the tuning
/// knob even though no matrix is ever built.
@immutable
@internal
class PageCurlCamera {
  const PageCurlCamera({
    required this.pageSize,
    required this.eyeDistance,
  }) : assert(eyeDistance > 0, 'eyeDistance must be positive');

  /// Builds a camera for [pageSize] with a vertical field of view of
  /// [fovY] radians.
  ///
  /// The default of 0.62 rad (~35.5°) is a mild perspective: enough for a
  /// lifted page to read as three-dimensional, shallow enough that the page
  /// corners do not visibly splay. A wider FOV brings the eye closer and
  /// exaggerates the lift.
  factory PageCurlCamera.forPage(Size pageSize, {double fovY = defaultFovY}) {
    return PageCurlCamera(
      pageSize: pageSize,
      eyeDistance: eyeDistanceFor(pageSize.height, fovY),
    );
  }

  /// ~35.5°. See [PageCurlCamera.forPage].
  static const double defaultFovY = 0.62;

  /// Distance from the eye to the `z = 0` page plane for a page of height [h]
  /// at a vertical field of view of [fovY] radians.
  static double eyeDistanceFor(double h, double fovY) {
    final half = fovY.clamp(0.02, math.pi - 0.02) * 0.5;
    return h / (2.0 * math.tan(half));
  }

  /// The logical page rectangle the camera is calibrated against.
  final Size pageSize;

  /// Distance from the eye to the `z = 0` plane, in logical pixels.
  final double eyeDistance;

  /// Largest `z` that still projects safely.
  ///
  /// Beyond this the vertex is at or behind the eye and the divide diverges.
  /// The margin keeps `s` bounded by `eyeDistance / (0.25 * eyeDistance) == 4`,
  /// so a bad curl parameter produces a large page rather than one that
  /// explodes to infinity.
  double get maxSafeZ => eyeDistance * 0.75;

  /// Projects a single 3D page-space point to screen space.
  ///
  /// [origin] offsets the result, for a page drawn somewhere other than the
  /// top-left of the canvas (a landscape spread's right half, say).
  ///
  /// `z` is clamped to [maxSafeZ] rather than allowed to diverge: a clamped
  /// vertex is visibly wrong in a way that is easy to debug, whereas an
  /// infinite one corrupts the whole draw call and can take the raster thread
  /// with it.
  Offset project(double x, double y, double z, {Offset origin = Offset.zero}) {
    final cx = pageSize.width * 0.5;
    final cy = pageSize.height * 0.5;
    final safeZ = z.isFinite ? math.min(z, maxSafeZ) : 0.0;
    final s = eyeDistance / (eyeDistance - safeZ);
    return Offset(
      origin.dx + cx + (x - cx) * s,
      origin.dy + cy + (y - cy) * s,
    );
  }

  /// Projects a packed `[x, y, z, ...]` buffer into a packed `[x, y, ...]`
  /// buffer, in place and without allocating.
  ///
  /// Returns the number of vertices that had to be clamped or repaired. The
  /// caller uses that count as a health signal: a handful is a steep but legal
  /// curl, while most of the mesh means the curl parameters are wrong and the
  /// frame should fall back to drawing the page flat rather than rendering
  /// garbage.
  int projectBuffer(
    List<double> world,
    List<double> screen,
    int vertexCount, {
    Offset origin = Offset.zero,
  }) {
    final cx = pageSize.width * 0.5;
    final cy = pageSize.height * 0.5;
    final ox = origin.dx;
    final oy = origin.dy;
    final eye = eyeDistance;
    final limit = maxSafeZ;
    var bad = 0;

    for (var i = 0; i < vertexCount; i++) {
      final x = world[i * 3];
      final y = world[i * 3 + 1];
      var z = world[i * 3 + 2];

      if (!x.isFinite || !y.isFinite || !z.isFinite) {
        // Fall back to the vertex's flat resting place. It is always a sane
        // value, and one stray vertex snapping flat is far less visible than
        // a triangle stretched to the edge of the canvas.
        bad++;
        screen[i * 2] = ox + (x.isFinite ? x : cx);
        screen[i * 2 + 1] = oy + (y.isFinite ? y : cy);
        continue;
      }
      if (z > limit) {
        bad++;
        z = limit;
      }

      final s = eye / (eye - z);
      screen[i * 2] = ox + cx + (x - cx) * s;
      screen[i * 2 + 1] = oy + cy + (y - cy) * s;
    }
    return bad;
  }

  /// The perspective scale applied at depth [z]. `1.0` at the page plane.
  double scaleAt(double z) {
    final safeZ = z.isFinite ? math.min(z, maxSafeZ) : 0.0;
    return eyeDistance / (eyeDistance - safeZ);
  }

  PageCurlCamera copyWith({Size? pageSize, double? eyeDistance}) =>
      PageCurlCamera(
        pageSize: pageSize ?? this.pageSize,
        eyeDistance: eyeDistance ?? this.eyeDistance,
      );

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
      'PageCurlCamera(page: $pageSize, eye: ${eyeDistance.toStringAsFixed(1)})';
}
