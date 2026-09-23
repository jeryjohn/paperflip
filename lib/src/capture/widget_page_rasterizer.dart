import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'package:flip_book/src/pages/page_texture.dart';

/// Captures live Flutter page widgets into [PageTexture]s.
///
/// ## Why the pages are hosted, not rendered off-tree
///
/// There is no way to rasterise a `Widget` that is not in the tree: it has no
/// element, no render object and no layer, so there is nothing to paint. The
/// only capture primitive Flutter offers is
/// `RenderRepaintBoundary.toImage`, which reads back a boundary that **has
/// already painted at least once**.
///
/// So the pages to be captured are mounted for real, each under its own
/// [RepaintBoundary]. They remain part of the paint pipeline while an
/// opaque/visible reader layer covers them.
///
/// The capture host deliberately does **not** use `Offstage`, `Opacity(0)` or
/// `Visibility(visible: false)`, because those may prevent the subtree from
/// painting. A subtree that has not painted cannot be read back reliably by
/// `toImage`.
///
/// ## Timing
///
/// A page can only be captured after the frame in which it first painted, so
/// every capture costs at least one frame of latency. That is the entire reason
/// the renderer prepares textures *ahead* of interaction: the first pointer
/// move must never be what triggers a rasterisation.
///
/// ## Limits
///
/// Platform views cannot be captured — a `WebView` or a native map renders
/// blank on Android and throws on iOS, and on web it is composited outside the
/// Flutter canvas entirely. Pages containing them are not supported by the
/// curl, and [capture] surfaces the failure rather than silently producing a
/// blank sheet.
@internal
class WidgetPageRasterizer {
  WidgetPageRasterizer({this.pixelRatio = 2.0})
      : assert(pixelRatio > 0),
        assert(pixelRatio.isFinite);

  /// Resolution multiplier for captured pages.
  ///
  /// Deliberately not the device pixel ratio by default. A 3x capture of a
  /// full-screen page is a large texture to upload and hold, and during a flip
  /// the sheet is moving and foreshortened, so the extra detail is largely
  /// invisible. 2x keeps body text crisp at a quarter of the memory of 4x.
  final double pixelRatio;

  double get _safePixelRatio =>
      pixelRatio.isFinite && pixelRatio > 0 ? pixelRatio : 1.0;

  /// Captures the boundary behind [key].
  ///
  /// Returns `null` when the boundary is not ready — not yet laid out, not yet
  /// painted, detached, or sized differently from [logicalSize]. Those are
  /// expected transient states; the caller should retry on a later frame.
  Future<PageTexture?> capture(
    GlobalKey key, {
    required Size logicalSize,
    PageTextureKey? textureKey,
  }) async {
    if (logicalSize.isEmpty ||
        !logicalSize.width.isFinite ||
        !logicalSize.height.isFinite) {
      return null;
    }

    final context = key.currentContext;
    if (context == null) return null;

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;

    final boundary = renderObject;
    if (!boundary.attached ||
        boundary.debugNeedsPaint ||
        !boundary.hasSize ||
        boundary.size.isEmpty) {
      return null;
    }

    // The texture coordinates and mesh dimensions are based on the logical
    // page size. Capturing a differently-sized boundary would stretch content
    // and is especially visible on text-heavy EPUB pages.
    const tolerance = 0.5;
    if ((boundary.size.width - logicalSize.width).abs() > tolerance ||
        (boundary.size.height - logicalSize.height).abs() > tolerance) {
      return null;
    }

    try {
      final image = await boundary.toImage(
        pixelRatio: _safePixelRatio,
      );

      // Be defensive about unusual renderer/platform implementations that may
      // return an invalid image handle after a failed readback.
      if (image.width <= 0 || image.height <= 0) {
        image.dispose();
        return null;
      }

      return PageTexture(
        image: image,
        logicalSize: logicalSize,
        key: textureKey,
      );
    } on Object {
      // Most commonly a platform view in the subtree. Surfacing null lets the
      // caller retry/fall back to the live widget rather than showing a blank
      // sheet.
      return null;
    }
  }
}

/// Mounts pages so they can be captured, without showing them.
///
/// Sits at the bottom of a [Stack] beneath the visible content. The pages paint
/// normally — which is what makes them capturable — but nothing of them should
/// reach the screen because the reader's visible layers are above this host.
///
/// Only the pages in [indices] are mounted, so the cost is bounded by the
/// preparation window rather than by the length of the book.
@internal
class PageCaptureHost extends StatelessWidget {
  const PageCaptureHost({
    super.key,
    required this.indices,
    required this.keyFor,
    required this.pageSize,
    required this.builder,
  });

