import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'package:flip_book/src/rendering/curl_parameters.dart';
import 'package:flip_book/src/rendering/page_curl_camera.dart';
import 'package:flip_book/src/rendering/page_curl_geometry.dart';
import 'package:flip_book/src/rendering/page_curl_mesh.dart';
import 'package:flip_book/src/rendering/sheet_atlas.dart';

/// Draws the curled sheet as a texture-mapped triangle mesh.
///
/// One `drawVertices` call per frame, one `ImageShader`, one mesh. The
/// expensive parts — topology, texture coordinates, the shader — are built once
/// and reused; only the vertex positions and lighting change per frame.
///
/// ## Resource lifetimes
///
/// Three kinds of native-backed object are involved and each has a different
/// rule:
///
///   * **`ui.Image`** — owned by whoever supplied the [SheetAtlas]. The
///     renderer never disposes it.
///   * **`ImageShader`** — owned here, cached, and rebuilt only when the source
///     image changes. Creating one per frame would be a per-frame texture
///     binding for no reason.
///   * **`ui.Vertices`** — owned here, and unavoidably rebuilt every frame.
///     `Vertices` is immutable and holds a native copy of the buffers; the
///     class exposes no setter, so there is genuinely no way to update one in
///     place. What *can* be reused are the typed buffers feeding it, and those
///     are allocated once by [PageCurlMesh]. The previous frame's `Vertices` is
///     disposed as soon as the new one replaces it, rather than left to the
///     garbage collector, because it holds memory the Dart heap does not
///     account for.
///
/// ## Why the triangles are indexed
///
/// Adjacent triangles share vertex *records* via the index buffer rather than
/// each carrying its own copy of the shared corners. That makes the mesh
/// watertight: the rasteriser's fill rules guarantee no gap and no double-hit
/// along an interior edge. Duplicating shared vertices instead — or worse,
/// issuing one draw call per triangle — produces hairline seams across the
/// whole page wherever the floating-point coordinates disagree in the last bit.
@internal
class PageCurlRenderer {
  PageCurlRenderer({
    PageCurlGeometry geometry = const PageCurlGeometry(),
  }) : _geometry = geometry;

  final PageCurlGeometry _geometry;

  ui.Vertices? _vertices;
  ui.ImageShader? _shader;
  ui.Image? _shaderImage;
  final Paint _paint = Paint()
    ..isAntiAlias = true
    ..filterQuality = FilterQuality.medium;

  /// Reusable index buffer holding triangles in draw order.
  Uint16List? _orderedIndices;

  /// Draws [mesh] deformed by [params], sampling [atlas].
  ///
  /// [origin] offsets the sheet within the canvas, for a spread's right half.
  /// Returns `false` when the frame was skipped because the geometry was
  /// unusable, letting the caller fall back to drawing the page flat.
  bool paint(
    Canvas canvas,
    PageCurlMesh mesh,
    CurlParameters params,
    SheetAtlas atlas, {
    required PageCurlCamera camera,
    Offset origin = Offset.zero,
    bool spineAtCentre = false,
    PageCurlLighting lighting = const PageCurlLighting(),
  }) {
    _geometry.deform(mesh, params, spineAtCentre: spineAtCentre);
    _geometry.computeNormals(mesh);

    final bad = camera.projectBuffer(
      mesh.worldPositions,
      mesh.positions,
      mesh.vertexCount,
      origin: origin,
    );
    // A few clamped vertices is a steep but legal curl. Most of the mesh means
    // the parameters are wrong, and drawing it would produce a spray of
    // stretched triangles across the canvas -- far worse than one dropped
    // frame.
    if (bad > mesh.vertexCount * 0.3) return false;

    _updateTextureCoordinates(mesh, atlas, params);
    lighting.apply(mesh, params);

    final indices = _orderTriangles(mesh);
    final shader = _shaderFor(atlas.image);

    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      mesh.positions,
      textureCoordinates: mesh.textureCoordinates,
      colors: mesh.colors,
      indices: indices,
    );

    _paint.shader = shader;
    // Paint (the texture) is the source, vertex colours the destination, so
    // `modulate` multiplies the page by its lighting. It is also the last
    // blend mode on the fast pipeline -- anything "advanced" drops to a slower
    // path for no visual gain here.
    canvas.drawVertices(vertices, BlendMode.modulate, _paint);

