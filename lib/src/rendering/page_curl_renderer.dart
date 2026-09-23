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
/// The renderer is deliberately kept in Flutter's canvas/vertices pipeline:
/// one draw call, one image shader, one mesh. Topology and index buffers are
/// reused; the per-frame work is deformation, projection, lighting, ordering,
/// and the immutable [ui.Vertices] object required by Flutter.
///
/// ## Resource lifetimes
///
/// * The [SheetAtlas] owns its atlas image. This renderer never disposes it.
/// * The [ui.ImageShader] is owned and cached here. It is rebuilt only when
///   the atlas image changes.
/// * [ui.Vertices] is owned here and replaced every frame. Flutter exposes an
///   immutable vertices object, so the reusable typed buffers in [PageCurlMesh]
///   are the part we can keep allocation-free.
///
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

  int _orderedTriangleCount = 0;

  /// Draws [mesh] deformed by [params], sampling [atlas].
  ///
  /// [origin] offsets the sheet within the canvas, for a spread's right half.
  /// Returns `false` when the frame is unsafe to draw and the caller should
  /// keep the live page visible instead of displaying a malformed mesh.
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
    if (_invalidAtlas(atlas) || mesh.vertexCount == 0) {
      return false;
    }

    _geometry.deform(
      mesh,
      params,
      spineAtCentre: spineAtCentre,
    );
    _geometry.computeNormals(mesh);

    final bad = camera.projectBuffer(
      mesh.worldPositions,
      mesh.positions,
      mesh.vertexCount,
      origin: origin,
    );

    // A few vertices can legitimately clamp at an extreme perspective angle.
    // If a large fraction becomes invalid, drawing the result produces huge
    // stretched triangles and is visually worse than dropping that frame.
    if (bad > mesh.vertexCount * 0.30) {
      return false;
    }

    if (!_updateTextureCoordinates(mesh, atlas, params)) {
      return false;
    }

    lighting.apply(mesh, params);

    final indices = _orderTriangles(mesh, params);
    final shader = _shaderFor(atlas);
    if (shader == null) return false;

    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      mesh.positions,
      textureCoordinates: mesh.textureCoordinates,
      colors: mesh.colors,
      indices: indices,
    );

    _paint.shader = shader;

    // drawVertices records the draw into the canvas. The native vertices
    // handle can therefore be replaced immediately afterwards; keeping the
    // previous frame alive is unnecessary native memory.
    canvas.drawVertices(
      vertices,
      BlendMode.modulate,
      _paint,
    );

    _vertices?.dispose();
    _vertices = vertices;
    return true;
  }

  /// Points every vertex at the appropriate sheet-face region.
  ///
  /// The current paper model intentionally treats the turning sheet as a
  /// single front-facing digital page whose reverse is blank paper. The
  /// halfway transition therefore switches the UV region once the sheet has
  /// passed the midpoint.
  ///
  /// Keeping the UV mapping continuous and centralized here is important:
  /// [SheetAtlas] controls pixel ownership, while this class controls how the
  /// mesh samples those pixels.
  bool _updateTextureCoordinates(
    PageCurlMesh mesh,
    SheetAtlas atlas,
    CurlParameters params,
  ) {
    if (atlas.isDisposed) return false;

    final showBack = !atlas.isSingleFace && params.progress > 0.5;
    final region = showBack ? atlas.backRegion : atlas.frontRegion;

    if (!_isValidRegion(atlas.image, region)) return false;

    // Inset by half a texel. Bilinear sampling at the cell edge can otherwise
    // pull neighbouring pixels across the two-face atlas gutter.
    final inset = region.deflate(0.5);
    if (inset.width <= 0 || inset.height <= 0) return false;

    mesh.updateTextureRegion(
      inset,
      // A back page is viewed from the reverse side of the sheet, so its
      // horizontal reading direction is mirrored. V remains unchanged.
      mirrorHorizontally: showBack,
    );

    return true;
  }

  /// Orders triangles back-to-front because Canvas has no depth buffer.
  ///
  /// Curl motion is continuous, so the previous permutation is an excellent
  /// starting point for insertion sort. On a flat sheet all depths are equal,
  /// so the original topology order is already sufficient and the full depth
  /// pass can be skipped.
  Uint16List _orderTriangles(
    PageCurlMesh mesh,
    CurlParameters params,
  ) {
    final depth = mesh.triangleDepth;
    final indices = mesh.indices;
    final world = mesh.worldPositions;
    final count = mesh.triangleCount;

    if (count == 0) return Uint16List(0);

    if (params.isFlat) {
      return indices;
    }

    var lo = double.infinity;
    var hi = double.negativeInfinity;

    for (var t = 0; t < count; t++) {
      final a = indices[t * 3];
      final b = indices[t * 3 + 1];
      final c = indices[t * 3 + 2];

      final z = (world[a * 3 + 2] + world[b * 3 + 2] + world[c * 3 + 2]) / 3.0;

      if (!z.isFinite) {
        // Returning the original topology is safer than constructing a
        // permutation from NaN/Infinity values.
        return indices;
      }

      depth[t] = z;
      if (z < lo) lo = z;
      if (z > hi) hi = z;
    }

    // Coplanar or numerically-flat: no triangle can meaningfully occlude
    // another, so preserve the mesh's native order.
    if (!lo.isFinite || !hi.isFinite || hi - lo < 1e-3) {
      return indices;
    }

    final order = mesh.depthOrder;

    // The array is maintained as a permutation across frames.
    // If its size ever changes because a different mesh topology is used with
    // this renderer instance, rebuild it before sorting.
    if (order.length != count) {
      return indices;
    }

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

    if (_orderedIndices == null || _orderedTriangleCount != count) {
      _orderedIndices = Uint16List(count * 3);
      _orderedTriangleCount = count;
    }

    final ordered = _orderedIndices!;
    for (var i = 0; i < count; i++) {
      final triangle = order[i];
      ordered[i * 3] = indices[triangle * 3];
      ordered[i * 3 + 1] = indices[triangle * 3 + 1];
      ordered[i * 3 + 2] = indices[triangle * 3 + 2];
    }

    return ordered;
  }

  /// Returns a cached shader for [atlas]'s image.
  ui.ImageShader? _shaderFor(SheetAtlas atlas) {
    if (atlas.isDisposed) return null;
    final image = atlas.image;

    final cached = _shader;
    if (cached != null && identical(_shaderImage, image)) {
      return cached;
    }

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

  bool _invalidAtlas(SheetAtlas atlas) {
    if (atlas.isDisposed) return true;

    final size = atlas.logicalSize;
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) {
      return true;
    }

    if (!_isValidRegion(atlas.image, atlas.frontRegion)) return true;
    if (!_isValidRegion(atlas.image, atlas.backRegion)) return true;

    return false;
  }

  static bool _isValidRegion(ui.Image image, Rect region) {
    return region.left.isFinite &&
        region.top.isFinite &&
        region.right.isFinite &&
        region.bottom.isFinite &&
        region.width > 0 &&
        region.height > 0 &&
        region.left >= 0 &&
        region.top >= 0 &&
        region.right <= image.width &&
        region.bottom <= image.height;
  }

  /// Releases the shader and last-frame vertices.
  ///
  /// The atlas image is not touched because [PageCurlRenderer] never owns it.
  void dispose() {
    _vertices?.dispose();
    _vertices = null;

    _shader?.dispose();
    _shader = null;
    _shaderImage = null;

    _orderedIndices = null;
    _orderedTriangleCount = 0;
    _paint.shader = null;
  }
}

