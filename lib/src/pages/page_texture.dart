import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// A page rendered to pixels, ready to be mapped onto the curl mesh.
///
/// This is the boundary the whole renderer is built around: once EPUB, PDF or
/// a custom widget has produced a [PageTexture], nothing downstream knows or
/// cares which of them it came from.
///
/// ## Ownership
///
/// A `ui.Image` is a handle to native memory, not a garbage-collected Dart
/// object, and it must be disposed explicitly. A [PageTexture] **owns** its
/// handle: disposing the texture disposes the image.
///
/// When two parts of the renderer need the same pixels with independent
/// lifetimes — most importantly, when a cache entry may be evicted while a
/// flip is still drawing it — use [share] rather than passing the same
/// [PageTexture] instance around.
///
/// [share] and [slice] create a new image handle through `ui.Image.clone()`.
/// The underlying pixel storage is shared; no full pixel copy is made.
/// Each returned texture still owns and must dispose its own handle.
///
/// The rule this enforces: **never hold a `PageTexture` you did not create or
/// [share]**, and always dispose what you hold.
@immutable
@internal
class PageTexture {
  /// Wraps an already-rendered image.
  ///
  /// [logicalSize] is the size the page occupies on screen; [image] may be
  /// larger (a device-pixel-ratio multiple of it), and the two are deliberately
  /// separate so the mesh can be built in logical space while sampling at full
  /// resolution.
  PageTexture({
    required this.image,
    required this.logicalSize,
    this.textureRegion,
    this.key,
  })  : assert(
          logicalSize.width > 0 && logicalSize.height > 0,
          'logicalSize must be non-empty',
        ),
        assert(
          logicalSize.width.isFinite && logicalSize.height.isFinite,
          'logicalSize must be finite',
        ),
        assert(
          textureRegion == null ||
              (textureRegion.left.isFinite &&
                  textureRegion.top.isFinite &&
                  textureRegion.right.isFinite &&
                  textureRegion.bottom.isFinite),
          'textureRegion must be finite',
        );

  /// Tracks disposal of [image]. `ui.Image.debugDisposed` throws in release
  /// builds, so ownership is recorded here instead. A final reference to a
  /// mutable box keeps the class shallowly immutable.
  final DisposalFlag _disposal = DisposalFlag();

  /// The rendered pixels. Owned by this texture; see the class doc.
  final ui.Image image;

  /// The size the page occupies on screen, in logical pixels.
  final Size logicalSize;

  /// Which part of [image] belongs to this page, in image pixel space.
  ///
  /// `null` means the whole image, which is the common case: a page rendered
  /// on its own. A non-null region is how an atlased page addresses its cell.
  final Rect? textureRegion;

  /// Identifies what was rendered, so a cache can tell a stale texture from a
  /// current one. See [PageTextureKey].
  final PageTextureKey? key;

  /// The region actually sampled, resolving a null [textureRegion] to the
  /// whole image.
  Rect get region =>
      textureRegion ??
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());

  /// Whether the sample region lies entirely inside the backing image.
  ///
  /// Keeping this as a cheap check lets the renderer/atlas code reject a bad
  /// slice before a GPU upload or draw produces undefined-looking sampling.
  bool get hasValidRegion {
    final r = region;
    return r.left >= 0 &&
        r.top >= 0 &&
        r.right <= image.width &&
        r.bottom <= image.height &&
        r.width > 0 &&
        r.height > 0;
  }

  /// The image's pixel dimensions.
  Size get pixelSize => Size(image.width.toDouble(), image.height.toDouble());

  /// Pixels per logical pixel across the page's width.
  ///
  /// This is the number the texture-size benchmark tunes: below ~1.0 text
  /// turns mushy during the flip, and above the device ratio it costs memory
  /// for detail no display can show.
  ///
  /// Returns zero for an invalid region rather than producing an infinity or
  /// NaN that could poison downstream UV calculations.
  double get pixelRatio {
    final width = logicalSize.width;
    if (width <= 0) return 0;
    final ratio = region.width / width;
    return ratio.isFinite && ratio > 0 ? ratio : 0;
  }

  /// Approximate native image bytes held by this handle's backing image.
  ///
  /// This is intentionally approximate. It describes the raster dimensions,
  /// not allocator overhead, compression, GPU tiling, or shared-handle
  /// deduplication.
  int get approximateByteSize => image.width * image.height * 4;

  /// Whether the underlying image handle has been released.
  bool get isDisposed => _disposal.value;

  /// Returns an independently-owned handle to the same pixels.
  ///
  /// No pixel data is copied. Both the original and the returned texture must
  /// be disposed.
  PageTexture share() {
    _assertUsable();
    return PageTexture(
      image: image.clone(),
      logicalSize: logicalSize,
      textureRegion: textureRegion,
      key: key,
    );
  }

  /// Returns a view of the same image restricted to [region].
  ///
  /// Used to slice one tall rasterised EPUB chapter into its constituent
  /// pages without re-rendering. The returned texture shares the same backing
  /// pixels through an independently-owned image handle.
  ///
  /// [region] is expressed in the backing image's pixel coordinate space.
  PageTexture slice(
    Rect region, {
    required Size logicalSize,
    PageTextureKey? key,
  }) {
    _assertUsable();

    if (!logicalSize.width.isFinite ||
        !logicalSize.height.isFinite ||
        logicalSize.width <= 0 ||
        logicalSize.height <= 0) {
      throw ArgumentError.value(
        logicalSize,
        'logicalSize',
        'must be finite and non-empty',
      );
    }

    final imageBounds = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );

    // The page-slicing code should always generate exact in-bounds regions.
    // Fail early here instead of allowing a bad UV rectangle to propagate to
    // the renderer.
    if (!region.left.isFinite ||
        !region.top.isFinite ||
        !region.right.isFinite ||
        !region.bottom.isFinite ||
        region.width <= 0 ||
        region.height <= 0 ||
        !imageBounds.contains(Offset(region.left, region.top)) ||
        region.right > imageBounds.right ||
        region.bottom > imageBounds.bottom) {
      throw ArgumentError.value(
        region,
        'region',
        'must be a finite, non-empty region inside the image',
      );
    }

    return PageTexture(
      image: image.clone(),
      logicalSize: logicalSize,
      textureRegion: region,
      key: key ?? this.key,
    );
  }

  /// Releases this texture's handle on the image.
  ///
  /// Safe to call twice; the second call is a no-op. Other handles created by
  /// [share] or [slice] are unaffected.
  void dispose() {
    if (_disposal.value) return;
    _disposal.value = true;
    image.dispose();
  }

  void _assertUsable() {
    if (_disposal.value) {
      throw StateError('PageTexture has already been disposed.');
    }
  }

  @override
  String toString() => 'PageTexture(${image.width}x${image.height}px, '
      'logical $logicalSize, region $region, '
      'ratio ${pixelRatio.toStringAsFixed(2)}, key: $key)';
}

