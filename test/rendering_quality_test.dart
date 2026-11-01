import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperflip/src/rendering/curl_parameters.dart';
import 'package:paperflip/src/rendering/page_curl_camera.dart';
import 'package:paperflip/src/rendering/page_curl_geometry.dart';
import 'package:paperflip/src/rendering/page_curl_mesh.dart';
import 'package:paperflip/src/rendering/page_curl_renderer.dart';

void main() {
  const pageSize = Size(400, 600);

  group('Page rendering quality improvements', () {
    test(
      'defaultColumns is 48 for high curvature smoothness without low-poly facets',
      () {
        expect(PageCurlMesh.defaultColumns, 48);
        final mesh = PageCurlMesh.forPage(pageSize: pageSize);
        expect(mesh.columns, 48);
        // 400x600 has aspect ratio 1.5, so 48 * 1.5 = 72 rows.
        expect(mesh.rows, 72);
        expect(mesh.vertexCount, 49 * 73);
      },
    );

    test(
      'PageCurlLighting provides smooth diffuse illumination without dark crease artifacts',
      () {
        const lighting = PageCurlLighting();
        expect(lighting.ambient, greaterThanOrEqualTo(0.70));
        expect(lighting.foldDarkening, lessThanOrEqualTo(0.05));

        final mesh = PageCurlMesh.forPage(pageSize: pageSize, columns: 24);
        const geometry = PageCurlGeometry();

        // Deform with corner fold:
        final params = CurlParameters.forGesture(
          progress: 0.35,
          grabV: 0.1,
          direction: 1,
          cornerEdge: -1,
          cornerLift: 0.1,
        );
        geometry
          ..deform(mesh, params)
          ..computeNormals(mesh);

        lighting.apply(mesh, params);

        // Verify that no vertex luminance drops into an unnatural dark crease:
        for (var i = 0; i < mesh.vertexCount; i++) {
          final color = mesh.colors[i];
          final alpha = (color >> 24) & 0xFF;
          final red = (color >> 16) & 0xFF;
          final green = (color >> 8) & 0xFF;
          final blue = color & 0xFF;

          expect(alpha, 0xFF, reason: 'lighting must preserve full opacity');
          expect(red, green);
          expect(green, blue);

          // Luminance must stay at or above 60% (~153/255), never collapsing to pitch black:
          expect(
            red,
            greaterThanOrEqualTo(150),
            reason: 'vertex $i luminance=$red is too dark (crease artifact)',
          );
        }
      },
    );

    test('Flat resting page receives pure white 0xFFFFFFFF lighting', () {
      const lighting = PageCurlLighting();
      final mesh = PageCurlMesh.forPage(pageSize: pageSize, columns: 16);
      mesh.resetToFlat();

      lighting.apply(mesh, CurlParameters.rest);

      for (var i = 0; i < mesh.vertexCount; i++) {
        expect(mesh.colors[i] & 0xFFFFFFFF, 0xFFFFFFFF);
      }
    });

    test(
      'Corner fold produces exact analytic unit normals without central-difference error',
      () {
        final mesh = PageCurlMesh.forPage(pageSize: pageSize, columns: 32);
        const geometry = PageCurlGeometry();

        final params = CurlParameters.forGesture(
          progress: 0.4,
          grabV: 0.9,
          direction: 1,
          cornerEdge: 1,
          cornerLift: 0.05,
        );

        geometry
          ..deform(mesh, params)
          ..computeNormals(mesh);

        final normals = mesh.normals;
        final world = mesh.worldPositions;

        for (var i = 0; i < mesh.vertexCount; i++) {
          final nx = normals[i * 3];
          final ny = normals[i * 3 + 1];
          final nz = normals[i * 3 + 2];
          final pz = world[i * 3 + 2];

          final len = math.sqrt(nx * nx + ny * ny + nz * nz);
          expect(
            len,
            closeTo(1.0, 1e-4),
            reason: 'normal $i must be unit length',
          );

          // On the flat sheet (pz == 0), the normal must point straight up toward the viewer:
          if (pz.abs() < 1e-6) {
            expect(nx, closeTo(0.0, 1e-6));
            expect(ny, closeTo(0.0, 1e-6));
            expect(nz, closeTo(-1.0, 1e-6));
          }
        }
      },
    );

    test('Corner shadow renders smoothly without throwing', () {
      const shadow = PageCurlShadow();
      final mesh = PageCurlMesh.forPage(pageSize: pageSize, columns: 24);
      final camera = PageCurlCamera.forPage(pageSize);
      const geometry = PageCurlGeometry();

      final params = CurlParameters.forGesture(
        progress: 0.3,
        grabV: 0.1,
        direction: 1,
        cornerEdge: -1,
        cornerLift: 0.1,
      );

      geometry
        ..deform(mesh, params)
        ..computeNormals(mesh);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Verify painting corner shadow produces valid canvas operations:
      expect(
        () => shadow.paint(canvas, mesh, params, camera: camera),
        returnsNormally,
      );

      final picture = recorder.endRecording();
      expect(picture, isNotNull);
      picture.dispose();
    });
  });
}
