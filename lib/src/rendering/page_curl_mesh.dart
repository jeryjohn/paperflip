import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// The static topology of the page mesh, plus reusable buffers the curl
/// overwrites each frame.
///
/// Everything that does not depend on the curl is computed once:
///
///   * the grid of vertices in normalised page space (`u`, `v` in `0..1`),
///   * the triangle index buffer,
///   * reusable texture-coordinate, position, normal, lighting and depth
///     buffers.
///
/// The geometry/renderer update those buffers in place. This keeps the hot
/// drag path free of per-vertex Dart allocations. Flutter's `ui.Vertices`
/// object is still immutable/native-backed and therefore recreated by the
/// renderer when a frame is submitted.
@internal
class PageCurlMesh {
  /// Builds a mesh with an explicit grid size.
  ///
  /// [columns] and [rows] are quad counts, so the vertex grid is
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
        assert(
          pageSize.width.isFinite && pageSize.height.isFinite,
          'pageSize must be finite',
        ),
        vertexCount = (columns + 1) * (rows + 1),
        triangleCount = columns * rows * 2 {
    if (vertexCount > _maxIndexValue + 1) {
      throw ArgumentError(
        'Mesh has $vertexCount vertices, but the index buffer uses Uint16List '
        'and supports at most ${_maxIndexValue + 1}.',
      );
    }
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
  /// [columns] is the primary quality/performance tuning knob.
  factory PageCurlMesh.forPage({
    required Size pageSize,
    int columns = defaultColumns,
    int maxRows = 96,
  }) {
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

    if (columns < 1) {
      throw ArgumentError.value(
        columns,
        'columns',
        'must be at least 1',
      );
    }

    if (maxRows < 1) {
      throw ArgumentError.value(
        maxRows,
        'maxRows',
        'must be at least 1',
      );
    }

    final aspect = pageSize.height / pageSize.width;
    final rows = (columns * aspect).round().clamp(1, maxRows).toInt();

    return PageCurlMesh(
      columns: columns,
      rows: rows,
      pageSize: pageSize,
    );
  }

  /// Starting point for the column sweep, not a researched optimum.
  ///
  /// The renderer should benchmark alternative values on the target devices
  /// before changing this default.
  static const int defaultColumns = 32;

  static const int _maxIndexValue = 0xFFFF;

  /// Quad columns across the page width.
  final int columns;

  /// Quad rows down the page height.
  final int rows;

  /// The page's logical size.
  final Size pageSize;

  /// `(columns + 1) * (rows + 1)`.
  final int vertexCount;

  /// `columns * rows * 2`.
  final int triangleCount;

  // ── Static buffers, built once ────────────────────────────────────────────

  /// Normalised page coordinates, `[u0, v0, u1, v1, ...]`, each in `0..1`.
  ///
  /// `u` runs from the spine side to the free edge in page space. The actual
  /// physical direction is resolved by the curl geometry.
  late final Float32List normalized;

  /// Texture coordinates in the image shader's pixel space.
  ///
  /// `Vertices.textureCoordinates` are matched directly against an
  /// [ui.ImageShader], so these values are image pixels rather than normalised
  /// UVs. [updateTextureRegion] maps the normalised grid into a full image or
  /// atlas cell.
  late final Float32List textureCoordinates;

  /// Triangle indices, three per triangle.
  late final Uint16List indices;

  // ── Per-frame buffers, overwritten in place ───────────────────────────────

  /// Projected screen positions, `[x0, y0, x1, y1, ...]`.
  late final Float32List positions;

  /// Per-vertex lighting, ARGB, combined with the texture by
  /// `BlendMode.modulate`.
  late final Int32List colors;

  /// Deformed 3D positions before projection, `[x0, y0, z0, ...]`.
  late final Float32List worldPositions;

  /// Accumulated per-vertex normals, `[nx0, ny0, nz0, ...]`.
  late final Float32List normals;

  /// Per-triangle view depth, used for back-to-front ordering.
  late final Float32List triangleDepth;

  /// Triangle draw order, as indices into [triangleDepth].
  ///
  /// This starts as the identity permutation and is retained between frames so
  /// insertion sort can exploit the curl's temporal coherence.
  late final Uint16List depthOrder;

  /// Scratch index buffer for callers/tests that want a reordered copy without
  /// allocating. The current renderer maintains its own submission buffer, but
  /// this remains part of the mesh's reusable scratch storage.
  late final Uint16List orderedIndices;

  void _buildTopology() {
    final vertexColumns = columns + 1;
    final vertexRows = rows + 1;

    normalized = Float32List(vertexCount * 2);
    textureCoordinates = Float32List(vertexCount * 2);
    positions = Float32List(vertexCount * 2);
    worldPositions = Float32List(vertexCount * 3);
    normals = Float32List(vertexCount * 3);
    colors = Int32List(vertexCount);

    for (var row = 0; row < vertexRows; row++) {
      final v = row / rows;

      for (var col = 0; col < vertexColumns; col++) {
        final u = col / columns;
        final vertex = row * vertexColumns + col;

        normalized[vertex * 2] = u;
        normalized[vertex * 2 + 1] = v;
      }
    }

    indices = Uint16List(triangleCount * 3);

    var offset = 0;
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < columns; col++) {
        final topLeft = row * vertexColumns + col;
        final topRight = topLeft + 1;
        final bottomLeft = topLeft + vertexColumns;
        final bottomRight = bottomLeft + 1;

        // Both triangles use the same winding in the flat state.
        indices[offset++] = topLeft;
        indices[offset++] = bottomLeft;
        indices[offset++] = topRight;

        indices[offset++] = topRight;
        indices[offset++] = bottomLeft;
        indices[offset++] = bottomRight;
      }
    }

