import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// The static topology of the page mesh, plus the reusable buffers the curl
/// writes into each frame.
///
/// Everything that does not depend on the curl is computed once, in the
/// constructor:
///
///   * the grid of vertices in *normalised page space* (`u`, `v` in `0..1`),
///   * the triangle index buffer,
///   * the texture coordinates.
///
/// The per-frame buffers ([positions], [colors]) are allocated once and
/// overwritten in place, so a drag allocates no Dart objects per vertex or per
/// triangle. See the note on [Vertices] lifetime in
/// `page_curl_renderer.dart` — the `ui.Vertices` handle itself is native-backed
/// and cannot be mutated, so it is the one object that must be rebuilt.
///
/// ## Resolution
///
/// A page is not square, so a square mesh is wrong: it produces triangles
/// stretched along the page's long axis, and the fold is where that shows. The
/// row count is therefore derived from the aspect ratio ([forPage]) rather than
/// set independently.
@internal
class PageCurlMesh {
  /// Builds a mesh with an explicit grid size.
  ///
  /// [columns] and [rows] are *quad* counts, so the vertex grid is
  /// `(columns + 1) * (rows + 1)`.
  PageCurlMesh({
    required this.columns,
    required this.rows,
    required this.pageSize,
  })  : assert(columns >= 1, 'columns must be at least 1'),
        assert(rows >= 1, 'rows must be at least 1'),
        assert(
          pageSize.width > 0 && pageSize.height > 0,
          'pageSize must be non-empty',
        ),
        vertexCount = (columns + 1) * (rows + 1),
        triangleCount = columns * rows * 2 {
    _buildTopology();
  }

  /// Builds a mesh whose row count follows the page's aspect ratio, so
  /// triangles stay close to square.
  ///
  /// ```dart
  /// // A 3:4 portrait page at 32 columns gets ~43 rows.
  /// final mesh = PageCurlMesh.forPage(
  ///   pageSize: const Size(300, 400),
  ///   columns: 32,
  /// );
  /// ```
  ///
  /// [columns] is the tuning knob; the plan's benchmark matrix sweeps it over
  /// 24/32/42/48 before a default is chosen, so it is deliberately not fixed
  /// here.
  factory PageCurlMesh.forPage({
    required Size pageSize,
    int columns = defaultColumns,
    int maxRows = 96,
  }) {
    final aspect = pageSize.height / pageSize.width;
    final rows = (columns * aspect).round().clamp(1, maxRows);
    return PageCurlMesh(
      columns: columns,
      rows: rows,
      pageSize: pageSize,
    );
  }

  /// Starting point for the column sweep, not a researched optimum.
  ///
  /// The reference implementation defaults to 42 columns; the plan explicitly
  /// says not to copy that number without benchmarking, so this stays at a
  /// conservative 32 until the benchmark runs.
  static const int defaultColumns = 32;

  /// Quad columns across the page width.
  final int columns;

  /// Quad rows down the page height.
  final int rows;

  /// The page's logical size. Changing it requires a new mesh: the normalised
  /// grid is size-independent, but the texture coordinates are not.
  final Size pageSize;

  /// `(columns + 1) * (rows + 1)`.
  final int vertexCount;

  /// `columns * rows * 2`.
  final int triangleCount;

  // ── Static buffers, built once ────────────────────────────────────────────

  /// Normalised page coordinates, `[u0, v0, u1, v1, ...]`, each in `0..1`.
  ///
  /// `u` runs from the spine side to the free edge in *page* space; which
  /// physical edge that is depends on the flip direction and is resolved by
  /// the geometry, not here.
  late final Float32List normalized;

  /// Texture coordinates in the shader's coordinate space.
  ///
  /// Note the space: `Vertices.textureCoordinates` indexes the image sampled
  /// by `Paint.shader`, **not** a normalised `0..1` range. With an
  /// [ImageShader] built from an identity matrix that space is the image's
  /// pixel space, so these are filled in pixels and rescaled by
  /// [updateTextureRegion] when the page maps to a sub-rect of a larger image.
  late final Float32List textureCoordinates;

  /// Triangle indices, 3 per triangle, wound consistently counter-clockwise in
  /// the flat state.
  late final Uint16List indices;

  // ── Per-frame buffers, overwritten in place ───────────────────────────────

  /// Projected screen positions, `[x0, y0, x1, y1, ...]`.
  late final Float32List positions;

  /// Per-vertex lighting, ARGB, combined with the texture by
  /// `BlendMode.modulate`.
  late final Int32List colors;

  /// Deformed 3D positions before projection, `[x0, y0, z0, x1, y1, z1, ...]`.
  ///
  /// Kept separately from [positions] because normals are computed from the
  /// 3D surface, and a projected point has lost the depth that makes the
  /// cross-product meaningful.
  late final Float32List worldPositions;

