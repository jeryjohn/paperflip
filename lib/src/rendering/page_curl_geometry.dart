import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'package:flip_book/src/rendering/curl_parameters.dart';
import 'package:flip_book/src/rendering/page_curl_mesh.dart';

/// Deforms the flat page mesh into a curled sheet.
///
/// This is the geometric core of the renderer. It writes only into the
/// reusable buffers owned by [PageCurlMesh]; it does not allocate widgets,
/// canvases, images, or other render objects.
///
/// The main invariant is that the curl itself is developable: bending changes
/// orientation and depth without intentionally stretching the paper. The
/// optional `droop` parameter is kept as a separate, explicitly non-isometric
/// visual effect and is therefore excluded from the strict isometry diagnostic.
@internal
class PageCurlGeometry {
  const PageCurlGeometry();

  /// Below this wrap angle the curved portion is numerically indistinguishable
  /// from a flat sheet.
  ///
  /// Importantly, a small wrap angle does **not** mean the whole page should be
  /// reset to the original screen position: near the end of a turn the page is
  /// nearly flat but is also nearly rotated by 180 degrees. In that situation
  /// [deform] uses the exact rigidly-rotated flat limit instead of snapping to
  /// the original flat page.
  static const double flatEpsilon = 1e-4;

  /// Below this, `atan2(b, a) / b` uses its analytic Taylor limit.
  static const double taylorEpsilon = 1e-7;

  /// Maximum allowed sine of the cone half-angle.
  static const double maxConeSin = 0.85;

  /// Largest permitted `|kappa * axial|`.
  ///
  /// Keeping this below one prevents a row from crossing the cone apex where
  /// the parameterisation becomes singular.
  static const double maxApexInfluence = 0.8;

  /// `sin^2(pi*t)`: zero value and zero slope at both ends.
  static double bump(double t) {
    final x = _finiteClamp(t, 0.0, 1.0);
    final s = math.sin(math.pi * x);
    return s * s;
  }

  /// Smoothstep with zero derivative at both ends.
  static double smoothstep(double t) {
    final x = _finiteClamp(t, 0.0, 1.0);
    return x * x * (3.0 - 2.0 * x);
  }

  /// Rigid rotation about the page spine.
  static double _phi(double progress) => math.pi * smoothstep(progress);

  /// Deforms [mesh] in place for [params].
  ///
  /// [spineAtCentre] selects a centre hinge for landscape spreads. For a normal
  /// portrait page, the hinge is the page's appropriate outer edge.
  void deform(
    PageCurlMesh mesh,
    CurlParameters params, {
    bool spineAtCentre = false,
  }) {
    final w = mesh.pageSize.width;
    final h = mesh.pageSize.height;

    if (!w.isFinite ||
        !h.isFinite ||
        w <= 0 ||
        h <= 0 ||
        mesh.columns < 1 ||
        mesh.rows < 1) {
      mesh.resetToFlat();
      return;
    }

    final t = _finiteClamp(params.progress, 0.0, 1.0);

    final dir = params.direction >= 0 ? 1.0 : -1.0;

    // Exact resting state. This must match the live page pixel-for-pixel at
    // the moment the curl starts.
    if (t <= 0.0 && dir > 0 && !spineAtCentre) {
      mesh.resetToFlat();
      return;
    }
    final b = bump(t);

    final bendAmount = _finiteNonNegative(params.bendAmount);
    final wrapAngle = bendAmount * b;

    final leafW = spineAtCentre ? w * 0.5 : w;
    final spineX = spineAtCentre ? w * 0.5 : (dir > 0 ? 0.0 : w);

    final phi = _phi(t);
    final cosPhi = math.cos(phi);
    final sinPhi = math.sin(phi);

    final grabV = _finiteClamp(params.grabV, 0.0, 1.0);
    final droop = _finiteNonNegative(params.droop);

    // Once the cone curvature becomes numerically tiny, use the exact flat
    // surface rotated around its hinge. This is the important end-of-turn
    // continuity fix: progress can approach 1.0 with phi -> pi while the
    // physical curl radius tends to infinity.
    if (wrapAngle < flatEpsilon) {
      _deformRigidFlat(
        mesh: mesh,
        rows: mesh.rows,
        cols: mesh.columns,
        leafW: leafW,
        spineX: spineX,
        dir: dir,
        cosPhi: cosPhi,
        sinPhi: sinPhi,
        originY: h * 0.5,
      );
      return;
    }

    final r0 = leafW / wrapAngle;
    if (!r0.isFinite || r0 <= 0) {
      _deformRigidFlat(
        mesh: mesh,
        rows: mesh.rows,
        cols: mesh.columns,
        leafW: leafW,
        spineX: spineX,
        dir: dir,
        cosPhi: cosPhi,
        sinPhi: sinPhi,
        originY: h * 0.5,
      );
      return;
    }

    final coneSin = _resolveConeSin(params.conicity, r0: r0, pageHeight: h);
    final kappa = coneSin / r0;

    final cosTheta = math.sqrt(math.max(0.0, 1.0 - coneSin * coneSin));

    final sagAmp = droop * b * h;

    _deformRows(
      mesh: mesh,
      cols: mesh.columns,
      rows: mesh.rows,
      h: h,
      leafW: leafW,
      spineX: spineX,
      dir: dir,
      r0: r0,
      kappa: kappa,
      cosTheta: cosTheta,
      cosPhi: cosPhi,
      sinPhi: sinPhi,
      sagAmp: sagAmp,
      grabV: grabV,
    );
  }

