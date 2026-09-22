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
/// `RepaintBoundary`, and hidden behind an opaque cover.
///
/// The cover specifically is *not* `Offstage` and *not* `Opacity(0)`. Both of
/// those skip painting as an optimisation, which is exactly the thing capture
/// depends on — under either one `toImage` yields a blank or throws. An opaque
/// widget drawn on top still lets the subtree beneath it paint normally.
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
  WidgetPageRasterizer({this.pixelRatio = 2.0});

  /// Resolution multiplier for captured pages.
  ///
  /// Deliberately not the device pixel ratio by default. A 3x capture of a
  /// full-screen page is a large texture to upload and hold, and during a flip
  /// the sheet is moving and foreshortened, so the extra detail is largely
  /// invisible. 2x keeps body text crisp at a quarter of the memory of 3x.
  final double pixelRatio;

  /// Captures the boundary behind [key].
  ///
  /// Returns `null` when the boundary is not ready — not yet laid out, not yet
  /// painted, or detached. That is an expected transient on the first frame,
  /// not an error; the caller retries on the next frame.
  Future<PageTexture?> capture(
    GlobalKey key, {
    required Size logicalSize,
    PageTextureKey? textureKey,
  }) async {
    final context = key.currentContext;
    if (context == null) return null;

    final boundary = context.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    if (!boundary.attached || boundary.debugNeedsPaint) return null;
    if (!boundary.hasSize || boundary.size.isEmpty) return null;

    try {
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      return PageTexture(
        image: image,
        logicalSize: logicalSize,
        key: textureKey,
      );
    } on Object {
      // Most commonly a platform view in the subtree. Surfacing null lets the
      // caller fall back to the live widget rather than showing a blank sheet.
      return null;
    }
  }
}

/// Mounts pages so they can be captured, without showing them.
///
/// Sits at the bottom of a [Stack] beneath the visible content. The pages paint
/// normally — which is what makes them capturable — but nothing of them reaches
/// the screen, because the reader's own content is drawn over the top.
///
/// Only the pages in [indices] are mounted, so the cost is bounded by the
/// preparation window (previous, current, next) rather than by the length of
/// the book.
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
    return SizedBox(
      width: pageSize.width,
      height: pageSize.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final index in indices)
            // Every page is stacked at the same place. Only the last one is
            // visible, and all of them are hidden by the caller's content --
            // what matters is that each one lays out and paints.
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
    );
  }
}

/// A bounded cache of captured page textures.
///
/// Holds a window around the current page rather than the whole book: a reader
/// only ever needs the sheet it is turning and the pages either side of it, and
/// keeping more would put an unbounded number of full-page images on the GPU.
///
/// Eviction disposes the image. Nothing else will — a `ui.Image` is a handle to
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
  PageTexture? operator [](PageTextureKey key) {
    final entry = _entries[key];
    if (entry != null) {
      // Refresh recency.
      _order.remove(key);
      _order.add(key);
    }
    return entry;
  }

  /// Whether [key] is already held.
  bool contains(PageTextureKey key) => _entries.containsKey(key);

  /// Stores [texture], evicting the least recently used entry if needed.
  ///
  /// Replacing an existing key disposes the texture it replaces.
  void put(PageTextureKey key, PageTexture texture) {
    final existing = _entries[key];
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
  /// viewport resize, or an EPUB re-paginating.
  void retainWhere(bool Function(PageTextureKey key) keep) {
    final doomed = _order.where((k) => !keep(k)).toList();
    for (final key in doomed) {
      _order.remove(key);
      _entries.remove(key)?.dispose();
    }
  }

  /// Number of textures currently held.
  int get length => _entries.length;

  /// Total bytes approximately held, for the memory benchmark.
  int get approximateByteSize =>
      _entries.values.fold(0, (sum, t) => sum + t.approximateByteSize);

  /// Disposes every texture and empties the cache.
  void clear() {
    for (final texture in _entries.values) {
      texture.dispose();
    }
    _entries.clear();
    _order.clear();
  }
}