  /// Accumulated per-vertex normals, `[nx0, ny0, nz0, ...]`.
  late final Float32List normals;

  /// Per-triangle view depth, used by the depth-ordering strategy.
  late final Float32List triangleDepth;

  /// Triangle draw order, as indices into [triangleDepth]. Rewritten in place
  /// when ordering is dynamic; left as the identity permutation when the curl
  /// guarantees a stable order.
  late final Uint16List depthOrder;

  /// Scratch index buffer holding [indices] permuted by [depthOrder], so a
  /// reordered draw does not allocate.
  late final Uint16List orderedIndices;

  void _buildTopology() {
    final vcols = columns + 1;
    final vrows = rows + 1;

    normalized = Float32List(vertexCount * 2);
    textureCoordinates = Float32List(vertexCount * 2);
    positions = Float32List(vertexCount * 2);
    worldPositions = Float32List(vertexCount * 3);
    normals = Float32List(vertexCount * 3);
    colors = Int32List(vertexCount);

    for (var row = 0; row < vrows; row++) {
      final v = row / rows;
      for (var col = 0; col < vcols; col++) {
        final u = col / columns;
        final i = row * vcols + col;
        normalized[i * 2] = u;
        normalized[i * 2 + 1] = v;
      }
    }

    indices = Uint16List(triangleCount * 3);
    var t = 0;
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < columns; col++) {
        final topLeft = row * vcols + col;
        final topRight = topLeft + 1;
        final bottomLeft = topLeft + vcols;
        final bottomRight = bottomLeft + 1;

        // Two triangles per quad, both wound the same way.
        indices[t++] = topLeft;
        indices[t++] = bottomLeft;
        indices[t++] = topRight;

        indices[t++] = topRight;
        indices[t++] = bottomLeft;
        indices[t++] = bottomRight;
      }
    }

    triangleDepth = Float32List(triangleCount);
    depthOrder = Uint16List(triangleCount);
    for (var i = 0; i < triangleCount; i++) {
      depthOrder[i] = i;
    }
    orderedIndices = Uint16List(triangleCount * 3);

    // Default the texture to the whole image; a page drawn from an atlas
    // overrides this.
    updateTextureRegion(
      Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
    );
    resetColors();
  }

  /// Maps the mesh's `0..1` page space onto [region] of the shader image.
  ///
  /// For a page that owns its whole image, [region] is the full image rect in
  /// pixels. For a page packed into an atlas, it is that page's sub-rect.
  ///
  /// When [mirrorHorizontally] is set the `u` axis is reversed, which is what
  /// makes the back face of a sheet read correctly instead of appearing
  /// mirrored.
  void updateTextureRegion(Rect region, {bool mirrorHorizontally = false}) {
    for (var i = 0; i < vertexCount; i++) {
      final u = normalized[i * 2];
      final v = normalized[i * 2 + 1];
      final su = mirrorHorizontally ? 1.0 - u : u;
      textureCoordinates[i * 2] = region.left + su * region.width;
      textureCoordinates[i * 2 + 1] = region.top + v * region.height;
    }
  }

  /// Resets every vertex to unlit white, the identity for `BlendMode.modulate`.
  void resetColors() {
    colors.fillRange(0, colors.length, 0xFFFFFFFF);
  }

  /// Restores the flat resting state: every vertex at `z = 0`, positioned at
  /// its undeformed place inside [origin] `&` [pageSize].
  ///
  /// The curl must agree with this exactly at `progress == 0`, or the first
  /// frame of a drag visibly jumps.
  void resetToFlat({Offset origin = Offset.zero}) {
    for (var i = 0; i < vertexCount; i++) {
      final x = origin.dx + normalized[i * 2] * pageSize.width;
      final y = origin.dy + normalized[i * 2 + 1] * pageSize.height;
      positions[i * 2] = x;
      positions[i * 2 + 1] = y;
      worldPositions[i * 3] = x;
      worldPositions[i * 3 + 1] = y;
      worldPositions[i * 3 + 2] = 0;
      normals[i * 3] = 0;
      normals[i * 3 + 1] = 0;
      normals[i * 3 + 2] = -1;
    }
  }

  /// Index of the vertex at grid position ([col], [row]).
  int vertexIndex(int col, int row) => row * (columns + 1) + col;

  /// Whether [other] describes the same grid over the same page, and can
  /// therefore reuse this mesh's buffers.
  bool matches({required Size pageSize, required int columns, required int rows}) =>
      this.pageSize == pageSize && this.columns == columns && this.rows == rows;

  @override
  String toString() =>
      'PageCurlMesh(${columns}x$rows, $vertexCount verts, '
      '$triangleCount tris, page $pageSize)';
}