  /// Clamps cone strength to both the valid trigonometric domain and the
  /// singularity-avoidance bound.
  static double _resolveConeSin(
    double conicity, {
    required double r0,
    required double pageHeight,
  }) {
    if (!conicity.isFinite || conicity == 0.0) {
      return 0.0;
    }

    if (!r0.isFinite || r0 <= 0 || !pageHeight.isFinite || pageHeight <= 0) {
      return 0.0;
    }

    final apexLimit = 2.0 * maxApexInfluence * r0 / pageHeight;

    final boundedLimit = math.min(maxConeSin, apexLimit);

    if (!boundedLimit.isFinite || boundedLimit <= 0) {
      return 0.0;
    }

    final requested = _finiteClamp(conicity, -1.0, 1.0) * maxConeSin;

    return requested.clamp(-boundedLimit, boundedLimit).toDouble();
  }

  /// Exact rigid limit of the developable surface as the curvature goes to zero.
  ///
  /// This is not the same as [PageCurlMesh.resetToFlat]: the sheet may already
  /// be almost fully rotated when the curvature vanishes at the end of a turn.
  void _deformRigidFlat({
    required PageCurlMesh mesh,
    required int cols,
    required int rows,
    required double leafW,
    required double spineX,
    required double dir,
    required double cosPhi,
    required double sinPhi,
    required double originY,
  }) {
    final world = mesh.worldPositions;

    for (var row = 0; row <= rows; row++) {
      final v = rows == 0 ? 0.0 : row / rows;
      final axial = (v - 0.5) * mesh.pageSize.height;

      for (var col = 0; col <= cols; col++) {
        final u = cols == 0 ? 0.0 : col / cols;
        final cross = u * leafW;

        final rotatedCross = cross * cosPhi;
        final rotatedLift = cross * sinPhi;

        final i = row * (cols + 1) + col;

        world[i * 3] = spineX + dir * rotatedCross;
        world[i * 3 + 1] = originY + axial;
        world[i * 3 + 2] = rotatedLift;
      }
    }
  }