/// Everything that changes what a rendered page looks like.
///
/// A texture is valid only for the exact configuration that produced it, so
/// the cache is keyed by this rather than by a page index. Getting this wrong
/// is how a reader ends up showing a page laid out for the previous font size:
/// the index still matches, the pixels do not.
///
/// [contentVersion] is the escape hatch for anything not enumerated here — an
/// EPUB's layout generation, a theme change, a PDF re-rendered at a new
/// rotation. Bump it and every texture carrying the old value is stale.
@immutable
@internal
class PageTextureKey {
  const PageTextureKey({
    required this.sourceId,
    required this.pageId,
    required this.logicalSize,
    required this.pixelRatio,
    this.contentVersion = 0,
  });

  /// Identifies the document. Two books must never collide here.
  final Object sourceId;

  /// Identifies the page *within* that document.
  ///
  /// For PDF and custom pages this is normally the page index. For EPUB it is
  /// preferably a stable `(spineIndex, pageInDocument)` identity rather than
  /// the global page number, because the global number changes on reflow.
  final Object pageId;

  /// The size the page was laid out at.
  final Size logicalSize;

  /// The resolution multiplier it was rasterised at.
  final double pixelRatio;

  /// Bumped whenever anything else that affects rendering changes.
  final int contentVersion;

  PageTextureKey copyWith({
    Object? sourceId,
    Object? pageId,
    Size? logicalSize,
    double? pixelRatio,
    int? contentVersion,
  }) =>
      PageTextureKey(
        sourceId: sourceId ?? this.sourceId,
        pageId: pageId ?? this.pageId,
        logicalSize: logicalSize ?? this.logicalSize,
        pixelRatio: pixelRatio ?? this.pixelRatio,
        contentVersion: contentVersion ?? this.contentVersion,
      );

  /// Whether [other] refers to the same page of the same document, ignoring
  /// rendering resolution and viewport size.
  bool sameContentAs(PageTextureKey other) =>
      sourceId == other.sourceId &&
      pageId == other.pageId &&
      contentVersion == other.contentVersion;

  /// Whether the page identity and content generation match and the rendering
  /// configuration also matches exactly.
  bool matchesRenderConfiguration(PageTextureKey other) => this == other;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PageTextureKey &&
          other.sourceId == sourceId &&
          other.pageId == pageId &&
          other.logicalSize == logicalSize &&
          other.pixelRatio == pixelRatio &&
          other.contentVersion == contentVersion;

  @override
  int get hashCode =>
      Object.hash(sourceId, pageId, logicalSize, pixelRatio, contentVersion);

  @override
  String toString() => 'PageTextureKey($sourceId/$pageId @ $logicalSize '
      'x$pixelRatio v$contentVersion)';
}

/// The two faces of one physical sheet.
///
/// A turning sheet shows its front until it passes the halfway point and its
/// back afterwards. Modelling that as a pair, rather than swapping the page
/// index at the midpoint, is what keeps the content from visibly changing
/// under the user's finger.
///
/// [back] may be null when the visual model does not need it; the renderer can
/// fall back to plain paper for that case.
@immutable
@internal
class PageFaceSet {
  const PageFaceSet({required this.front, this.back});

  final PageTexture front;
  final PageTexture? back;

  /// Whether both faces use the exact same [ui.Image] handle.
  ///
  /// `ui.Image.clone()` creates a separate handle to the same native pixel
  /// storage, so Dart's public API cannot reliably tell whether two distinct
  /// handles ultimately reference the same backing allocation. We therefore
  /// only report `true` when the handles are literally identical.
  bool get isSingleImage {
    final other = back;
    return other == null || identical(front.image, other.image);
  }

  /// Disposes both faces' handles.
  ///
  /// Callers must only pass textures they own. A [PageFaceSet] does not clone
  /// them because ownership needs to stay explicit.
  void dispose() {
    front.dispose();
    back?.dispose();
  }

  @override
  String toString() => 'PageFaceSet(front: $front, back: $back)';
}

/// Mutable disposal marker held by otherwise-immutable handle classes.
@internal
class DisposalFlag {
  bool value = false;
}
