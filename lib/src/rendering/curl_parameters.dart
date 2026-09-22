import 'dart:math' as math;

import 'package:meta/meta.dart';

/// The complete geometric state of a page turn.
///
/// Deliberately *not* just `progress`. Two gestures that have travelled the
/// same horizontal distance look different if the user grabbed the page at the
/// top rather than the middle, and collapsing that away is what makes a page
/// turn read as an animation rather than as paper. [grabV] is what carries it.
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
  });

  /// Flat, un-turned page.
  static const CurlParameters rest = CurlParameters(progress: 0);

  /// Peak bend angle at mid-turn, in radians.
  ///
  /// This is the total angle the sheet wraps through, so the fold radius is
  /// `halfPageWidth / bendAmount`. Larger means a tighter curl.
  static const double defaultBendAmount = 1.32;

  /// Peak per-row shear of the fold angle, in radians. Makes the crease run
  /// diagonally for a corner grab instead of staying parallel to the spine.
  static const double defaultTiltAmount = 0.30;

  /// Peak droop of the free corner, as a fraction of page height.
  static const double defaultDroop = 0.06;

  /// How far through the turn, `0` (flat) to `1` (fully turned).
  final double progress;

  /// Where the sheet is held, as a fraction of page height: `0` is the top
  /// edge, `1` the bottom, `0.5` the middle.
  ///
  /// This drives both the fold's diagonal tilt and [conicity]'s sign, and so
  /// is the single parameter that distinguishes a corner pull from a
  /// centre-edge pull.
  final double grabV;

  /// `1` for a forward turn, `-1` for a backward one.
  final int direction;

  /// Peak wrap angle in radians. See [defaultBendAmount].
  final double bendAmount;

  /// Peak fold-angle shear in radians. See [defaultTiltAmount].
  final double tiltAmount;

  /// How cone-like the curl is, `-1` to `1`.
  ///
  /// `0` is an exact cylinder — the fold radius is constant down the whole
  /// spine. Non-zero makes the radius vary along the spine, which is what a
  /// cone is: one end of the fold curls tighter than the other. The sign
  /// selects which end, so a top grab and a bottom grab produce mirrored
  /// cones and a centre grab produces the cylinder between them.
  ///
  /// Derived from [grabV] by [resolveConicity] rather than set directly.
  final double conicity;

  /// Free-corner sag as a fraction of page height. Paper has weight; a lifted
  /// corner falls away from the held row.
  final double droop;

  /// Whether the page is flat, and so can skip the whole deform/project
  /// pipeline and draw as a plain rectangle.
  bool get isFlat => progress <= 0.0 || progress >= 1.0;

  /// Maps a grab position to a cone strength.
  ///
  /// A grab at the vertical centre gives a cylinder; grabs toward either edge
  /// give increasingly conical curls of opposite sign. The mapping is linear
  /// and passes through zero at the centre, so it is continuous — there is no
  /// point at which the geometry switches models.
  ///
  /// [strength] scales the whole effect; `0` pins the curl to a pure cylinder
  /// regardless of where the page is held.
  static double resolveConicity(double grabV, {double strength = 0.85}) {
    final v = grabV.isFinite ? grabV.clamp(0.0, 1.0) : 0.5;
    return ((0.5 - v) * 2.0 * strength).clamp(-1.0, 1.0);
  }

  /// Builds the parameters for a gesture, resolving [conicity] from [grabV].
  factory CurlParameters.forGesture({
    required double progress,
    required double grabV,
    required int direction,
    double bendAmount = defaultBendAmount,
    double tiltAmount = defaultTiltAmount,
    double droop = defaultDroop,
    double conicStrength = 0.85,
  }) {
    return CurlParameters(
      progress: progress.clamp(0.0, 1.0),
      grabV: grabV.clamp(0.0, 1.0),
      direction: direction >= 0 ? 1 : -1,
      bendAmount: bendAmount,
      tiltAmount: tiltAmount,
      conicity: resolveConicity(grabV, strength: conicStrength),
      droop: droop,
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
  }) =>
      CurlParameters(
        progress: progress ?? this.progress,
        grabV: grabV ?? this.grabV,
        direction: direction ?? this.direction,
        bendAmount: bendAmount ?? this.bendAmount,
        tiltAmount: tiltAmount ?? this.tiltAmount,
        conicity: conicity ?? this.conicity,
        droop: droop ?? this.droop,
      );

  /// Linear interpolation, used by the temporal smoother.
  ///
  /// [direction] is not interpolated — a half-forward, half-backward turn is
  /// meaningless — so it snaps to [b]'s value.
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
    );
  }

  /// Largest absolute difference across the animated fields.
  ///
  /// Used both to decide when the smoother has converged and to skip a repaint
  /// when nothing visible has changed.
  double distanceTo(CurlParameters other) {
    var d = (progress - other.progress).abs();
    d = math.max(d, (grabV - other.grabV).abs());
    d = math.max(d, (conicity - other.conicity).abs());
    d = math.max(d, (bendAmount - other.bendAmount).abs());
    d = math.max(d, (tiltAmount - other.tiltAmount).abs());
    d = math.max(d, (droop - other.droop).abs());
    return direction == other.direction ? d : double.infinity;
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
          other.droop == droop;

  @override
  int get hashCode => Object.hash(
        progress,
        grabV,
        direction,
        bendAmount,
        tiltAmount,
        conicity,
        droop,
      );

  @override
  String toString() => 'CurlParameters(t: ${progress.toStringAsFixed(3)}, '
      'grabV: ${grabV.toStringAsFixed(2)}, dir: $direction, '
      'conicity: ${conicity.toStringAsFixed(2)})';
}