  void _deformRows({
    required PageCurlMesh mesh,
    required int cols,
    required int rows,
    required double h,
    required double leafW,
    required double spineX,
    required double dir,
    required double r0,
    required double kappa,
    required double cosTheta,
    required double cosPhi,
    required double sinPhi,
    required double sagAmp,
    required double grabV,
  }) {
    final world = mesh.worldPositions;
    final halfH = h * 0.5;

    for (var row = 0; row <= rows; row++) {
      final v = rows == 0 ? 0.0 : row / rows;

      // Axial coordinate along the spine, measured from the page's vertical
      // centre.
      final axial = (v - 0.5) * h;
      final a = 1.0 + kappa * axial;

      // The non-isometric droop is intentionally tiny and is gated at both
      // ends by bump(). The strict isometry diagnostic is intended for droop=0.
      final sagRow = sagAmp * (v - grabV).abs();

      for (var col = 0; col <= cols; col++) {
        final u = cols == 0 ? 0.0 : col / cols;
        final cross = u * leafW;

        final bb = kappa * cross;
        final rho = math.sqrt(math.max(0.0, a * a + bb * bb));

        if (!rho.isFinite || rho <= 0 || a <= 0) {
          // Should be unreachable because _resolveConeSin keeps the apex away
          // from the page, but fail into a finite limit instead of emitting
          // NaN/Infinity into the renderer.
          final i = row * (cols + 1) + col;
          final rotatedCross = cross * cosPhi;
          final rotatedLift = cross * sinPhi;
          world[i * 3] = spineX + dir * rotatedCross;
          world[i * 3 + 1] = halfH + axial;
          world[i * 3 + 2] = rotatedLift;
          continue;
        }

        final g = bb.abs() > taylorEpsilon
            ? math.atan2(bb, a) / bb
            : 1.0 / a - bb * bb / (3.0 * a * a * a);

        final beta = cross * g / r0;
        final cosBeta = math.cos(beta);
        final sinBeta = math.sin(beta);

        // Algebraically equivalent to (rho - 1) / kappa, but without a
        // division by kappa, so the cylinder limit remains numerically stable.
        final hAxial =
            (2.0 * axial + kappa * (axial * axial + cross * cross)) /
            (rho + 1.0);

        final localAxial = hAxial - rho * r0 * r0 * kappa * (1.0 - cosBeta);

        final localCross = rho * r0 * sinBeta;
        final localLift = rho * r0 * (1.0 - cosBeta) * cosTheta;

        // Uniform rotation about the spine is rigid and therefore does not
        // compromise the developable mapping.
        final xr = localCross * cosPhi - localLift * sinPhi;
        final zr = localCross * sinPhi + localLift * cosPhi;

        final i = row * (cols + 1) + col;

        world[i * 3] = spineX + dir * xr;

        // Droop is a deliberately non-isometric visual weight effect. It is
        // kept separate from the actual cone/cylinder parameterisation and is
        // zero at both ends of the gesture.
        world[i * 3 + 1] = halfH + localAxial + sagRow * u;

        world[i * 3 + 2] = zr;
      }
    }
  }

  /// Computes per-vertex normals from the deformed surface by central
  /// differences across the grid.
  ///
  /// Degenerate differences fall back to a stable page normal rather than
  /// emitting NaN values.
  void computeNormals(PageCurlMesh mesh) {
    final cols = mesh.columns;
    final rows = mesh.rows;
    final world = mesh.worldPositions;
    final normals = mesh.normals;
    final stride = cols + 1;

    for (var row = 0; row <= rows; row++) {
      for (var col = 0; col <= cols; col++) {
        final i = row * stride + col;

        final left = row * stride + (col > 0 ? col - 1 : col);
        final right = row * stride + (col < cols ? col + 1 : col);
        final up = (row > 0 ? row - 1 : row) * stride + col;
        final down = (row < rows ? row + 1 : row) * stride + col;

        final tx = world[right * 3] - world[left * 3];
        final ty = world[right * 3 + 1] - world[left * 3 + 1];
        final tz = world[right * 3 + 2] - world[left * 3 + 2];

        final sx = world[down * 3] - world[up * 3];
        final sy = world[down * 3 + 1] - world[up * 3 + 1];
        final sz = world[down * 3 + 2] - world[up * 3 + 2];

        var nx = ty * sz - tz * sy;
        var ny = tz * sx - tx * sz;
        var nz = tx * sy - ty * sx;

        final len = math.sqrt(nx * nx + ny * ny + nz * nz);

        if (len < 1e-9 || !len.isFinite) {
          nx = 0.0;
          ny = 0.0;
          nz = -1.0;
        } else {
          nx /= len;
          ny /= len;
          nz /= len;
        }

        normals[i * 3] = nx;
        normals[i * 3 + 1] = ny;
        normals[i * 3 + 2] = nz;
      }
    }
  }

  // ── Debug / test support ──────────────────────────────────────────────────

  /// Checks the invariants the renderer depends on.
  ///
  /// Returns a human-readable failure description, or `null` when the
  /// geometry buffers contain finite/valid values.
  static String? debugValidate(PageCurlMesh mesh, CurlParameters params) {
    final world = mesh.worldPositions;
    final normals = mesh.normals;

    for (var i = 0; i < mesh.vertexCount; i++) {
      final x = world[i * 3];
      final y = world[i * 3 + 1];
      final z = world[i * 3 + 2];

      if (!x.isFinite || !y.isFinite || !z.isFinite) {
        return 'vertex $i is not finite: ($x, $y, $z) for $params';
      }

      final nx = normals[i * 3];
      final ny = normals[i * 3 + 1];
      final nz = normals[i * 3 + 2];

      if (!nx.isFinite || !ny.isFinite || !nz.isFinite) {
        return 'normal $i is not finite: ($nx, $ny, $nz) for $params';
      }

      final normalLength = math.sqrt(nx * nx + ny * ny + nz * nz);

      if (!normalLength.isFinite || (normalLength - 1.0).abs() > 1e-3) {
        return 'normal $i is not unit length: $normalLength';
      }
    }

    for (var i = 0; i < mesh.indices.length; i++) {
      if (mesh.indices[i] >= mesh.vertexCount) {
        return 'index $i out of range: '
            '${mesh.indices[i]} >= ${mesh.vertexCount}';
      }
    }

    return null;
  }

