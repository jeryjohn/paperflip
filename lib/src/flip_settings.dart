import 'package:flutter/widgets.dart';

/// Axis along which pages turn.
///
/// Only [horizontal] is implemented; the enum exists so the axis is part of
/// the API from the start rather than being retrofitted later.
enum FlipDirection {
  /// Pages turn left/right around a vertical spine.
  horizontal,
}

/// Configuration for the page-flip animation, independent of the document
/// being displayed.
///
/// ```dart
/// FlipBookWidget(
///   pageCount: 10,
///   pageBuilder: (context, index, constraints) => MyPage(index),
///   flip: const FlipSettings(
///     duration: Duration(milliseconds: 450),
///     curve: Curves.easeOut,
///   ),
/// )
/// ```
///
/// Setting [enabled] to `false` keeps navigation working but changes pages
/// instantly, with no curl:
///
/// ```dart
/// FlipBookWidget(
///   pageCount: 10,
///   pageBuilder: (context, index, constraints) => MyPage(index),
///   flip: const FlipSettings(enabled: false),
/// )
/// ```
@immutable
class FlipSettings {
  /// Creates flip settings. All parameters are optional; the defaults match
  /// the package's original hard-coded behaviour.
  const FlipSettings({
    this.enabled = true,
    this.duration = const Duration(milliseconds: 600),
    this.curve = Curves.easeInOut,
    this.settleCurve = Curves.easeOut,
    this.direction = FlipDirection.horizontal,
    this.showShadow = true,
    this.showBackFace = true,
  });

  /// Whether the page-curl animation runs.
  ///
  /// When `false`, pages change instantly: swiping and controller calls still
  /// navigate, but no curl is drawn and no animation is scheduled.
  final bool enabled;

  /// Duration of a full page-flip animation.
  ///
  /// A released drag settles proportionally to how far it still has to travel,
  /// so a partial drag finishes faster than this.
  final Duration duration;

  /// Easing for a programmatic flip (a controller call or a button).
  final Curve curve;

  /// Easing used when a released drag settles to fully-open or fully-closed.
  ///
  /// Deliberately separate from [curve]: a released drag is already in motion,
  /// so an ease-*in* curve reads as a stall. Defaults to [Curves.easeOut].
  final Curve settleCurve;

  /// Axis along which pages turn. Only [FlipDirection.horizontal] is
  /// implemented.
  final FlipDirection direction;

  /// Whether the curl casts a shadow and picks up a crease highlight.
  final bool showShadow;

  /// Whether the turning page's own content is mirrored onto the lifted flap.
  ///
  /// When `false` the flap is filled with the plain paper gradient instead,
  /// which is cheaper: the page content is built once per flip rather than
  /// twice.
  final bool showBackFace;

  /// Returns a copy with the given fields replaced.
  FlipSettings copyWith({
    bool? enabled,
    Duration? duration,
    Curve? curve,
    Curve? settleCurve,
    FlipDirection? direction,
    bool? showShadow,
    bool? showBackFace,
  }) {
    return FlipSettings(
      enabled: enabled ?? this.enabled,
      duration: duration ?? this.duration,
      curve: curve ?? this.curve,
      settleCurve: settleCurve ?? this.settleCurve,
      direction: direction ?? this.direction,
      showShadow: showShadow ?? this.showShadow,
      showBackFace: showBackFace ?? this.showBackFace,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FlipSettings &&
        other.enabled == enabled &&
        other.duration == duration &&
        other.curve == curve &&
        other.settleCurve == settleCurve &&
        other.direction == direction &&
        other.showShadow == showShadow &&
        other.showBackFace == showBackFace;
  }

  @override
  int get hashCode => Object.hash(
    enabled,
    duration,
    curve,
    settleCurve,
    direction,
    showShadow,
    showBackFace,
  );

  @override
  String toString() =>
      'FlipSettings(enabled: $enabled, duration: $duration, curve: $curve, '
      'settleCurve: $settleCurve, direction: $direction, '
      'showShadow: $showShadow, showBackFace: $showBackFace)';
}
