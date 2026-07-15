import 'package:flutter/widgets.dart';

/// Which corner of the page a flip originates from.
enum FlipCorner {
  /// Bottom-right corner — flips to the next page (default forward).
  bottomRight,

  /// Bottom-left corner — flips to the previous page (default backward).
  bottomLeft,

  /// Top-right corner — flips to the next page.
  topRight,

  /// Top-left corner — flips to the previous page.
  topLeft,
}

/// Returns `true` when the [position] falls inside the hot-corner zone.
///
/// Each hot corner is a [hotZoneSize] × [hotZoneSize] region in one of the
/// four corners of the widget with the given [size].
bool isInHotZone(
  Offset position,
  Size size,
  FlipCorner corner, {
  double hotZoneSize = 60.0,
}) {
  return switch (corner) {
    FlipCorner.bottomRight =>
      position.dx >= size.width - hotZoneSize &&
          position.dy >= size.height - hotZoneSize,
    FlipCorner.bottomLeft =>
      position.dx <= hotZoneSize &&
          position.dy >= size.height - hotZoneSize,
    FlipCorner.topRight =>
      position.dx >= size.width - hotZoneSize && position.dy <= hotZoneSize,
    FlipCorner.topLeft =>
      position.dx <= hotZoneSize && position.dy <= hotZoneSize,
  };
}

/// Returns the corner whose hot zone contains [position], or `null` if none.
FlipCorner? detectHotCorner(
  Offset position,
  Size size, {
  double hotZoneSize = 60.0,
}) {
  for (final corner in FlipCorner.values) {
    if (isInHotZone(position, size, corner, hotZoneSize: hotZoneSize)) {
      return corner;
    }
  }
  return null;
}

/// Returns `true` when the given [corner] flips forward (to a higher page index).
bool isForwardCorner(FlipCorner corner) =>
    corner == FlipCorner.bottomRight || corner == FlipCorner.topRight;