    // Replace and release in that order: the old handle stays valid until the
    // draw above has been recorded.
    _vertices?.dispose();
    _vertices = vertices;
    return true;
  }

  /// Points each vertex at the correct half of the atlas.
  ///
  /// Face selection is per *triangle*, but texture coordinates are per
  /// *vertex*, and a vertex on the fold belongs to triangles of both facings.
  /// Rather than split the mesh — which would break the shared-vertex
  /// watertightness described in the class doc — the whole sheet samples one
  /// face at a time, chosen by how far through the turn it is.
  ///
  /// That is correct because the sheet is a single smooth surface: the fold
  /// where facing flips sweeps across it, and past the halfway point the
  /// viewer is looking at the back of the sheet.
  void _updateTextureCoordinates(
    PageCurlMesh mesh,
    SheetAtlas atlas,
    CurlParameters params,
  ) {
    final showBack = !atlas.isSingleFace && params.progress > 0.5;
    final region = showBack ? atlas.backRegion : atlas.frontRegion;

    // Inset by half a texel. Bilinear sampling reads across the cell boundary
    // at the very edge, which would pull in the gutter -- or, for a
    // single-image sheet, whatever `TileMode.clamp` repeats there.
    final inset = region.deflate(0.5);

    mesh.updateTextureRegion(
      inset,
      // The back of a sheet is its front seen through the paper, so it reads
      // mirrored left-to-right. Only `u` flips: the sheet rotates about a
      // vertical axis, so `v` is untouched. Getting this wrong shows up as
      // upside-down text, which is why it is asserted in the tests.
      mirrorHorizontally: showBack,
    );
  }

  /// Orders triangles back-to-front and returns the index buffer to draw.
  ///
  /// `drawVertices` has no depth buffer, so when the sheet folds over itself
  /// the submission order *is* the depth test. Two things make this cheap:
  ///
  ///   * **A flat sheet needs no ordering at all.** At rest and at the two ends
  ///     of a turn every triangle is coplanar, so the sort is skipped outright
  ///     — which is most frames in a reader.
  ///   * **The order barely changes between frames.** The curl moves smoothly,
  ///     so the previous frame's order is nearly correct and an insertion sort
  ///     over the retained permutation runs in close to linear time. A fresh
  ///     comparison sort every frame would be `O(n log n)` for no benefit.
  Uint16List _orderTriangles(PageCurlMesh mesh) {
    final depth = mesh.triangleDepth;
    final indices = mesh.indices;
    final world = mesh.worldPositions;
    final count = mesh.triangleCount;

    var lo = double.infinity;
    var hi = double.negativeInfinity;
    for (var t = 0; t < count; t++) {
      final a = indices[t * 3];
      final b = indices[t * 3 + 1];
      final c = indices[t * 3 + 2];
      final z = (world[a * 3 + 2] + world[b * 3 + 2] + world[c * 3 + 2]) / 3.0;
      depth[t] = z;
      if (z < lo) lo = z;
      if (z > hi) hi = z;
    }

    // Coplanar: nothing can occlude anything, so the original order is correct
    // and cheapest.
    if (hi - lo < 1e-3) return indices;

    final order = mesh.depthOrder;
    // Insertion sort over the retained permutation, back (smallest z) first.
    for (var i = 1; i < count; i++) {
      final key = order[i];
      final keyDepth = depth[key];
      var j = i - 1;
      while (j >= 0 && depth[order[j]] > keyDepth) {
        order[j + 1] = order[j];
        j--;
      }
      order[j + 1] = key;
    }

    final ordered = _orderedIndices ??= Uint16List(count * 3);
    for (var i = 0; i < count; i++) {
      final t = order[i];
      ordered[i * 3] = indices[t * 3];
      ordered[i * 3 + 1] = indices[t * 3 + 1];
      ordered[i * 3 + 2] = indices[t * 3 + 2];
    }
    return ordered;
  }

  /// Returns a shader for [image], reusing the cached one while the image is
  /// unchanged.
  ui.ImageShader _shaderFor(ui.Image image) {
    final cached = _shader;
    if (cached != null && identical(_shaderImage, image)) return cached;

    cached?.dispose();
    final shader = ui.ImageShader(
      image,
      TileMode.clamp,
      TileMode.clamp,
      Matrix4.identity().storage,
      filterQuality: FilterQuality.medium,
    );
    _shader = shader;
    _shaderImage = image;
    return shader;
  }

  /// Releases the shader and the last frame's vertices.
  ///
  /// Does not touch the atlas image, which the renderer does not own.
  void dispose() {
    _vertices?.dispose();
    _vertices = null;
    _shader?.dispose();
    _shader = null;
    _shaderImage = null;
    _paint.shader = null;
  }
}

/// Turns the deformed surface's normals into per-vertex brightness.
///
/// Lighting here exists to *reinforce* the geometry, never to stand in for it.
/// The page is dark where its surface turns away from the light, not because
/// progress happens to be 0.5 — which is what the previous renderer did, and
/// why its fold read as a painted gradient rather than a shape.
///
/// The consequence that matters most: a flat page evaluates to exactly 1.0
/// everywhere, so at rest and at the end of a turn the sheet is pixel-identical
/// to the static page underneath it. There is no brightness step at hand-off.
@immutable
@internal
class PageCurlLighting {
  const PageCurlLighting({
    this.ambient = 0.30,
    this.foldDarkening = 0.22,
  });

  /// Brightness of a surface turned fully away from the light.
  ///
  /// Never zero: a page that goes black at grazing angles looks like a hole,
  /// not like paper.
  final double ambient;

  /// Extra darkening applied in proportion to curvature, which deepens the
  /// inside of the fold.
  final double foldDarkening;

