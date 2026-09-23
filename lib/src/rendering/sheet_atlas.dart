import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'package:flip_book/src/pages/page_texture.dart';

/// The two faces of one sheet packed side by side into a single image.
///
/// ## Why this has to exist
///
/// A turning sheet can expose both faces during one continuous curl. Those
/// triangles are interleaved by depth because the page folds over itself.
///
/// `Canvas.drawVertices` uses one paint/shader for a draw call. Packing the
/// front and back into one image lets the renderer draw the entire turning
/// sheet in one depth-sorted pass while the texture coordinates select the
/// visible face.
///
/// This is intentionally a *two-face sheet atlas*, not a whole-book atlas.
/// The page source remains responsible for producing individual
/// [PageTexture]s; this class only prepares the currently turning sheet.
@immutable
@internal
class SheetAtlas {
  SheetAtlas._({
    required this.image,
    required this.frontRegion,
    required this.backRegion,
    required this.logicalSize,
    required this.ownsImage,
    PageTexture? borrowedFrom,
  }) : _borrowedFrom = borrowedFrom;

  /// The texture whose image a single-face atlas borrows, if any.
  final PageTexture? _borrowedFrom;

  /// Records disposal of an owned [image]. `ui.Image.debugDisposed` throws in
  /// release builds, so it cannot be used to answer [isDisposed].
  final DisposalFlag _disposal = DisposalFlag();

  /// Whether [image] is no longer usable — either this atlas released it, or
  /// the texture it borrows from was disposed.
  bool get isDisposed => _disposal.value || (_borrowedFrom?.isDisposed ?? false);

  /// One image containing the front face on the left and the back face on the
  /// right, unless this is a single-face atlas.
  final ui.Image image;

  /// Where the front face lives, in atlas-image pixel space.
  final Rect frontRegion;

  /// Where the back face lives, in atlas-image pixel space.
  ///
  /// For a single-face atlas this is exactly [frontRegion].
  final Rect backRegion;

  /// The logical size of the sheet face.
  final Size logicalSize;

  /// Whether this atlas owns [image].
  ///
  /// A single-face atlas borrows the front [PageTexture]'s image, so it must
  /// not dispose it. A packed two-face atlas owns its newly-created image.
  final bool ownsImage;

  /// Whether both faces point at the same region of the atlas.
  bool get isSingleFace => frontRegion == backRegion;

  /// Builds an atlas from a sheet's faces.
  ///
  /// When there is no distinct back face, the front image is borrowed directly
  /// with no raster copy. This keeps the common/idle preparation path cheap.
  ///
  /// When a back face exists, the two source regions are copied into a single
  /// atlas image with a small gutter between them. The gutter prevents linear
  /// filtering from sampling the neighbouring face at the cell boundary.
  static Future<SheetAtlas> pack(PageFaceSet faces) async {
    final front = faces.front;
    final back = faces.back;

    _validateTexture(front, name: 'front');

    if (back == null) {
      return SheetAtlas._(
        image: front.image,
        frontRegion: front.region,
        backRegion: front.region,
        logicalSize: front.logicalSize,
        ownsImage: false,
        borrowedFrom: front,
      );
    }

    _validateTexture(back, name: 'back');

    if (front.logicalSize != back.logicalSize) {
      throw StateError(
        'Cannot pack sheet faces with different logical sizes: '
        '${front.logicalSize} vs ${back.logicalSize}.',
      );
    }

    // The source textures normally have the same capture pixel ratio. We still
    // handle differing source dimensions safely by fitting both into the
    // larger destination cell. The renderer samples in atlas pixel space, so
    // both faces retain the same logical page bounds.
    const gutter = 2.0;
    final cellW = math.max(front.region.width, back.region.width);
    final cellH = math.max(front.region.height, back.region.height);

    if (cellW <= 0 || cellH <= 0 || !cellW.isFinite || !cellH.isFinite) {
      throw StateError(
        'Cannot pack empty or invalid page regions: '
        'front=${front.region}, back=${back.region}.',
      );
    }

    final totalW = (cellW * 2 + gutter).ceil();
    final totalH = cellH.ceil();

    if (totalW <= 0 || totalH <= 0) {
      throw StateError(
        'Calculated an invalid atlas size: ${totalW}x$totalH.',
      );
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = false;

    final frontRegion = Rect.fromLTWH(0, 0, cellW, cellH);
    final backRegion = Rect.fromLTWH(cellW + gutter, 0, cellW, cellH);

    try {
      _drawIntoCell(
        canvas,
        source: front,
        destination: frontRegion,
        paint: paint,
      );
      _drawIntoCell(
        canvas,
        source: back,
        destination: backRegion,
        paint: paint,
      );

      final picture = recorder.endRecording();
      try {
        final image = await picture.toImage(totalW, totalH);

        return SheetAtlas._(
          image: image,
          frontRegion: frontRegion,
          backRegion: backRegion,
          logicalSize: front.logicalSize,
          ownsImage: true,
        );
      } finally {
        picture.dispose();
      }
    } catch (_) {
      // The recorder is only a Dart-side recording object. Make sure it is
      // ended on failure too so this path does not retain resources longer
      // than necessary.
      try {
        recorder.endRecording().dispose();
      } catch (_) {
        // There is nothing useful to recover here; the original error is more
        // informative to the caller.
      }
      rethrow;
    }
  }

  /// Releases the atlas image when this object owns it.
  ///
  /// Single-face atlases borrow the front texture's image and therefore leave
  /// disposal to [PageTexture].
  void dispose() {
    if (!ownsImage || _disposal.value) return;
    _disposal.value = true;
    image.dispose();
  }

  @override
  String toString() => 'SheetAtlas(${image.width}x${image.height}, '
      'single: $isSingleFace, ownsImage: $ownsImage)';

  static void _validateTexture(
    PageTexture texture, {
    required String name,
  }) {
    if (texture.isDisposed) {
      throw StateError('Cannot pack disposed $name PageTexture.');
    }

    if (!texture.hasValidRegion) {
      throw StateError(
        'Cannot pack $name PageTexture with invalid region: '
        '${texture.region}.',
      );
    }

    if (texture.logicalSize.isEmpty ||
        !texture.logicalSize.width.isFinite ||
        !texture.logicalSize.height.isFinite) {
      throw StateError(
        'Cannot pack $name PageTexture with invalid logical size: '
        '${texture.logicalSize}.',
      );
    }
  }

  static void _drawIntoCell(
    Canvas canvas, {
    required PageTexture source,
    required Rect destination,
    required Paint paint,
  }) {
    canvas.drawImageRect(
      source.image,
      source.region,
      destination,
      paint,
    );
  }
}
