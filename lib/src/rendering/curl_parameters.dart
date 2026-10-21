import 'dart:math' as math;

import 'package:meta/meta.dart';

/// The complete geometric state of a page turn.
///
/// Deliberately not just `progress`: two gestures that have travelled the same
/// horizontal distance can look different when the page is grabbed at
/// different heights. [grabV] carries that physical information into the curl.
@immutable
@internal
class CurlParameters {
  const CurlParameters({
    required this.progress,
    this.grabV = 0.5,
    this.direction = 1,
    this.bendAmount = defaultBendAmount,
    this.tiltAmount = defaultTiltAmount,
    this.conicity = 0.0,
    this.droop = defaultDroop,
    this.cornerEdge = 0,
    this.cornerLift = 0.0,
  });

  /// Flat, unturned page.
  static const CurlParameters rest = CurlParameters(progress: 0);

  /// Peak wrap angle at the middle of the turn, in radians.
  ///
  /// This controls the actual curl radius. Rotation of the finished sheet is
  /// handled separately by the geometry so a near-flat final state can still
  /// be nearly 180 degrees around its spine without a geometric snap.
  static const double defaultBendAmount = 1.32;

  /// Legacy/public tuning value retained for API compatibility.
  ///
  /// The current cone formulation gets the physically meaningful diagonal
  /// variation from [conicity], which is derived from [grabV]. A per-row angle
  /// shear would break the developable/isometric surface, so this value is not
  /// applied directly by [PageCurlGeometry].
  static const double defaultTiltAmount = 0.30;

  /// Peak free-corner droop as a fraction of page height.
  static const double defaultDroop = 0.06;

  /// How far through the turn, `0` to `1`.
  final double progress;

  /// Vertical position where the user grabbed the sheet: `0` top, `1` bottom.
  final double grabV;

  /// `1` for a forward turn, `-1` for a backward turn.
  final int direction;

  /// Peak wrap angle in radians.
  final double bendAmount;

  /// Retained as a public compatibility/tuning field.
  ///
  /// See [defaultTiltAmount] for why the current physical cone implementation
  /// does not turn this into a non-rigid per-row shear.
  final double tiltAmount;

  /// Cone strength, `-1` to `1`.
  ///
  /// `0` is an exact cylinder. Positive/negative values make opposite ends of
  /// the page curl tighter.
  final double conicity;

  /// Free-corner sag as a fraction of page height.
  final double droop;

  /// Which corner of the free edge is being peeled.
  ///
  /// `0` (the default) keeps the spine-hinged cone curl. `-1` peels the top
  /// corner and `1` the bottom corner along a diagonal crease — the way paper
  /// folds when it is lifted by a corner. Discrete, like [direction].
  final int cornerEdge;

  /// Vertical displacement of the grabbed corner, as a fraction of page
  /// height (positive = down). Only meaningful when [cornerEdge] is non-zero.
  final double cornerLift;

  /// Whether this turn is a diagonal corner peel rather than a spine curl.
  bool get isCornerFold => cornerEdge != 0;

  /// Whether the state is the exact initial flat state.
  ///
  /// Progress `1` is intentionally **not** considered flat here. At the end of
  /// a turn the sheet's curvature approaches zero, but it is also rotated toward
  /// the destination side of the book. The geometry must render that rigidly
  /// rotated limit until the settle completes and the live destination page is
  /// handed back.
  bool get isFlat => progress <= 0.0;

  /// Maps a vertical grab position to cone strength.
  ///
  /// Middle grab => cylinder. Top/bottom grabs => opposite cone directions.
  static double resolveConicity(double grabV, {double strength = 0.85}) {
    final v = _finiteClamp(grabV, 0.0, 1.0);

    if (!strength.isFinite) {
      strength = 0.85;
    }

    final boundedStrength = strength.clamp(0.0, 1.0).toDouble();

    return ((0.5 - v) * 2.0 * boundedStrength).clamp(-1.0, 1.0).toDouble();
  }

  /// Builds parameters for a user gesture.
  factory CurlParameters.forGesture({
    required double progress,
    required double grabV,
    required int direction,
    double bendAmount = defaultBendAmount,
    double tiltAmount = defaultTiltAmount,
    double droop = defaultDroop,
    double conicStrength = 0.85,
    int cornerEdge = 0,
    double cornerLift = 0.0,
  }) {
    return CurlParameters(
      progress: _finiteClamp(progress, 0.0, 1.0),
      grabV: _finiteClamp(grabV, 0.0, 1.0),
      direction: direction >= 0 ? 1 : -1,
      bendAmount: _finiteNonNegative(bendAmount),
      tiltAmount: _finiteNonNegative(tiltAmount),
      conicity: resolveConicity(grabV, strength: conicStrength),
      droop: _finiteNonNegative(droop),
      cornerEdge: cornerEdge.sign,
      cornerLift: cornerLift.isFinite
          ? cornerLift.clamp(-1.0, 1.0).toDouble()
          : 0.0,
    );
  }

  CurlParameters copyWith({
    double? progress,
    double? grabV,
    int? direction,
    double? bendAmount,
    double? tiltAmount,
    double? conicity,
    double? droop,
    int? cornerEdge,
    double? cornerLift,
  }) => CurlParameters(
    progress: progress ?? this.progress,
    grabV: grabV ?? this.grabV,
    direction: direction ?? this.direction,
    bendAmount: bendAmount ?? this.bendAmount,
    tiltAmount: tiltAmount ?? this.tiltAmount,
    conicity: conicity ?? this.conicity,
    droop: droop ?? this.droop,
    cornerEdge: cornerEdge ?? this.cornerEdge,
    cornerLift: cornerLift ?? this.cornerLift,
  );

