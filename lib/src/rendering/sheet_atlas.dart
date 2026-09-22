import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'package:flip_book/src/pages/page_texture.dart';

/// The two faces of one sheet packed side by side into a single image.
///
/// ## Why this has to exist
///
/// A turning sheet shows its front and its back at the same time: once the
/// curl passes vertical, part of the mesh faces away and must sample the back
/// page. Those triangles are *interleaved* with front-facing ones in draw
/// order, because draw order is decided by depth and the sheet folds over
/// itself.
///
/// `Canvas.drawVertices` samples exactly one shader, and a shader wraps exactly
/// one image. Drawing all front triangles and then all back triangles would
/// need two calls — and two calls cannot interleave, so the fold would
/// visibly draw in the wrong order wherever the sheet overlaps itself.
///
/// Packing both faces into one image makes the whole sheet one draw call with
/// one shader, and lets the triangle order be purely a function of depth. Each
/// triangle picks its face by which half of the image its texture coordinates
/// point at.
///
/// This is *not* the multi-page atlas the implementation plan defers: it is two
/// cells, built once per sheet, and the renderer works without it (a sheet with
/// no back face skips it entirely).
@immutable
@internal
class SheetAtlas {
  const SheetAtlas._({
    required this.image,
    required this.frontRegion,
    required this.backRegion,
    required this.logicalSize,
  });

  /// One image holding the front face in its left half and the back in its
  /// right.
  final ui.Image image;

  /// Where the front face lives, in [image] pixel space.
  final Rect frontRegion;

  /// Where the back face lives, in [image] pixel space. Identical to
  /// [frontRegion] when the sheet has no distinct back.
  final Rect backRegion;

  /// The logical size of one face.
  final Size logicalSize;

  /// Whether both faces resolve to the same pixels.
  bool get isSingleFace => frontRegion == backRegion;

  /// Builds an atlas from a sheet's faces.
  ///
  /// When [faces] has no back, the front texture is used directly with no
  /// copy and no extra memory — [isSingleFace] is then true and both regions
  /// address the same pixels.
  ///
  /// A one-pixel gutter separates the two cells. Bilinear sampling reads
  /// slightly outside a triangle's own texture coordinates at cell edges, and
  /// without the gutter the front face would bleed a sliver of the back face
  /// along the fold — a thin, hard-to-diagnose seam exactly where the eye is
  /// already looking.
  static Future<SheetAtlas> pack(PageFaceSet faces) async {
    final front = faces.front;
    final back = faces.back;

    if (back == null) {
      return SheetAtlas._(
        image: front.image,
        frontRegion: front.region,
        backRegion: front.region,
        logicalSize: front.logicalSize,
      );
    }

    const gutter = 1.0;
    final cellW = math.max(front.region.width, back.region.width);
    final cellH = math.max(front.region.height, back.region.height);
    final totalW = (cellW * 2 + gutter).ceil();
    final totalH = cellH.ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..filterQuality = FilterQuality.high;

    final frontRegion = Rect.fromLTWH(0, 0, cellW, cellH);
    final backRegion = Rect.fromLTWH(cellW + gutter, 0, cellW, cellH);

    canvas.drawImageRect(front.image, front.region, frontRegion, paint);
    canvas.drawImageRect(back.image, back.region, backRegion, paint);

    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(totalW, totalH);
      return SheetAtlas._(
        image: image,
        frontRegion: frontRegion,
        backRegion: backRegion,
        logicalSize: front.logicalSize,
      );
    } finally {
      picture.dispose();
    }
  }

  /// Releases the packed image.
  ///
  /// Skipped when [isSingleFace], since the image is then owned by the caller's
  /// front [PageTexture] and disposing it here would be a double free.
  void dispose() {
    if (!isSingleFace && !image.debugDisposed) image.dispose();
  }

  @override
  String toString() => 'SheetAtlas(${image.width}x${image.height}, '
      'single: $isSingleFace)';
}