  /// The wrap angle reached at the free edge of row [v].
  static double debugWrapAngleAtRow(
    CurlParameters params,
    Size pageSize,
    double v, {
    bool spineAtCentre = false,
  }) {
    if (!pageSize.width.isFinite ||
        !pageSize.height.isFinite ||
        pageSize.width <= 0 ||
        pageSize.height <= 0) {
      return 0.0;
    }

    final t = _finiteClamp(params.progress, 0.0, 1.0);
    final bendAmount = _finiteNonNegative(params.bendAmount);
    final wrapAngle = bendAmount * bump(t);

    if (wrapAngle < flatEpsilon) {
      return 0.0;
    }

    final leafW = spineAtCentre ? pageSize.width * 0.5 : pageSize.width;

    final r0 = leafW / wrapAngle;
    if (!r0.isFinite || r0 <= 0) {
      return 0.0;
    }

    final coneSin = _resolveConeSin(
      params.conicity,
      r0: r0,
      pageHeight: pageSize.height,
    );
    final kappa = coneSin / r0;

    final axial = (_finiteClamp(v, 0.0, 1.0) - 0.5) * pageSize.height;
    final a = 1.0 + kappa * axial;
    final cross = leafW;
    final bb = kappa * cross;

    if (!a.isFinite || a <= 0) {
      return 0.0;
    }

    final g = bb.abs() > taylorEpsilon
        ? math.atan2(bb, a) / bb
        : 1.0 / a - bb * bb / (3.0 * a * a * a);

    return cross * g / r0;
  }

  /// Largest relative error by which the deformation fails to preserve the
  /// length of adjacent grid edges.
  ///
  /// The strict developable part should be tested with `droop: 0`. A finite
  /// residual is expected because the renderer samples a curved continuous
  /// surface with straight mesh edges; the error should converge roughly as
  /// mesh spacing squared.
  static double debugMaxIsometryError(
    PageCurlMesh mesh, {
    bool spineAtCentre = false,
  }) {
    final world = mesh.worldPositions;
    final cols = mesh.columns;
    final rows = mesh.rows;
    final stride = cols + 1;

    final leafW = spineAtCentre
        ? mesh.pageSize.width * 0.5
        : mesh.pageSize.width;

    if (cols < 1 || rows < 1 || leafW <= 0 || mesh.pageSize.height <= 0) {
      return double.infinity;
    }

    final flatDx = leafW / cols;
    final flatDy = mesh.pageSize.height / rows;
    var worst = 0.0;

    double lengthBetween(int i, int j) {
      final dx = world[i * 3] - world[j * 3];
      final dy = world[i * 3 + 1] - world[j * 3 + 1];
      final dz = world[i * 3 + 2] - world[j * 3 + 2];
      return math.sqrt(dx * dx + dy * dy + dz * dz);
    }

    for (var row = 0; row <= rows; row++) {
      for (var col = 0; col <= cols; col++) {
        final i = row * stride + col;

        if (col < cols) {
          final length = lengthBetween(i, i + 1);
          final err = (length - flatDx).abs() / flatDx;
          if (!err.isFinite) return double.infinity;
          if (err > worst) worst = err;
        }

        if (row < rows) {
          final length = lengthBetween(i, i + stride);
          final err = (length - flatDy).abs() / flatDy;
          if (!err.isFinite) return double.infinity;
          if (err > worst) worst = err;
        }
      }
    }

    return worst;
  }

  static double _finiteClamp(double value, double min, double max) {
    if (!value.isFinite) return min;
    return value.clamp(min, max).toDouble();
  }

  static double _finiteNonNegative(double value) {
    if (!value.isFinite || value <= 0) return 0.0;
    return value;
  }
}