/// Keeps the displayed curl continuous when pointer input is not.
///
/// Pointer events and display frames are independent. A fast finger can travel
/// a long way between two paints, and rendering each raw sample directly makes
/// the fold jump. But over-correcting is worse than the jump: a page that
/// trails the finger by 50 ms feels disconnected in a way that a small hitch
/// does not.
///
/// So this is a *response limiter*, not a filter. It is deliberately:
///
///   * **adaptive** — small deltas pass through essentially untouched, and only
///     a delta large enough to read as a jump is damped at all;
///   * **dt-aware** — the catch-up is per unit time, so it behaves identically
///     at 60, 90 and 120 Hz;
///   * **bounded** — [maxLagSeconds] caps how far behind the target the
///     displayed value may ever fall, so lag cannot accumulate.
@internal
class CurlSmoother {
  CurlSmoother({
    this.responseRate = 26.0,
    this.passThroughDelta = 0.012,
    this.maxLagSeconds = 0.045,
  });

  /// Exponential catch-up rate, per second. Higher is more direct.
  ///
  /// At 26/s, a 60 Hz frame closes ~35% of the remaining gap, which settles a
  /// jump in ~3 frames (≈50 ms) while leaving normal motion untouched.
  final double responseRate;

  /// Deltas at or below this pass straight through, undamped.
  ///
  /// A normal drag moves the curl by well under this per frame, so ordinary
  /// finger-following has *no* smoothing applied at all and therefore no lag.
  final double passThroughDelta;

  /// Hard ceiling on how far behind the target the display may fall.
  final double maxLagSeconds;

  CurlParameters _displayed = CurlParameters.rest;
  CurlParameters _target = CurlParameters.rest;

  /// What the renderer should draw this frame.
  CurlParameters get displayed => _displayed;

  /// Where the gesture actually is.
  CurlParameters get target => _target;

  /// Whether the display has caught up with the target.
  bool get isSettled => _displayed.distanceTo(_target) < 1e-4;

  /// Records where the gesture now is. Cheap; safe to call per pointer event.
  void setTarget(CurlParameters value) => _target = value;

  /// Snaps both states to [value], bypassing smoothing entirely.
  ///
  /// Used when continuity would be wrong rather than desirable: the start of a
  /// new gesture, a committed page, a programmatic jump, or a resize.
  void reset(CurlParameters value) {
    _displayed = value;
    _target = value;
  }

  /// Advances [displayed] toward [target] by one frame of [dt] seconds.
  ///
  /// Returns `true` when the displayed value changed and a repaint is needed.
  bool advance(double dt) {
    final target = _target;
    final current = _displayed;

    // A direction change is a new gesture, not something to interpolate
    // through — `distanceTo` reports infinity for it.
    if (current.direction != target.direction) {
      _displayed = target;
      return true;
    }

    final delta = current.distanceTo(target);
    if (delta < 1e-5) return false;

    // Small movement: follow exactly. This is the common case, and it is why
    // there is no perceptible lag during an ordinary drag.
    if (delta <= passThroughDelta) {
      _displayed = target;
      return true;
    }

    final step = dt.isFinite && dt > 0 ? dt.clamp(0.0, 0.1) : 1 / 60;

    // Frame-rate independent exponential approach: the fraction of the gap
    // closed per second is constant, so the feel does not change with refresh
    // rate.
    var t = 1.0 - math.exp(-responseRate * step);

    // Never lag further behind than maxLagSeconds' worth of travel. Without
    // this the exponential tail lets a sustained fast drag accumulate an
    // unbounded offset, which reads as the page sticking to the finger late.
    final maxLag = delta * (step / maxLagSeconds);
    if (maxLag < 1.0) t = math.max(t, maxLag);

    _displayed = CurlParameters.lerp(current, target, t.clamp(0.0, 1.0));
    return true;
  }
}