/// Turns the deformed surface's normals into per-vertex brightness.
///
/// Lighting reinforces the geometry rather than replacing it. A flat page is
/// exactly white under [BlendMode.modulate], so the live page and the resting
/// mesh can hand off without a brightness step.
@immutable
@internal
class PageCurlLighting {
  const PageCurlLighting({
    this.ambient = 0.30,
    this.foldDarkening = 0.22,
  })  : assert(ambient >= 0 && ambient <= 1),
        assert(foldDarkening >= 0);

  /// Minimum brightness at grazing angles.
  final double ambient;

  /// Additional darkening inside the fold.
  final double foldDarkening;

  /// Writes per-vertex ARGB into [mesh.colors].
  void apply(PageCurlMesh mesh, CurlParameters params) {
    final colors = mesh.colors;

    if (params.isFlat) {
      mesh.resetColors();
      return;
    }

    final normals = mesh.normals;

    for (var i = 0; i < mesh.vertexCount; i++) {
      final nz = normals[i * 3 + 2];

      // Two-sided paper: front and back both receive light according to their
      // absolute facing angle.
      final facing = nz.abs().clamp(0.0, 1.0);
      final curl = 1.0 - facing;

      var luminance = ambient + (1.0 - ambient) * facing;
      luminance -= foldDarkening * curl * curl;

      final level = (luminance.clamp(0.0, 1.0) * 255).round();

      // Keep alpha opaque. Modulating alpha would make the live page beneath
      // leak through and read as transparency rather than paper shading.
      colors[i] = 0xFF000000 | (level << 16) | (level << 8) | level;
    }
  }