  /// Writes per-vertex ARGB into `mesh.colors`.
  void apply(PageCurlMesh mesh, CurlParameters params) {
    final colors = mesh.colors;
    final normals = mesh.normals;

    if (params.isFlat) {
      // Exactly unlit: `modulate` by white is the identity, so a resting sheet
      // matches the live page it replaces.
      mesh.resetColors();
      return;
    }

    for (var i = 0; i < mesh.vertexCount; i++) {
      final nz = normals[i * 3 + 2];

      // Two-sided: the back of a sheet catches light just as its front does,
      // so only the angle matters, not which way the normal happens to point.
      final facing = nz.abs().clamp(0.0, 1.0);
      final curl = 1.0 - facing;

      var lum = ambient + (1.0 - ambient) * facing;
      lum -= foldDarkening * curl * curl;
      final level = (lum.clamp(0.0, 1.0) * 255).round();

      // Alpha must stay fully opaque: `modulate` multiplies alpha too, so
      // anything less makes the sheet translucent and the page beneath shows
      // through it.
      colors[i] = 0xFF000000 | (level << 16) | (level << 8) | level;
    }
  }

  /// Peak lift of the sheet, used to scale the cast shadow.
  static double peakLift(PageCurlMesh mesh) {
    var peak = 0.0;
    for (var i = 0; i < mesh.vertexCount; i++) {
      final z = mesh.worldPositions[i * 3 + 2];
      if (z > peak) peak = z;
    }
    return peak;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PageCurlLighting &&
          other.ambient == ambient &&
          other.foldDarkening == foldDarkening;

  @override
  int get hashCode => Object.hash(ambient, foldDarkening);
}

/// Draws the shadow the lifted sheet casts on the page beneath it.
///
/// Kept separate from [PageCurlRenderer] so it can be benchmarked and disabled
/// on its own — the implementation plan calls for measuring shadow cost rather
/// than assuming it.
///
/// The shadow's outline is built from the *same* deformed mesh as the page, so
/// its edge follows the curve of the fold. A straight shadow band under a
/// curved sheet is one of the most obvious tells that a page-curl is painted
/// rather than modelled.
@internal
class PageCurlShadow {
  const PageCurlShadow({
    this.opacity = 0.32,
    this.blurSigma = 12.0,
  });

  final double opacity;
  final double blurSigma;

  /// Paints the cast shadow for the current mesh state.
  ///
  /// Call before the page itself, so the sheet draws over its own shadow.
  void paint(
    Canvas canvas,
    PageCurlMesh mesh,
    CurlParameters params, {
    required PageCurlCamera camera,
    Offset origin = Offset.zero,
  }) {
    if (params.isFlat) return;

    final lift = PageCurlLighting.peakLift(mesh);
    if (lift <= 0.5) return;

    // Fade in with height, with zero slope at contact so the shadow dissolves
    // as the sheet lands instead of snapping off.
    final envelope = PageCurlGeometry.smoothstep(
      (lift / (mesh.pageSize.width * 0.18)).clamp(0.0, 1.0),
    );
    if (envelope <= 0.01) return;

    final path = _freeEdgePath(mesh, camera, origin);
    if (path == null) return;

    final paint = Paint()
      ..color = Color.fromRGBO(0, 0, 0, opacity * envelope)
      ..maskFilter = ui.MaskFilter.blur(
        ui.BlurStyle.normal,
        blurSigma * envelope,
      );
    canvas.drawPath(path, paint);
  }

  /// Builds a polygon from the sheet's free edge back to the spine.
  ///
  /// Traces real projected mesh vertices rather than approximating with a
  /// rectangle, which is what keeps the shadow's boundary on the same curve as
  /// the page.
  Path? _freeEdgePath(
    PageCurlMesh mesh,
    PageCurlCamera camera,
    Offset origin,
  ) {
    final cols = mesh.columns;
    final rows = mesh.rows;
    final positions = mesh.positions;
    if (rows < 1) return null;

    final path = Path();
    // Down the free edge, following the curl.
    for (var row = 0; row <= rows; row++) {
      final i = mesh.vertexIndex(cols, row);
      final x = positions[i * 2];
      final y = positions[i * 2 + 1];
      if (!x.isFinite || !y.isFinite) return null;
      if (row == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    // Back along the spine, which is straight.
    for (var row = rows; row >= 0; row--) {
      final i = mesh.vertexIndex(0, row);
      path.lineTo(positions[i * 2], positions[i * 2 + 1]);
    }
    path.close();
    return path;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PageCurlShadow &&
          other.opacity == opacity &&
          other.blurSigma == blurSigma;

  @override
  int get hashCode => Object.hash(opacity, blurSigma);
}

/// Convenience for the peak absolute lift, used by tests and the harness.
@internal
double debugPeakLift(PageCurlMesh mesh) {
  var peak = 0.0;
  for (var i = 0; i < mesh.vertexCount; i++) {
    peak = math.max(peak, mesh.worldPositions[i * 3 + 2].abs());
  }
  return peak;
}