  /// The page indices to keep mounted and capturable.
  final List<int> indices;

  /// Supplies the stable [GlobalKey] identifying each page's boundary.
  final GlobalKey Function(int index) keyFor;

  /// The logical size each page is laid out at. Must match the size the page
  /// will eventually occupy, or the captured texture will not line up.
  final Size pageSize;

  /// Builds the page content.
  final Widget Function(BuildContext context, int index) builder;

  @override
  Widget build(BuildContext context) {
    if (pageSize.isEmpty) return const SizedBox.shrink();

    // Defensive de-duplication keeps callers from accidentally mounting the
    // same GlobalKey twice. Preserve caller order because the last entry is the
    // top-most capture host, although all entries are expected to be covered by
    // the visible reader layers.
    final uniqueIndices = <int>[];
    final seen = <int>{};
    for (final index in indices) {
      if (seen.add(index)) {
        uniqueIndices.add(index);
      }
    }

    return IgnorePointer(
      child: ExcludeSemantics(
        child: SizedBox(
          width: pageSize.width,
          height: pageSize.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final index in uniqueIndices)
                Positioned(
                  left: 0,
                  top: 0,
                  width: pageSize.width,
                  height: pageSize.height,
                  child: RepaintBoundary(
                    key: keyFor(index),
                    child: builder(context, index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A bounded cache of captured page textures.
///
/// Holds a window around the current page rather than the whole book: a reader
/// only ever needs the sheet it is turning and the pages either side of it, and
/// keeping more would put an unbounded number of full-page images on the GPU.
///
/// Eviction disposes the image. Nothing else will — a [ui.Image] is a handle to
/// native memory that the Dart garbage collector does not account for, so a
/// cache that merely drops references leaks for the life of the process.
@internal
class PageTextureCache {
  PageTextureCache({this.capacity = 5}) : assert(capacity > 0);

  /// Maximum number of textures held at once.
  ///
  /// Five covers a preparation window of `current ± 2`, which is enough for a
  /// flip already in flight plus the next one in either direction.
  final int capacity;

  final Map<PageTextureKey, PageTexture> _entries = {};
  final List<PageTextureKey> _order = [];

  /// The texture for [key], or `null` when it has not been captured.
  ///
  /// Reading an item also promotes it to most-recently-used, because texture
  /// access during sheet packing means that item is actively needed.
  PageTexture? operator [](PageTextureKey key) {
    final entry = _entries[key];
    if (entry == null) return null;

    _order.remove(key);
    _order.add(key);
    return entry;
  }

  /// Whether [key] is already held.
  bool contains(PageTextureKey key) => _entries.containsKey(key);

  /// Stores [texture], evicting the least recently used entry if needed.
  ///
  /// Replacing an existing key disposes the previous texture. A defensive
  /// identity check avoids disposing the exact object being stored.
  void put(PageTextureKey key, PageTexture texture) {
    final existing = _entries[key];

    if (identical(existing, texture)) {
      _order.remove(key);
      _order.add(key);
      return;
    }

    if (existing != null) {
      existing.dispose();
      _order.remove(key);
    }

    _entries[key] = texture;
    _order.add(key);

    while (_order.length > capacity) {
      final oldest = _order.removeAt(0);
      _entries.remove(oldest)?.dispose();
    }
  }

  /// Drops every entry whose key does not satisfy [keep], disposing each.
  ///
  /// Used when something invalidates a whole generation of textures — a
  /// viewport resize, an EPUB re-pagination, or a content-version change.
  void retainWhere(bool Function(PageTextureKey key) keep) {
    final doomed = <PageTextureKey>[];
    for (final key in _order) {
      if (!keep(key)) doomed.add(key);
    }

    for (final key in doomed) {
      _order.remove(key);
      _entries.remove(key)?.dispose();
    }
  }

  /// Number of textures currently held.
  int get length => _entries.length;

  /// Total bytes approximately held, for the memory benchmark.
  int get approximateByteSize => _entries.values.fold(0, (sum, texture) {
        return sum + texture.approximateByteSize;
      });

  /// Disposes every texture and empties the cache.
  void clear() {
    for (final texture in _entries.values) {
      texture.dispose();
    }
    _entries.clear();
    _order.clear();
  }
}