    triangleDepth = Float32List(triangleCount);
    depthOrder = Uint16List(triangleCount);

    for (var triangle = 0; triangle < triangleCount; triangle++) {
      depthOrder[triangle] = triangle;
    }

    orderedIndices = Uint16List(triangleCount * 3);

    // Start with a neutral full-page mapping. The actual renderer replaces
    // this with the captured image/atlas region before the first draw.
    updateTextureRegion(
      Rect.fromLTWH(
        0,
        0,
        pageSize.width,
        pageSize.height,
      ),
    );

    resetColors();
    resetToFlat();
  }

  /// Maps the mesh's `0..1` page space onto [region] of the shader image.
  ///
  /// [region] is expressed in image pixels, not logical page units.
  ///
  /// When [mirrorHorizontally] is true, `u` runs in the opposite direction.
  /// This is useful for a genuine reverse-side texture.
  void updateTextureRegion(
    Rect region, {
    bool mirrorHorizontally = false,
  }) {
    if (region.width <= 0 ||
        region.height <= 0 ||
        !region.left.isFinite ||
        !region.top.isFinite ||
        !region.right.isFinite ||
        !region.bottom.isFinite) {
      throw ArgumentError.value(
        region,
        'region',
        'must be finite and non-empty',
      );
    }

    for (var vertex = 0; vertex < vertexCount; vertex++) {
      final u = normalized[vertex * 2];
      final v = normalized[vertex * 2 + 1];

      final sampledU = mirrorHorizontally ? 1.0 - u : u;

      textureCoordinates[vertex * 2] = region.left + sampledU * region.width;
      textureCoordinates[vertex * 2 + 1] = region.top + v * region.height;
    }
  }

  /// Resets every vertex to unlit white, the identity for
  /// `BlendMode.modulate`.
  void resetColors() {
    colors.fillRange(0, colors.length, 0xFFFFFFFF);
  }

  /// Restores the flat resting state at [origin].
  ///
  /// The curl geometry should agree with this state exactly when progress is
  /// zero. Keeping this operation explicit also gives tests a deterministic
  /// reference state for the first frame and for renderer hand-off.
  void resetToFlat({Offset origin = Offset.zero}) {
    for (var vertex = 0; vertex < vertexCount; vertex++) {
      final x = origin.dx + normalized[vertex * 2] * pageSize.width;
      final y = origin.dy + normalized[vertex * 2 + 1] * pageSize.height;

      positions[vertex * 2] = x;
      positions[vertex * 2 + 1] = y;

      worldPositions[vertex * 3] = x;
      worldPositions[vertex * 3 + 1] = y;
      worldPositions[vertex * 3 + 2] = 0;

      normals[vertex * 3] = 0;
      normals[vertex * 3 + 1] = 0;
      normals[vertex * 3 + 2] = -1;
    }

    for (var triangle = 0; triangle < triangleCount; triangle++) {
      triangleDepth[triangle] = 0;
      depthOrder[triangle] = triangle;
    }
  }

  /// Index of the vertex at grid position ([col], [row]).
  int vertexIndex(int col, int row) {
    assert(col >= 0 && col <= columns);
    assert(row >= 0 && row <= rows);
    return row * (columns + 1) + col;
  }

  /// Whether [other] describes the same grid over the same page.
  ///
  /// A matching mesh can safely reuse all of its buffers.
  bool matches({
    required Size pageSize,
    required int columns,
    required int rows,
  }) =>
      this.pageSize == pageSize && this.columns == columns && this.rows == rows;

  @override
  String toString() => 'PageCurlMesh(${columns}x$rows, $vertexCount verts, '
      '$triangleCount tris, page $pageSize)';
}