  /// Linear interpolation of the animated geometric fields.
  ///
  /// Direction and [cornerEdge] are discrete and therefore follow [b].
  static CurlParameters lerp(CurlParameters a, CurlParameters b, double t) {
    if (t <= 0) return a;
    if (t >= 1) return b;

    double mix(double x, double y) => x + (y - x) * t;

    return CurlParameters(
      progress: mix(a.progress, b.progress),
      grabV: mix(a.grabV, b.grabV),
      direction: b.direction,
      bendAmount: mix(a.bendAmount, b.bendAmount),
      tiltAmount: mix(a.tiltAmount, b.tiltAmount),
      conicity: mix(a.conicity, b.conicity),
      droop: mix(a.droop, b.droop),
      cornerEdge: b.cornerEdge,
      cornerLift: mix(a.cornerLift, b.cornerLift),
    );
  }

  /// Largest absolute difference across animated fields.
  double distanceTo(CurlParameters other) {
    var distance = (progress - other.progress).abs();
    distance = math.max(distance, (grabV - other.grabV).abs());
    distance = math.max(distance, (conicity - other.conicity).abs());
    distance = math.max(distance, (bendAmount - other.bendAmount).abs());
    distance = math.max(distance, (tiltAmount - other.tiltAmount).abs());
    distance = math.max(distance, (droop - other.droop).abs());
    distance = math.max(distance, (cornerLift - other.cornerLift).abs());

    return direction == other.direction && cornerEdge == other.cornerEdge
        ? distance
        : double.infinity;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CurlParameters &&
          other.progress == progress &&
          other.grabV == grabV &&
          other.direction == direction &&
          other.bendAmount == bendAmount &&
          other.tiltAmount == tiltAmount &&
          other.conicity == conicity &&
          other.droop == droop &&
          other.cornerEdge == cornerEdge &&
          other.cornerLift == cornerLift;

  @override
  int get hashCode => Object.hash(
    progress,
    grabV,
    direction,
    bendAmount,
    tiltAmount,
    conicity,
    droop,
    cornerEdge,
    cornerLift,
  );

  @override
  String toString() {
    final corner = isCornerFold
        ? ', corner: $cornerEdge, lift: ${cornerLift.toStringAsFixed(2)}'
        : '';
    return 'CurlParameters(t: ${progress.toStringAsFixed(3)}, '
        'grabV: ${grabV.toStringAsFixed(2)}, '
        'dir: $direction, '
        'conicity: ${conicity.toStringAsFixed(2)}$corner)';
  }

  static double _finiteClamp(double value, double min, double max) {
    if (!value.isFinite) return min;
    return value.clamp(min, max).toDouble();
  }

  static double _finiteNonNegative(double value) {
    if (!value.isFinite || value <= 0) return 0.0;
    return value;
  }
}

/// Keeps the displayed curl continuous when pointer input and display frames
/// do not arrive at the same cadence.
///
/// This is intentionally a response limiter rather than a heavy filter:
/// ordinary small finger movements follow immediately; only larger jumps are
/// eased over a few frames. The approach is time-based, so the feel remains
/// similar at 60, 90, and 120 Hz.
@internal
class CurlSmoother {
  CurlSmoother({
    this.responseRate = 26.0,
    this.passThroughDelta = 0.012,
    this.maxLagSeconds = 0.045,
  }) : assert(responseRate > 0),
       assert(passThroughDelta >= 0),
       assert(maxLagSeconds > 0);

  /// Exponential catch-up rate, per second.
  final double responseRate;

  /// Deltas below this threshold follow directly.
  final double passThroughDelta;

  /// Maximum amount of temporal lag permitted by the limiter.
  final double maxLagSeconds;

  CurlParameters _displayed = CurlParameters.rest;
  CurlParameters _target = CurlParameters.rest;

  /// What the renderer should draw now.
  CurlParameters get displayed => _displayed;

  /// Where the gesture/programmatic animation is trying to go.
  CurlParameters get target => _target;

  /// Whether the visual state has converged.
  bool get isSettled => _displayed.distanceTo(_target) < 1e-4;

  /// Records the latest target cheaply.
  void setTarget(CurlParameters value) {
    _target = value;
  }

  /// Snaps both states to [value].
  ///
  /// Used at the beginning of a new interaction, after a committed page, and
  /// for programmatic jumps where interpolation would create a discontinuity.
  void reset(CurlParameters value) {
    _displayed = value;
    _target = value;
  }

  /// Advances the displayed state toward the target.
  ///
  /// Returns true when a visible repaint is needed.
  bool advance(double dt) {
    final target = _target;
    final current = _displayed;

    // Direction is discrete. Crossing through zero between opposite directions
    // would invent a physically meaningless half-forward/half-backward state.
    if (current.direction != target.direction ||
        current.cornerEdge != target.cornerEdge) {
      _displayed = target;
      return true;
    }

    final delta = current.distanceTo(target);
    if (!delta.isFinite || delta < 1e-5) {
      if (delta < 1e-5) {
        _displayed = target;
      }
      return false;
    }

    // Ordinary dragging is direct.
    if (delta <= passThroughDelta) {
      _displayed = target;
      return true;
    }

    final step = dt.isFinite && dt > 0
        ? dt.clamp(0.0, 0.1).toDouble()
        : 1.0 / 60.0;

    var interpolation = 1.0 - math.exp(-responseRate * step);

    // Bound the temporal lag. A sustained fast drag therefore cannot slowly
    // build a larger and larger gap between the finger and the page.
    final lagFraction = (step / maxLagSeconds).clamp(0.0, 1.0).toDouble();

    interpolation = math.max(interpolation, lagFraction);

    _displayed = CurlParameters.lerp(
      current,
      target,
      interpolation.clamp(0.0, 1.0),
    );

    return true;
  }
}
