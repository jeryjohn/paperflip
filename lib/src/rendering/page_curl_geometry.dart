import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'package:flip_book/src/rendering/curl_parameters.dart';
import 'package:flip_book/src/rendering/page_curl_mesh.dart';

/// Deforms the flat page mesh into a curled sheet.
///
/// This is the heart of the renderer. It is pure — no Flutter, no canvas, no
/// allocation — which is what makes it testable against the invariants in
/// [debugValidate] and [debugMaxIsometryError]. A fold is very hard to eyeball
/// at 95% progress and very easy to assert on.
///
/// ## The surface must be developable
///
/// Paper can bend but not stretch. A surface with that property is called
/// *developable*: it can be flattened onto a plane without distortion. If the
/// page mesh is not developable, the texture rubber-bands — text smears and
/// compresses as the sheet moves — and no amount of lighting hides it.
///
/// So the requirement is stronger than "looks curved": the map from flat page
/// coordinates to 3D must be an **isometry**, preserving every distance.
/// [debugMaxIsometryError] measures exactly that, and the geometry tests assert
/// it stays at floating-point noise.
///
/// ## One formula for cone, cylinder and inverted cone
///
/// A grab at the middle of the free edge bends the page around a **cylinder**.
/// A grab at a corner bends it around a **cone** — tight at the held corner,
/// opening out toward the far edge. A grab at the opposite corner gives the
/// mirrored, *inverted* cone. A renderer needs all three, and needs to move
/// between them without a visible switch.
///
/// The obvious approach — compute a cone and a cylinder, then blend the
/// resulting positions — is what the best-known published implementation does,
/// and it is wrong: a blend of two isometries is not an isometry, so the paper
/// stretches at every intermediate value, worst exactly in the middle where
/// most grabs land.
///
/// Instead, this uses a single cone parameterised by the **signed reciprocal of
/// the distance to its apex**:
///
/// ```text
/// kappa = 1 / L        L = signed distance from the page to the cone's apex
/// ```
///
/// A cone whose apex recedes to infinity *is* a cylinder. So `kappa == 0` is
/// not a blend toward a cylinder or an approximation of one — it is the
/// cylinder, exactly, and the sign of `kappa` selects which side the apex
/// falls on and hence whether the cone is upright or inverted. One branch-free
/// formula covers the whole family, every member of it an exact isometry.
///
/// Writing `L = 1 / kappa` naively divides by zero at the cylinder. Every such
/// term cancels analytically, and [_deformRow] uses the cancelled forms:
///
/// ```text
/// rho = sqrt(a^2 + b^2)          a = 1 + kappa*t,  b = kappa*s
/// H   = (2t + kappa*(t^2 + s^2)) / (rho + 1)     // == (rho - 1)/kappa
/// G   = atan2(b, a) / b                          // Taylor series as b -> 0
/// ```
///
/// Each is a ratio of polynomials and `atan2`, analytic in `kappa` around zero,
/// so the family is smooth across the cylinder rather than merely continuous.
///
/// ## The diagonal fold comes free
///
/// The half-turn ruling sits where `beta == pi`. Because `beta` depends on the
/// axial coordinate through `a = 1 + kappa*t`, that ruling is **not** parallel
/// to the spine when `kappa != 0`: the fold runs diagonally across the page, by
/// over 40% of the leaf width at moderate cone strength.
///
/// This matters because the usual way to get a diagonal crease is to shear the
/// rotation angle per row — and a per-row rotation is not rigid, so it breaks
/// the isometry the cone was chosen to preserve. Here the diagonal is a
/// *consequence* of the cone, at no cost. The rotation applied on top
/// ([_phi]) is therefore uniform across the sheet, and rigid.
///
/// ## Landing flat
///
/// Curvature is gated by `bump = sin^2(pi * t)`, whose value *and* first
/// derivative vanish at both ends. Curvature arrives and leaves with zero
/// velocity, which is what stops the sheet snapping flat in the last few
/// percent of the turn. `sin(pi * t)` peaks identically but has slope `+/-pi`
/// at the ends, and that slope is visible as a pop.
@internal
class PageCurlGeometry {
  const PageCurlGeometry();

