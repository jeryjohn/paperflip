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

  // Two-sided buffers for corner folds: every vertex twice, once sampling the
  // front face and once the back, so each triangle can pick its own face.
  Float32List? _faceTex;
  Float32List? _facePositions;
  Int32List? _faceColors;
  Uint16List? _faceIndices;

  /// Computes deformation, normals, and perspective projection in one pass.
  ///
  /// Returns `false` when more than 30% of vertices clamp at an extreme perspective angle.
  bool deformAndProject(
    PageCurlMesh mesh,
    CurlParameters params, {
    required PageCurlCamera camera,
    Offset origin = Offset.zero,
    bool spineAtCentre = false,
  }) {
    if (mesh.vertexCount == 0) return false;

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

    return bad <= mesh.vertexCount * 0.30;
  }

  /// Draws [mesh] deformed by [params], sampling [atlas].
  ///
  /// [origin] offsets the sheet within the canvas, for a spread's right half.
  /// Set [alreadyDeformed] to true if [deformAndProject] was already run on [mesh]
  /// for this frame (e.g. by shadow calculation).
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
    bool alreadyDeformed = false,
  }) {
    if (_invalidAtlas(atlas) || mesh.vertexCount == 0) {
      return false;
    }

    if (!alreadyDeformed) {
      final ok = deformAndProject(
        mesh,
        params,
        camera: camera,
        origin: origin,
        spineAtCentre: spineAtCentre,
      );
      if (!ok) return false;
    }

    final twoSided =
        params.isCornerFold &&
        !atlas.isSingleFace &&
        mesh.vertexCount * 2 <= 0x10000;

    final ui.Vertices vertices;
    if (twoSided) {
      final built = _buildTwoSided(mesh, atlas, params, lighting);
      if (built == null) return false;
      vertices = built;
    } else {
      if (!_updateTextureCoordinates(mesh, atlas, params)) {
        return false;
      }

      lighting.apply(mesh, params);

      final indices = _orderTriangles(mesh, params);
      vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        mesh.positions,
        textureCoordinates: mesh.textureCoordinates,
        colors: mesh.colors,
        indices: indices,
      );
    }

    final shader = _shaderFor(atlas);
    if (shader == null) {
      vertices.dispose();
      return false;
    }

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
  /// Resolves whether the back face of the sheet should be shown.
  @visibleForTesting
  static bool resolveShowBack({
    required bool isSingleFace,
    required double progress,
    required int direction,
  }) {
    if (isSingleFace) return false;
    return progress > 0.5;
  }

  /// Resolves whether the UV coordinates along U should be inverted.
  ///
  /// In forward turns (direction >= 0), mesh coordinate `u` runs left-to-right (0 at spineX=0, 1 at free edge).
  /// In backward turns (direction < 0), mesh coordinate `u` runs right-to-left (0 at spineX=w, 1 at free edge=0).
  /// Inverting U during backward turns ensures text/content reads naturally left-to-right on screen
  /// without being horizontally mirrored or reversed.
  /// Content is never mirrored merely because the back face is being displayed.
  @visibleForTesting
  static bool resolveMirrorHorizontally({
    required int direction,
    required bool showBack,
  }) {
    return direction < 0;
  }

  /// Builds vertices where each triangle shows whichever face of the sheet is
  /// actually toward the viewer.
  ///
  /// The spine curl can switch the whole sheet to its back at the midpoint
  /// because the whole sheet rotates together. A corner peel cannot: the
  /// folded-over flap shows the back of the paper while the rest of the same
  /// sheet still shows the page. Facing is read from the projected winding,
  /// which is exact for what ends up on screen.
  ui.Vertices? _buildTwoSided(
    PageCurlMesh mesh,
    SheetAtlas atlas,
    CurlParameters params,
    PageCurlLighting lighting,
  ) {
    if (atlas.isDisposed) return null;
    final n = mesh.vertexCount;

    final front = atlas.frontRegion.deflate(0.5);
    final back = atlas.backRegion.deflate(0.5);
    if (front.width <= 0 || front.height <= 0) return null;
    if (back.width <= 0 || back.height <= 0) return null;

    final mirror = resolveMirrorHorizontally(
      direction: params.direction,
      showBack: false,
    );

    var tex = _faceTex;
    if (tex == null || tex.length != n * 4) {
      tex = _faceTex = Float32List(n * 4);
      _facePositions = Float32List(n * 4);
      _faceColors = Int32List(n * 2);
      _faceIndices = Uint16List(mesh.triangleCount * 3);
    }
    final pos = _facePositions!;
    final colors = _faceColors!;
    final out = _faceIndices!;

    mesh.updateTextureRegion(back, mirrorHorizontally: mirror);
    tex.setRange(n * 2, n * 4, mesh.textureCoordinates);
    mesh.updateTextureRegion(front, mirrorHorizontally: mirror);
    tex.setRange(0, n * 2, mesh.textureCoordinates);

    lighting.apply(mesh, params);
    pos.setRange(0, n * 2, mesh.positions);
    pos.setRange(n * 2, n * 4, mesh.positions);
    colors.setRange(0, n, mesh.colors);
    colors.setRange(n, n * 2, mesh.colors);

    final ordered = _orderTriangles(mesh, params);
    final p = mesh.positions;
    final uv = mesh.normalized;

    // Winding of the flat, unturned sheet. Forward and backward turns lay
    // the grid out mirrored, which flips it.
    final a0 = mesh.indices[0];
    final b0 = mesh.indices[1];
    final c0 = mesh.indices[2];
    final flatSign =
        _cross(
          uv[a0 * 2], uv[a0 * 2 + 1],
          uv[b0 * 2], uv[b0 * 2 + 1],
          uv[c0 * 2], uv[c0 * 2 + 1],
        ).sign *
        (params.direction >= 0 ? 1.0 : -1.0);

    for (var t = 0; t < mesh.triangleCount; t++) {
      final a = ordered[t * 3];
      final b = ordered[t * 3 + 1];
      final c = ordered[t * 3 + 2];
      final area = _cross(
        p[a * 2], p[a * 2 + 1],
        p[b * 2], p[b * 2 + 1],
        p[c * 2], p[c * 2 + 1],
      );
      final offset = area * flatSign < 0 ? n : 0;
      out[t * 3] = a + offset;
      out[t * 3 + 1] = b + offset;
      out[t * 3 + 2] = c + offset;
    }

    return ui.Vertices.raw(
      ui.VertexMode.triangles,
      pos,
      textureCoordinates: tex,
      colors: colors,
      indices: out,
    );
  }

  static double _cross(
    double ax, double ay,
    double bx, double by,
    double cx, double cy,
  ) => (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);

  /// Points every vertex at the appropriate sheet-face region.
  ///
  /// The current paper model treats the turning sheet as a front-facing
  /// digital page whose reverse is blank paper. The midpoint transition
  /// switches to the paper back face once the sheet has turned over.
  bool _updateTextureCoordinates(
    PageCurlMesh mesh,
    SheetAtlas atlas,
    CurlParameters params,
  ) {
    if (atlas.isDisposed) return false;

    final showBack = resolveShowBack(
      isSingleFace: atlas.isSingleFace,
      progress: params.progress,
      direction: params.direction,
    );
    final region = showBack ? atlas.backRegion : atlas.frontRegion;

    if (!_isValidRegion(atlas.image, region)) return false;

    // Inset by half a texel. Bilinear sampling at the cell edge can otherwise
    // pull neighbouring pixels across the two-face atlas gutter.
    final inset = region.deflate(0.5);
    if (inset.width <= 0 || inset.height <= 0) return false;

    final mirrorHorizontally = resolveMirrorHorizontally(
      direction: params.direction,
      showBack: showBack,
    );

    mesh.updateTextureRegion(
      inset,
      mirrorHorizontally: mirrorHorizontally,
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
    _faceTex = null;
    _facePositions = null;
    _faceColors = null;
    _faceIndices = null;
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

    if (params.isCornerFold) {
      _paintCornerShadow(canvas, mesh.pageSize, params, origin);
      return;
    }

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

  /// Soft shadow the roll casts onto the revealed page, along the crease.
  ///
  /// The roll's silhouette reaches `R` past the crease line; the shadow starts
  /// there and fades out over a short band. Everything on the other side is
  /// under the sheet and hidden anyway.
  void _paintCornerShadow(
    Canvas canvas,
    Size pageSize,
    CurlParameters params,
    Offset origin,
  ) {
    final f = CornerFoldFrame.resolve(params, pageSize);
    if (f == null) return;

    // Fade in with the size of the roll, so a barely-lifted corner and the
    // final flat landing carry no shadow.
    final envelope = PageCurlGeometry.smoothstep(
      f.radius / (CornerFoldFrame.maxRadiusFraction * f.leafWidth * 0.5),
    );
    if (envelope <= 0.01) return;

    // Crease normal and start point in screen space.
    final nx = f.dir * f.mx;
    final ny = f.my;
    final sx = f.spineX + f.dir * (f.axisX + f.mx * f.radius);
    final sy = f.axisY + f.my * f.radius;
    final width = f.leafWidth * 0.08 + f.radius * 0.6;

    final start = origin + Offset(sx, sy);
    final end = start + Offset(nx * width, ny * width);
    final alpha = opacity * envelope;

    // Half-plane on the revealed side of the start line, clipped to the page.
    final page = origin & pageSize;
    final big = pageSize.longestSide * 4;
    final tangent = Offset(-ny, nx);
    final normal = Offset(nx, ny);
    final band = Path()
      ..moveTo(start.dx + tangent.dx * big, start.dy + tangent.dy * big)
      ..lineTo(start.dx - tangent.dx * big, start.dy - tangent.dy * big)
      ..lineTo(
        start.dx - tangent.dx * big + normal.dx * big,
        start.dy - tangent.dy * big + normal.dy * big,
      )
      ..lineTo(
        start.dx + tangent.dx * big + normal.dx * big,
        start.dy + tangent.dy * big + normal.dy * big,
      )
      ..close();

    final paint = Paint()
      ..shader = ui.Gradient.linear(start, end, [
        Color.fromRGBO(0, 0, 0, alpha),
        const Color(0x00000000),
      ]);

    canvas
      ..save()
      ..clipRect(page)
      ..drawPath(band, paint)
      ..restore();
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
