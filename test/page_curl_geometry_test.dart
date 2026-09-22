import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flip_book/src/rendering/curl_parameters.dart';
import 'package:flip_book/src/rendering/page_curl_camera.dart';
import 'package:flip_book/src/rendering/page_curl_geometry.dart';
import 'package:flip_book/src/rendering/page_curl_mesh.dart';

/// The progress values the plan calls out, including the ones either side of
/// the ends where a naive schedule tends to misbehave.
const _progresses = <double>[
  0.0,
  0.01,
  0.1,
  0.25,
  0.5,
  0.75,
  0.9,
  0.99,
  1.0,
];

/// Top, middle and bottom grabs — the three cases that must look different.
const _grabs = <double>[0.0, 0.25, 0.5, 0.75, 1.0];

const _pageSize = Size(300, 400);

PageCurlMesh _mesh({Size size = _pageSize, int columns = 24}) =>
    PageCurlMesh.forPage(pageSize: size, columns: columns);

CurlParameters _params({
  required double progress,
  double grabV = 0.5,
  int direction = 1,
  double droop = CurlParameters.defaultDroop,
}) =>
    CurlParameters.forGesture(
      progress: progress,
      grabV: grabV,
      direction: direction,
      droop: droop,
    );

void main() {
  const geometry = PageCurlGeometry();

  group('mesh topology', () {
    test('rows follow the page aspect ratio, not a square grid', () {
      final portrait = PageCurlMesh.forPage(
        pageSize: const Size(300, 400),
        columns: 32,
      );
      // 4:3 tall -> about a third more rows than columns.
      expect(portrait.rows, 43);
      expect(portrait.columns, 32);

      final square = PageCurlMesh.forPage(
        pageSize: const Size(400, 400),
        columns: 32,
      );
      expect(square.rows, 32);
    });

    test('vertex and triangle counts match the grid', () {
      final mesh = PageCurlMesh(
        columns: 4,
        rows: 3,
        pageSize: _pageSize,
      );
      expect(mesh.vertexCount, 5 * 4);
      expect(mesh.triangleCount, 4 * 3 * 2);
      expect(mesh.indices.length, mesh.triangleCount * 3);
      expect(mesh.positions.length, mesh.vertexCount * 2);
      expect(mesh.worldPositions.length, mesh.vertexCount * 3);
    });

    test('every index addresses a real vertex', () {
      final mesh = _mesh();
      for (final index in mesh.indices) {
        expect(index, lessThan(mesh.vertexCount));
      }
    });

    test('texture coordinates are in image pixel space, not 0..1', () {
      final mesh = PageCurlMesh(columns: 2, rows: 2, pageSize: _pageSize);
      mesh.updateTextureRegion(const Rect.fromLTWH(0, 0, 600, 800));
      // Bottom-right vertex maps to the far corner of the image.
      final last = mesh.vertexCount - 1;
      expect(mesh.textureCoordinates[last * 2], closeTo(600, 1e-6));
      expect(mesh.textureCoordinates[last * 2 + 1], closeTo(800, 1e-6));
    });

    test('mirroring reverses u but never v', () {
      final mesh = PageCurlMesh(columns: 2, rows: 2, pageSize: _pageSize);
      const region = Rect.fromLTWH(0, 0, 100, 200);
      mesh.updateTextureRegion(region, mirrorHorizontally: true);
      // Top-left vertex now samples the image's top-RIGHT.
      expect(mesh.textureCoordinates[0], closeTo(100, 1e-6));
      expect(mesh.textureCoordinates[1], closeTo(0, 1e-6));
      // Bottom-left vertex samples bottom-right: v is untouched.
      final bottomLeft = mesh.vertexIndex(0, 2);
      expect(mesh.textureCoordinates[bottomLeft * 2], closeTo(100, 1e-6));
      expect(mesh.textureCoordinates[bottomLeft * 2 + 1], closeTo(200, 1e-6));
    });
  });

  group('geometry invariants', () {
    test('no NaN or infinity anywhere in the parameter space', () {
      final mesh = _mesh();
      for (final progress in _progresses) {
        for (final grabV in _grabs) {
          for (final direction in [1, -1]) {
            for (final spread in [false, true]) {
              final params = _params(
                progress: progress,
                grabV: grabV,
                direction: direction,
              );
              geometry.deform(mesh, params, spineAtCentre: spread);
              expect(
                PageCurlGeometry.debugValidate(mesh, params),
                isNull,
                reason: 'progress=$progress grabV=$grabV dir=$direction '
                    'spread=$spread',
              );
              geometry.computeNormals(mesh);
              for (var i = 0; i < mesh.vertexCount * 3; i++) {
                expect(mesh.normals[i].isFinite, isTrue);
              }
            }
          }
        }
      }
    });

    test('progress 0 reproduces the flat page exactly', () {
      final mesh = _mesh();
      geometry.deform(mesh, _params(progress: 0));

      for (var row = 0; row <= mesh.rows; row++) {
        for (var col = 0; col <= mesh.columns; col++) {
          final i = mesh.vertexIndex(col, row);
          expect(
            mesh.worldPositions[i * 3],
            closeTo(col / mesh.columns * _pageSize.width, 1e-9),
          );
          expect(
            mesh.worldPositions[i * 3 + 1],
            closeTo(row / mesh.rows * _pageSize.height, 1e-9),
          );
          expect(mesh.worldPositions[i * 3 + 2], closeTo(0, 1e-9));
        }
      }
    });

    test('the spine never moves, at any progress or grab point', () {
      final mesh = _mesh();
      for (final progress in _progresses) {
        for (final grabV in _grabs) {
          geometry.deform(
            mesh,
            _params(progress: progress, grabV: grabV),
          );
          for (var row = 0; row <= mesh.rows; row++) {
            final i = mesh.vertexIndex(0, row);
            expect(
              mesh.worldPositions[i * 3],
              closeTo(0, 1e-9),
              reason: 'spine x moved at progress=$progress grabV=$grabV',
            );
            expect(
              mesh.worldPositions[i * 3 + 2],
              closeTo(0, 1e-9),
              reason: 'spine lifted at progress=$progress grabV=$grabV',
            );
          }
        }
      }
    });

    test('a backward turn mirrors a forward one about the page centre', () {
      final forward = _mesh();
      final backward = _mesh();
      const progress = 0.4;
      geometry.deform(
        forward,
        _params(progress: progress, grabV: 0.5, direction: 1),
      );
      geometry.deform(
        backward,
        _params(progress: progress, grabV: 0.5, direction: -1),
      );

      // The mesh buffers are Float32, so ~1e-7 relative precision over
      // page-sized magnitudes. 1e-3 logical pixels is far below anything
      // visible and still catches any real asymmetry.
      const tolerance = 1e-3;
      for (var i = 0; i < forward.vertexCount; i++) {
        // x mirrors about the page's vertical centre line; y and z match.
        expect(
          forward.worldPositions[i * 3],
          closeTo(_pageSize.width - backward.worldPositions[i * 3], tolerance),
        );
        expect(
          forward.worldPositions[i * 3 + 1],
          closeTo(backward.worldPositions[i * 3 + 1], tolerance),
        );
        expect(
          forward.worldPositions[i * 3 + 2],
          closeTo(backward.worldPositions[i * 3 + 2], tolerance),
        );
      }
    });
  });

  group('the surface is developable (paper, not rubber)', () {
    // The continuous surface is an exact isometry. What a mesh can measure is
    // that isometry sampled at its vertices, where a chord across a curved
    // strip is always slightly shorter than the arc it subtends. That error is
    // O(spacing^2) and shrinks with density -- which is the real test, and the
    // one a non-developable surface cannot pass at any density.
    const atProductionDensity = 2e-3;

    test('a centre grab does not stretch the page', () {
      final mesh = _mesh(columns: 32);
      for (final progress in _progresses) {
        geometry.deform(
          mesh,
          _params(progress: progress, grabV: 0.5, droop: 0),
        );
        expect(
          PageCurlGeometry.debugMaxIsometryError(mesh),
          lessThan(atProductionDensity),
          reason: 'cylinder stretched at progress=$progress',
        );
      }
    });

    test('a corner grab does not stretch it either — the cone is isometric',
        () {
      final mesh = _mesh(columns: 32);
      for (final grabV in _grabs) {
        for (final progress in [0.1, 0.25, 0.5, 0.75, 0.9]) {
          geometry.deform(
            mesh,
            _params(progress: progress, grabV: grabV, droop: 0),
          );
          expect(
            PageCurlGeometry.debugMaxIsometryError(mesh),
            lessThan(atProductionDensity),
            reason: 'cone stretched at grabV=$grabV progress=$progress',
          );
        }
      }
    });

    test('a landscape spread leaf does not stretch', () {
      for (final grabV in _grabs) {
        final mesh = _mesh(columns: 32);
        geometry.deform(
          mesh,
          _params(progress: 0.5, grabV: grabV, droop: 0),
          spineAtCentre: true,
        );
        expect(
          PageCurlGeometry.debugMaxIsometryError(mesh, spineAtCentre: true),
          lessThan(atProductionDensity),
          reason: 'spread leaf stretched at grabV=$grabV',
        );
      }
    });

    test(
      'the residual is discretization, not stretch: it quarters when the '
      'mesh density doubles',
      () {
        // This is the proof. A surface that genuinely stretches does so by a
        // fixed percentage no matter how finely it is sampled; only chord-vs-arc
        // error converges quadratically.
        double errorAt(int columns, double grabV) {
          final mesh = PageCurlMesh.forPage(
            pageSize: _pageSize,
            columns: columns,
            maxRows: 512,
          );
          geometry.deform(
            mesh,
            _params(progress: 0.5, grabV: grabV, droop: 0),
            spineAtCentre: true,
          );
          return PageCurlGeometry.debugMaxIsometryError(
            mesh,
            spineAtCentre: true,
          );
        }

        // The mesh buffers are Float32, so once the error approaches ~1e-5 at
        // page-sized magnitudes it is measuring rounding rather than geometry
        // and the ratio stops meaning anything. Only compare above that floor.
        const float32Floor = 5e-5;
        var comparisons = 0;

        for (final grabV in [0.0, 0.5, 1.0]) {
          for (final columns in [16, 32, 64]) {
            final coarse = errorAt(columns, grabV);
            final fine = errorAt(columns * 2, grabV);
            if (fine < float32Floor) continue;

            comparisons++;
            final ratio = coarse / fine;
            expect(
              ratio,
              inInclusiveRange(3.2, 4.8),
              reason: 'grabV=$grabV, $columns -> ${columns * 2} columns: '
                  'expected ~4x convergence, got ${ratio.toStringAsFixed(2)}x '
                  '($coarse -> $fine)',
            );
          }
        }

        expect(comparisons, greaterThanOrEqualTo(6),
            reason: 'the floor filter must not skip the whole test');
      },
    );
  });

  group('cone / cylinder family', () {
    test('a centre grab produces exactly zero conicity', () {
      expect(CurlParameters.resolveConicity(0.5), 0.0);
    });

    test('grabs above and below centre give opposite cone signs', () {
      final top = CurlParameters.resolveConicity(0.0);
      final bottom = CurlParameters.resolveConicity(1.0);
      expect(top, greaterThan(0));
      expect(bottom, lessThan(0));
      expect(top, closeTo(-bottom, 1e-12));
    });

    test('conicity is continuous through the cylinder', () {
      var previous = CurlParameters.resolveConicity(0.0);
      for (var i = 1; i <= 100; i++) {
        final next = CurlParameters.resolveConicity(i / 100);
        expect((next - previous).abs(), lessThan(0.05));
        previous = next;
      }
    });

    test('a centre grab wraps every row identically — a true cylinder', () {
      final params = _params(progress: 0.45, grabV: 0.5, droop: 0);
      final atTop =
          PageCurlGeometry.debugWrapAngleAtRow(params, _pageSize, 0.0);
      final atMiddle =
          PageCurlGeometry.debugWrapAngleAtRow(params, _pageSize, 0.5);
      final atBottom =
          PageCurlGeometry.debugWrapAngleAtRow(params, _pageSize, 1.0);

      expect(atTop, closeTo(atMiddle, 1e-12));
      expect(atBottom, closeTo(atMiddle, 1e-12));
    });

    test('a top grab curls the top of the page hardest', () {
      // Note this is about how far round the curl each row travels, not how
      // high it rises: a tighter curl has a smaller radius, so it wraps
      // further while lifting less. That is how a real corner fold behaves.
      final params = _params(progress: 0.45, grabV: 0.0, droop: 0);
      final wrap = [
        for (var i = 0; i <= 4; i++)
          PageCurlGeometry.debugWrapAngleAtRow(params, _pageSize, i / 4),
      ];

      for (var i = 1; i < wrap.length; i++) {
        expect(
          wrap[i],
          lessThan(wrap[i - 1]),
          reason: 'wrap angle must fall monotonically away from the held '
              'corner: $wrap',
        );
      }
      expect(wrap.first / wrap.last, greaterThan(1.2),
          reason: 'the cone should be clearly visible, not a token tilt');
    });

    test('a bottom grab is the exact mirror of a top grab', () {
      final top = _params(progress: 0.45, grabV: 0.0, droop: 0);
      final bottom = _params(progress: 0.45, grabV: 1.0, droop: 0);
      for (var i = 0; i <= 4; i++) {
        final v = i / 4;
        expect(
          PageCurlGeometry.debugWrapAngleAtRow(top, _pageSize, v),
          closeTo(
            PageCurlGeometry.debugWrapAngleAtRow(bottom, _pageSize, 1 - v),
            1e-12,
          ),
        );
      }
    });

    test('the fold runs diagonally for a corner grab, straight for a centre one',
        () {
      // The diagonal crease is a consequence of the cone, not of shearing the
      // rotation -- see the geometry class doc on why that distinction matters.
      double skew(double grabV) {
        final params = _params(progress: 0.5, grabV: grabV, droop: 0);
        final atTop =
            PageCurlGeometry.debugWrapAngleAtRow(params, _pageSize, 0.0);
        final atBottom =
            PageCurlGeometry.debugWrapAngleAtRow(params, _pageSize, 1.0);
        return (atTop - atBottom).abs();
      }

      expect(skew(0.5), closeTo(0, 1e-12));
      expect(skew(0.0), greaterThan(0.1));
      expect(skew(1.0), greaterThan(0.1));
    });
  });

  group('landing flat', () {
    test('curvature and its rate both vanish at each end', () {
      // bump = sin^2(pi t): value and slope are zero at t=0 and t=1, which is
      // what stops the sheet snapping flat in the last few percent.
      expect(PageCurlGeometry.bump(0), closeTo(0, 1e-12));
      expect(PageCurlGeometry.bump(1), closeTo(0, 1e-12));
      expect(PageCurlGeometry.bump(0.5), closeTo(1, 1e-12));

      const h = 1e-6;
      final slopeAtStart = (PageCurlGeometry.bump(h) - PageCurlGeometry.bump(0)) / h;
      final slopeAtEnd = (PageCurlGeometry.bump(1) - PageCurlGeometry.bump(1 - h)) / h;
      expect(slopeAtStart.abs(), lessThan(1e-4));
      expect(slopeAtEnd.abs(), lessThan(1e-4));
    });

    test('peak lift decays smoothly over the last 20% — no collapse', () {
      final mesh = _mesh();

      double peakLift(double progress) {
        geometry.deform(mesh, _params(progress: progress, droop: 0));
        var peak = 0.0;
        for (var i = 0; i < mesh.vertexCount; i++) {
          peak = math.max(peak, mesh.worldPositions[i * 3 + 2].abs());
        }
        return peak;
      }

      final samples = [
        for (var i = 80; i <= 100; i++) peakLift(i / 100),
      ];

      // Monotonically decreasing into the landing, with no single step
      // dominating -- a collapse shows up as one large jump.
      for (var i = 1; i < samples.length; i++) {
        expect(samples[i], lessThanOrEqualTo(samples[i - 1] + 1e-9));
      }
      final biggestStep = [
        for (var i = 1; i < samples.length; i++) samples[i - 1] - samples[i],
      ].reduce(math.max);
      final total = samples.first - samples.last;
      expect(
        biggestStep,
        lessThan(total * 0.35),
        reason: 'lift collapses in one step rather than easing out',
      );
    });
  });

  group('camera', () {
    test('the flat page maps pixel-exactly onto its own rectangle', () {
      final camera = PageCurlCamera.forPage(_pageSize);
      for (final point in [
        Offset.zero,
        Offset(_pageSize.width, 0),
        Offset(0, _pageSize.height),
        Offset(_pageSize.width, _pageSize.height),
        Offset(_pageSize.width / 2, _pageSize.height / 2),
      ]) {
        final projected = camera.project(point.dx, point.dy, 0);
        expect(projected.dx, closeTo(point.dx, 1e-9));
        expect(projected.dy, closeTo(point.dy, 1e-9));
      }
    });

    test('lifting toward the viewer enlarges', () {
      final camera = PageCurlCamera.forPage(_pageSize);
      expect(camera.scaleAt(0), closeTo(1.0, 1e-12));
      expect(camera.scaleAt(50), greaterThan(1.0));
      expect(camera.scaleAt(-50), lessThan(1.0));
    });

    test('a vertex at or past the eye is clamped, never infinite', () {
      final camera = PageCurlCamera.forPage(_pageSize);
      final projected = camera.project(10, 10, camera.eyeDistance * 10);
      expect(projected.dx.isFinite, isTrue);
      expect(projected.dy.isFinite, isTrue);
    });

    test('non-finite input is repaired rather than propagated', () {
      final camera = PageCurlCamera.forPage(_pageSize);
      final world = <double>[double.nan, 10, 0, 10, double.infinity, 0];
      final screen = List<double>.filled(4, 0);
      final bad = camera.projectBuffer(world, screen, 2);
      expect(bad, 2);
      expect(screen.every((v) => v.isFinite), isTrue);
    });

    test('projecting a whole buffer agrees with projecting point by point', () {
      final camera = PageCurlCamera.forPage(_pageSize);
      final mesh = _mesh(columns: 8);
      geometry.deform(mesh, _params(progress: 0.4, grabV: 0.2));
      final screen = List<double>.filled(mesh.vertexCount * 2, 0);
      final bad = camera.projectBuffer(
        mesh.worldPositions,
        screen,
        mesh.vertexCount,
      );
      expect(bad, 0);
      for (var i = 0; i < mesh.vertexCount; i++) {
        final expected = camera.project(
          mesh.worldPositions[i * 3],
          mesh.worldPositions[i * 3 + 1],
          mesh.worldPositions[i * 3 + 2],
        );
        expect(screen[i * 2], closeTo(expected.dx, 1e-9));
        expect(screen[i * 2 + 1], closeTo(expected.dy, 1e-9));
      }
    });
  });

  group('temporal smoothing', () {
    test('an ordinary drag step passes through with no lag at all', () {
      final smoother = CurlSmoother()..reset(_params(progress: 0.20));
      smoother.setTarget(_params(progress: 0.205));
      expect(smoother.advance(1 / 60), isTrue);
      // Below the pass-through threshold: followed exactly.
      expect(smoother.displayed.progress, closeTo(0.205, 1e-12));
    });

    test('a large jump is damped but still moves substantially', () {
      final smoother = CurlSmoother()..reset(_params(progress: 0.0));
      smoother.setTarget(_params(progress: 0.9));
      smoother.advance(1 / 60);
      expect(smoother.displayed.progress, greaterThan(0.1));
      expect(smoother.displayed.progress, lessThan(0.9));
    });

    test('it converges, and quickly', () {
      final smoother = CurlSmoother()..reset(_params(progress: 0.0));
      smoother.setTarget(_params(progress: 0.9));
      var frames = 0;
      while (!smoother.isSettled && frames < 100) {
        smoother.advance(1 / 60);
        frames++;
      }
      expect(smoother.isSettled, isTrue);
      expect(frames, lessThan(20), reason: 'smoothing must not read as lag');
    });

    test('behaviour is the same at 60, 90 and 120 Hz', () {
      double travelAfter(double seconds, double dt) {
        final smoother = CurlSmoother()..reset(_params(progress: 0.0));
        smoother.setTarget(_params(progress: 1.0));
        for (var elapsed = 0.0; elapsed < seconds; elapsed += dt) {
          smoother.advance(dt);
        }
        return smoother.displayed.progress;
      }

      final at60 = travelAfter(0.1, 1 / 60);
      final at90 = travelAfter(0.1, 1 / 90);
      final at120 = travelAfter(0.1, 1 / 120);
      expect(at90, closeTo(at60, 0.05));
      expect(at120, closeTo(at60, 0.05));
    });

    test('a direction reversal snaps rather than interpolating through zero',
        () {
      final smoother = CurlSmoother()
        ..reset(_params(progress: 0.5, direction: 1));
      final reversed = _params(progress: 0.5, direction: -1);
      smoother.setTarget(reversed);
      smoother.advance(1 / 60);
      expect(smoother.displayed.direction, -1);
      expect(smoother.displayed.progress, closeTo(0.5, 1e-12));
    });

    test('a settled smoother reports no repaint needed', () {
      final smoother = CurlSmoother()..reset(_params(progress: 0.3));
      smoother.setTarget(_params(progress: 0.3));
      expect(smoother.advance(1 / 60), isFalse);
    });
  });
}