  /// Below this wrap angle the sheet is treated as flat.
  ///
  /// The fold radius is `leafW / a`, which diverges as `a -> 0`, so the flat
  /// case uses its closed-form limit rather than dividing by something tiny.
  static const double flatEpsilon = 1e-4;

  /// Below this, `atan2(b, a) / b` is evaluated by its Taylor series.
  ///
  /// The expression is perfectly well-behaved in the limit (`-> 1/a`) but
  /// computes as `0 / 0` in floating point.
  static const double taylorEpsilon = 1e-7;

  /// Hard ceiling on `sin(theta)`, the cone's half-angle sine.
  ///
  /// `cos(theta) = sqrt(1 - sin^2(theta))` needs this strictly below 1. The
  /// margin also keeps the cone from degenerating into a flat fan.
  static const double maxConeSin = 0.85;

  /// Largest `|kappa| * |t|` permitted, which keeps `a = 1 + kappa*t` inside
  /// `[0.2, 1.8]`.
  ///
  /// `a` reaching zero means a row passing exactly through the cone's apex,
  /// where the geometry is genuinely singular. Bounding it keeps the apex off
  /// the page entirely.
  static const double maxApexInfluence = 0.8;

  /// `sin^2(pi * t)`: peaks at 1 mid-turn, zero in both value and slope at each
  /// end. See the class doc on landing flat.
  static double bump(double t) {
    final s = math.sin(math.pi * t.clamp(0.0, 1.0));
    return s * s;
  }

  /// Smoothstep: zero slope at both ends, so the sheet eases into and out of
  /// rest rather than starting and stopping abruptly.
  static double smoothstep(double t) {
    final x = t.clamp(0.0, 1.0);
    return x * x * (3.0 - 2.0 * x);
  }

  /// Rotation of the sheet about the spine, from flat (`0`) to fully turned
  /// (`pi`).
  ///
  /// Uniform across the sheet, and therefore rigid — see the class doc on why
  /// the diagonal fold must not come from shearing this per row.
  static double _phi(double progress) => math.pi * smoothstep(progress);

