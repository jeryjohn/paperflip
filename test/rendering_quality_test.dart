import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperflip/src/pages/page_texture.dart';
import 'package:paperflip/src/rendering/curl_parameters.dart';
import 'package:paperflip/src/rendering/page_curl_camera.dart';
import 'package:paperflip/src/rendering/page_curl_geometry.dart';
import 'package:paperflip/src/rendering/page_curl_mesh.dart';
import 'package:paperflip/src/rendering/page_curl_renderer.dart';
import 'package:paperflip/src/rendering/sheet_atlas.dart';

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
      'PageCurlLighting provides balanced 3D curvature shading and depth without dark crease artifacts',
      () {
        const lighting = PageCurlLighting();
        expect(lighting.ambient, inInclusiveRange(0.55, 0.65));
        expect(lighting.foldDarkening, inInclusiveRange(0.08, 0.15));

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

        // Verify that vertex luminance provides tangible 3D fold depth without pitch black crease:
        for (var i = 0; i < mesh.vertexCount; i++) {
          final color = mesh.colors[i];
          final alpha = (color >> 24) & 0xFF;
          final red = (color >> 16) & 0xFF;
          final green = (color >> 8) & 0xFF;
          final blue = color & 0xFF;

          expect(alpha, 0xFF, reason: 'lighting must preserve full opacity');
          expect(red, green);
          expect(green, blue);

          // Luminance must stay balanced (>= 120/255), preserving paper texture while showing depth:
          expect(
            red,
            greaterThanOrEqualTo(120),
            reason: 'vertex $i luminance=$red collapsed to pitch black',
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

    test('PageCurlShadow has balanced minimum opacity for tactile depth', () {
      const shadow = PageCurlShadow();
      expect(shadow.opacity, inInclusiveRange(0.35, 0.45));
    });

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

    test(
      'Stationary mesh renders uniform ivory texture without crosshatch / diagonal checkerboard seams',
      () async {
        final mesh = PageCurlMesh.forPage(pageSize: pageSize, columns: 48);
        final camera = PageCurlCamera.forPage(pageSize);
        final renderer = PageCurlRenderer();

        // 1. Create a genuine 800x1200 ivory texture (pixelRatio 2.0):
        final frontRec = ui.PictureRecorder();
        final frontCanvas = Canvas(frontRec);
        frontCanvas.drawRect(
          const Rect.fromLTWH(0, 0, 800, 1200),
          Paint()..color = const Color(0xFFFBF0D9),
        );
        final frontImg = frontRec.endRecording().toImageSync(800, 1200);
        final frontTexture = PageTexture(
          image: frontImg,
          logicalSize: pageSize,
        );

        // 2. Create back texture (8x8 white stock):
        final backRec = ui.PictureRecorder();
        final backCanvas = Canvas(backRec);
        backCanvas.drawRect(
          const Rect.fromLTWH(0, 0, 8, 8),
          Paint()..color = const Color(0xFFFFFFFF),
        );
        final backImg = backRec.endRecording().toImageSync(8, 8);
        final backTexture = PageTexture(image: backImg, logicalSize: pageSize);

        // 3. Pack using the production SheetAtlas.pack:
        final atlas = await SheetAtlas.pack(
          PageFaceSet(front: frontTexture, back: backTexture),
        );

        expect(atlas.isSingleFace, isFalse);
        expect(atlas.image.width, 1602);
        expect(atlas.image.height, 1200);
        expect(atlas.frontRegion, const Rect.fromLTWH(0, 0, 800, 1200));
        expect(atlas.backRegion, const Rect.fromLTWH(802, 0, 800, 1200));

        // 4. Fill contrasting red background so a transparent/empty draw fails:
        final renderRec = ui.PictureRecorder();
        final renderCanvas = Canvas(renderRec);
        renderCanvas.drawRect(
          const Rect.fromLTWH(0, 0, 400, 600),
          Paint()..color = const Color(0xFFFF0000), // Red background
        );

        // 5. Render stationary flat mesh:
        final ok = renderer.paint(
          renderCanvas,
          mesh,
          CurlParameters.rest,
          atlas,
          camera: camera,
        );
        expect(
          ok,
          isTrue,
          reason: 'renderer.paint must return true for valid atlas',
        );

        final renderedImg = renderRec.endRecording().toImageSync(400, 600);
        final byteData = await renderedImg.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(byteData, isNotNull);
        final pixels = byteData!.buffer.asUint32List();

        // 6. Target ivory color in RGBA: R:251, G:240, B:217, A:255 (0xFFD9F0FB in little-endian uint32)
        // Check interior of the page (inset by 4 pixels to separate from perimeter stroke):
        const expectedColor = 0xFFD9F0FB;
        var interiorMismatches = 0;
        const width = 400;
        const height = 600;

        for (var y = 4; y < height - 4; y++) {
          for (var x = 4; x < width - 4; x++) {
            final px = pixels[y * width + x];
            if (px != expectedColor) {
              interiorMismatches++;
            }
          }
        }

        expect(
          interiorMismatches,
          0,
          reason:
              'Crosshatch seam artifact or non-uniform pixels detected in page interior',
        );

        frontTexture.dispose();
        backTexture.dispose();
        atlas.dispose();
        renderer.dispose();
      },
    );
  });
}
