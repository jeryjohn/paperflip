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
/// lifetimes — a cache entry that may be evicted while a flip is still drawing
/// it, most importantly — use [share] rather than passing the same instance
/// around. It calls `ui.Image.clone()`, which adds a reference to the same
/// underlying pixels without copying them, and yields a texture whose
/// [dispose] releases only that new handle.
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
  }) : assert(
          logicalSize.width > 0 && logicalSize.height > 0,
          'logicalSize must be non-empty',
        );

  /// The rendered pixels. Owned by this texture; see the class doc.
  final ui.Image image;

  /// The size the page occupies on screen, in logical pixels.
  final Size logicalSize;

  /// Which part of [image] belongs to this page, in image pixel space.
  ///
  /// `null` means the whole image, which is the common case: a page rendered
  /// on its own. A non-null region is how an atlased page addresses its cell.
  /// Kept in the contract from the start so that adding an atlas later is a
  /// change of one value, not a change of the renderer.
  final Rect? textureRegion;

  /// Identifies what was rendered, so a cache can tell a stale texture from a
  /// current one. See [PageTextureKey].
  final PageTextureKey? key;

  /// The region actually sampled, resolving a null [textureRegion] to the
  /// whole image.
  Rect get region =>
      textureRegion ??
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());

  /// The image's pixel dimensions.
  Size get pixelSize =>
      Size(image.width.toDouble(), image.height.toDouble());

  /// Pixels per logical pixel across the page's width.
  ///
  /// This is the number the texture-size benchmark tunes: below ~1.0 text
  /// turns mushy during the flip, and above the device ratio it costs memory
  /// for detail no display can show.
  double get pixelRatio => region.width / logicalSize.width;

  /// Approximate GPU bytes held, for the cache's budget.
  int get approximateByteSize => image.width * image.height * 4;

  /// Whether the underlying image handle has been released.
  bool get isDisposed => image.debugDisposed;

  /// Returns an independently-owned handle to the same pixels.
  ///
  /// No pixel data is copied. Both the original and the copy must be disposed.
  PageTexture share() => PageTexture(
        image: image.clone(),
        logicalSize: logicalSize,
        textureRegion: textureRegion,
        key: key,
      );

  /// Returns a view of the same image restricted to [region].
  ///
  /// Used to slice one tall rasterised EPUB chapter into its constituent
  /// pages without re-rendering: each page is a sub-rect of the same image,
  /// so a chapter costs one rasterisation and one texture upload rather than
  /// one per page. The returned texture holds its own handle.
  PageTexture slice(Rect region, {required Size logicalSize, PageTextureKey? key}) =>
      PageTexture(
        image: image.clone(),
        logicalSize: logicalSize,
        textureRegion: region,
        key: key ?? this.key,
      );

  /// Releases this texture's handle on the image.
  ///
  /// Safe to call twice; the second call is a no-op. Other handles created by
  /// [share] or [slice] are unaffected.
  void dispose() {
    if (!image.debugDisposed) image.dispose();
  }

  @override
  String toString() =>
      'PageTexture(${image.width}x${image.height}px, '
      'logical $logicalSize, ratio ${pixelRatio.toStringAsFixed(2)}, key: $key)';
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
  /// For PDF and custom pages this is the page index. For EPUB it must be a
  /// stable `(spineIndex, pageInDocument)` pair rather than the global page
  /// number, because the global number changes on every reflow while the
  /// pixels for a given spine position do not.
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
  /// the rendering configuration.
  ///
  /// Lets the cache serve a wrong-resolution texture as a placeholder while the
  /// correct one renders, instead of showing a blank sheet.
  bool sameContentAs(PageTextureKey other) =>
      sourceId == other.sourceId &&
      pageId == other.pageId &&
      contentVersion == other.contentVersion;

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
/// [back] may be null when the visual model does not need it (the very last
/// sheet of a book, or a mode that draws the flap as blank paper); the renderer
/// falls back to a plain paper fill in that case.
@immutable
@internal
class PageFaceSet {
  const PageFaceSet({required this.front, this.back});

  final PageTexture front;
  final PageTexture? back;

  /// Whether the two faces share one image, and so need only one shader.
  bool get isSingleImage =>
      back == null || identical(front.image, back!.image);

  /// Disposes both faces' handles.
  void dispose() {
    front.dispose();
    back?.dispose();
  }

  @override
  String toString() => 'PageFaceSet(front: $front, back: $back)';
}