  /// Deforms [mesh] in place for [params], writing `mesh.worldPositions`.
  ///
  /// [spineAtCentre] selects where the sheet hinges: `true` for a landscape
  /// spread, where the turning leaf is half the visible width and hinges at the
  /// middle; `false` for a single portrait page hinging at its own edge.
  void deform(
    PageCurlMesh mesh,
    CurlParameters params, {
    bool spineAtCentre = false,
  }) {
    final w = mesh.pageSize.width;
    final h = mesh.pageSize.height;
    final cols = mesh.columns;
    final rows = mesh.rows;

    final t = params.progress.clamp(0.0, 1.0);

    // Flat rest: take the exact rectangle rather than letting the general path
    // approximate it. The first frame of a drag must line up pixel-for-pixel
    // with the page that was on screen a frame earlier.
    if (t <= 0.0) {
      mesh.resetToFlat();
      return;
    }

    final dir = params.direction >= 0 ? 1.0 : -1.0;
    final b = bump(t);
    final wrapAngle = params.bendAmount * b;

    final double leafW;
    final double spineX;
    if (spineAtCentre) {
      leafW = w * 0.5;
      spineX = w * 0.5;
    } else {
      leafW = w;
      // A forward turn hinges on the left edge and lifts the right; a backward
      // turn mirrors it.
      spineX = dir > 0 ? 0.0 : w;
    }

    if (wrapAngle < flatEpsilon) {
      mesh.resetToFlat();
      return;
    }

    // Fold radius at the reference row (the page's vertical centre).
    final r0 = leafW / wrapAngle;

    // Cone strength as the half-angle sine, which is the parameterisation that
    // stays bounded: `kappa = coneSin / r0` then shrinks to zero automatically
    // as the sheet flattens and `r0` grows, so a nearly-flat page is never
    // conical.
    final coneSin = _resolveConeSin(params.conicity, r0: r0, pageHeight: h);
    final kappa = coneSin / r0;
    final cosTheta = math.sqrt(math.max(0.0, 1.0 - coneSin * coneSin));

    final phi = _phi(t);
    final cosPhi = math.cos(phi);
    final sinPhi = math.sin(phi);

    final sagAmp = params.droop * b * h;
    final grabV = params.grabV.isFinite ? params.grabV.clamp(0.0, 1.0) : 0.5;

    _deformRows(
      mesh: mesh,
      cols: cols,
      rows: rows,
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

  /// Clamps the requested cone strength into the range the formula is valid
  /// over.
  ///
  /// Two independent limits apply, and the tighter one wins:
  ///
  ///  * [maxConeSin], so `cos(theta)` stays real;
  ///  * [maxApexInfluence], so no row passes through the apex. Since
  ///    `kappa = coneSin / r0` and the farthest row is `pageHeight / 2` from
  ///    the reference row, that bounds `coneSin` by
  ///    `2 * maxApexInfluence * r0 / pageHeight`.
  static double _resolveConeSin(
    double conicity, {
    required double r0,
    required double pageHeight,
  }) {
    if (!conicity.isFinite || conicity == 0.0) return 0.0;
    final apexLimit =
        pageHeight <= 0 ? maxConeSin : 2.0 * maxApexInfluence * r0 / pageHeight;
    final limit = math.min(maxConeSin, apexLimit);
    return (conicity.clamp(-1.0, 1.0) * maxConeSin).clamp(-limit, limit);
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
      // centre. This is the `t` of the cone formula.
      final axial = (v - 0.5) * h;
      final a = 1.0 + kappa * axial;
      final sagRow = sagAmp * (v - grabV).abs();

      for (var col = 0; col <= cols; col++) {
        final u = cols == 0 ? 0.0 : col / cols;
        // Distance from the spine across the sheet. This is the `s` of the
        // cone formula, and equals the flat arc length by construction.
        final cross = u * leafW;

        final bb = kappa * cross;
        final rho = math.sqrt(a * a + bb * bb);

        // atan2(bb, a) / bb, with its removable singularity at bb == 0 handled
        // by the two-term Taylor expansion.
        final g = bb.abs() > taylorEpsilon
            ? math.atan2(bb, a) / bb
            : 1.0 / a - bb * bb / (3.0 * a * a * a);

        final beta = cross * g / r0;
        final cosBeta = math.cos(beta);
        final sinBeta = math.sin(beta);

        // (rho - 1) / kappa, written so nothing divides by kappa.
        final hAxial = (2.0 * axial + kappa * (axial * axial + cross * cross)) /
            (rho + 1.0);

        // Local frame: axial along the spine, cross toward the free edge,
        // lift out of the page.
        final localAxial = hAxial - rho * r0 * r0 * kappa * (1.0 - cosBeta);
        final localCross = rho * r0 * sinBeta;
        final localLift = rho * r0 * (1.0 - cosBeta) * cosTheta;

        // Rigid rotation about the spine. Uniform across the sheet, so the
        // isometry established above survives it.
        final xr = localCross * cosPhi - localLift * sinPhi;
        final zr = localCross * sinPhi + localLift * cosPhi;

        final i = row * (cols + 1) + col;
        world[i * 3] = spineX + dir * xr;
        // Droop is proportional to u, so it is zero at the spine and cannot
        // detach the binding, and gated by `bump`, so it cannot pop at rest.
        world[i * 3 + 1] = halfH + localAxial + sagRow * u;
        world[i * 3 + 2] = zr;
      }
    }
  }

  /// Computes per-vertex normals from the deformed surface by central
  /// differences across the grid.
  ///
  /// Central differences rather than accumulated face normals: the grid is
  /// regular, so tangents are available directly, and this costs one cross
  /// product per *vertex* instead of one per triangle plus a scatter-add. The
  /// results agree for a smooth surface, which this always is.
  ///
  /// Degenerate cases fall back to the page normal rather than producing NaN.
  void computeNormals(PageCurlMesh mesh) {
    final cols = mesh.columns;
    final rows = mesh.rows;
    final world = mesh.worldPositions;
    final normals = mesh.normals;
    final stride = cols + 1;

    for (var row = 0; row <= rows; row++) {
      for (var col = 0; col <= cols; col++) {
        final i = row * stride + col;

        // Clamped neighbours, so an edge vertex uses a one-sided difference
        // instead of reading out of bounds.
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
          nz = 1.0;
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
  /// Returns a human-readable failure description, or `null` when the mesh is
  /// sound.
  static String? debugValidate(PageCurlMesh mesh, CurlParameters params) {
    final world = mesh.worldPositions;
    for (var i = 0; i < mesh.vertexCount; i++) {
      final x = world[i * 3];
      final y = world[i * 3 + 1];
      final z = world[i * 3 + 2];
      if (!x.isFinite || !y.isFinite || !z.isFinite) {
        return 'vertex $i is not finite: ($x, $y, $z) for $params';
      }
    }
    for (var i = 0; i < mesh.indices.length; i++) {
      if (mesh.indices[i] >= mesh.vertexCount) {
        return 'index $i out of range: ${mesh.indices[i]} >= ${mesh.vertexCount}';
      }
    }
    return null;
  }

  /// The wrap angle reached at the free edge of the row at normalised height
  /// [v], in radians.
  ///
  /// This is `beta` at `u == 1` — how far round the curl that row has
  /// travelled. It is the honest measure of "this row curls harder than that
  /// one", and the direct signature of the cone: a cylinder returns the same
  /// value for every row, while a cone's value varies monotonically down the
  /// page.
  ///
  /// Note this is *not* the same as peak lift. A tighter curl has a smaller
  /// radius, so it wraps further while rising less — which is exactly how a
  /// real corner fold behaves.
  static double debugWrapAngleAtRow(
    CurlParameters params,
    Size pageSize,
    double v, {
    bool spineAtCentre = false,
  }) {
    final t = params.progress.clamp(0.0, 1.0);
    final wrapAngle = params.bendAmount * bump(t);
    if (wrapAngle < flatEpsilon) return 0.0;

    final leafW = spineAtCentre ? pageSize.width * 0.5 : pageSize.width;
    final r0 = leafW / wrapAngle;
    final coneSin =
        _resolveConeSin(params.conicity, r0: r0, pageHeight: pageSize.height);
    final kappa = coneSin / r0;

    final axial = (v - 0.5) * pageSize.height;
    final a = 1.0 + kappa * axial;
    final cross = leafW;
    final bb = kappa * cross;
    final g = bb.abs() > taylorEpsilon
        ? math.atan2(bb, a) / bb
        : 1.0 / a - bb * bb / (3.0 * a * a * a);
    return cross * g / r0;
  }

  /// The largest relative error by which the deformation fails to preserve
  /// distance between adjacent mesh vertices.
  ///
  /// This is the measurement that decides whether the page is paper or rubber.
  ///
  /// ## Reading the number
  ///
  /// The *continuous* surface is an exact isometry, but this measures a
  /// polygonal approximation of it: a chord across a curved strip is always
  /// shorter than the arc it subtends. That discretization error is
  /// `O(spacing^2)` and unavoidable — it quarters every time the mesh density
  /// doubles, which the geometry tests assert directly.
  ///
  /// So a small residual at production density is expected and correct; what
  /// matters is that it **converges quadratically**. A genuinely
  /// non-developable surface stretches by a fixed percentage that does not
  /// shrink with density at all.
  ///
  /// Compares each grid edge's 3D length against its flat length. Note this
  /// must be called on a mesh deformed with `droop: 0` to be meaningful —
  /// droop is a deliberate, non-isometric weight effect.
  ///
  /// [spineAtCentre] must match the value passed to [deform], since it halves
  /// the leaf width and therefore the expected spacing between columns.
  static double debugMaxIsometryError(
    PageCurlMesh mesh, {
    bool spineAtCentre = false,
  }) {
    final world = mesh.worldPositions;
    final cols = mesh.columns;
    final rows = mesh.rows;
    final stride = cols + 1;
    final leafW =
        spineAtCentre ? mesh.pageSize.width * 0.5 : mesh.pageSize.width;
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
          final err = (lengthBetween(i, i + 1) - flatDx).abs() / flatDx;
          if (err > worst) worst = err;
        }
        if (row < rows) {
          final err = (lengthBetween(i, i + stride) - flatDy).abs() / flatDy;
          if (err > worst) worst = err;
        }
      }
    }
    return worst;
  }
}