  /// Peak positive lift of the sheet.
  static double peakLift(PageCurlMesh mesh) {
    var peak = 0.0;

    for (var i = 0; i < mesh.vertexCount; i++) {
      final z = mesh.worldPositions[i * 3 + 2];
      if (z.isFinite && z > peak) {
        peak = z;
      }
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
/// The outline comes from the same deformed mesh as the page rather than from
/// a straight approximation. Shadow work stays isolated so it can later be
/// benchmarked or disabled without changing the curl renderer.
@internal
class PageCurlShadow {
  const PageCurlShadow({
    this.opacity = 0.32,
    this.blurSigma = 12.0,
  })  : assert(opacity >= 0 && opacity <= 1),
        assert(blurSigma >= 0);

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
    if (params.isFlat || opacity <= 0) return;

    final lift = PageCurlLighting.peakLift(mesh);
    if (lift <= 0.5) return;

    final envelope = PageCurlGeometry.smoothstep(
      (lift / (mesh.pageSize.width * 0.18)).clamp(0.0, 1.0),
    );

    if (envelope <= 0.01) return;

    final path = _freeEdgePath(mesh);
    if (path == null) return;

    final paint = Paint()
      ..color = Color.fromRGBO(0, 0, 0, opacity * envelope)
      ..maskFilter = blurSigma <= 0
          ? null
          : ui.MaskFilter.blur(
              ui.BlurStyle.normal,
              blurSigma * envelope,
            );

    canvas.drawPath(path, paint);
  }

  /// Builds a polygon from the sheet's free edge back to the spine.
  ///
  /// The mesh positions are already projected by the caller before this
  /// function runs. [camera] and [origin] remain in the signature so the
  /// shadow API stays compatible with spread-aware renderers.
  Path? _freeEdgePath(PageCurlMesh mesh) {
    final cols = mesh.columns;
    final rows = mesh.rows;
    final positions = mesh.positions;

    if (rows < 1 || cols < 1) return null;

    final path = Path();

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

    for (var row = rows; row >= 0; row--) {
      final i = mesh.vertexIndex(0, row);
      final x = positions[i * 2];
      final y = positions[i * 2 + 1];

      if (!x.isFinite || !y.isFinite) return null;
      path.lineTo(x, y);
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
    final z = mesh.worldPositions[i * 3 + 2];
    if (z.isFinite) {
      peak = math.max(peak, z.abs());
    }
  }

  return peak;
}
