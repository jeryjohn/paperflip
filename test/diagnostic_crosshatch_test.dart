import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperflip/src/capture/widget_page_rasterizer.dart';
import 'package:paperflip/src/pages/page_texture.dart';
import 'package:paperflip/src/rendering/curl_parameters.dart';
import 'package:paperflip/src/rendering/page_curl_camera.dart';
import 'package:paperflip/src/rendering/page_curl_mesh.dart';
import 'package:paperflip/src/rendering/page_curl_renderer.dart';
import 'package:paperflip/src/rendering/sheet_atlas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const logicalSize = Size(400, 600);
  const ivoryColor = Color(0xFFFBF0D9); // R: 251, G: 240, B: 217, A: 255
  // uint32 in little-endian rawRgba memory:
  const expectedIvoryU32 = 0xFFD9F0FB;

  group('Crosshatch Pipeline Diagnostic Stages A-D', () {
    testWidgets('Stage A & B & C & D: complete pipeline validation', (
      tester,
    ) async {
      final captureKey = GlobalKey();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: logicalSize.width,
              height: logicalSize.height,
              child: RepaintBoundary(
                key: captureKey,
                child: const ColoredBox(color: ivoryColor),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        // ─────────────────────────────────────────────────────────────────────
        // Stage A – Raw texture capture
        // ─────────────────────────────────────────────────────────────────────
        final rasterizer = WidgetPageRasterizer(pixelRatio: 2.0);
        final rawTexture = await rasterizer.capture(
          captureKey,
          logicalSize: logicalSize,
          textureKey: const PageTextureKey(
            sourceId: 'diag',
            pageId: 0,
            logicalSize: logicalSize,
            pixelRatio: 2.0,
          ),
        );

        expect(rawTexture, isNotNull);
        final rawImage = rawTexture!.image;
        expect(
          rawImage.width,
          800,
          reason: 'Stage A: Captured width must be 800 (400 * 2.0)',
        );
        expect(
          rawImage.height,
          1200,
          reason: 'Stage A: Captured height must be 1200 (600 * 2.0)',
        );

        final rawByteData = await rawImage.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(rawByteData, isNotNull);
        final rawPixels = rawByteData!.buffer.asUint32List();
        expect(rawPixels.length, 800 * 1200);

        var rawMismatches = 0;
        for (var i = 0; i < rawPixels.length; i++) {
          if (rawPixels[i] != expectedIvoryU32) {
            rawMismatches++;
          }
        }
        expect(
          rawMismatches,
          0,
          reason:
              'Stage A: Raw captured texture must be 100% uniform ivory with 0 pixel mismatches',
        );

        // ─────────────────────────────────────────────────────────────────────
        // Stage B – Direct image rendering baseline
        // ─────────────────────────────────────────────────────────────────────
        final recB = ui.PictureRecorder();
        final canvasB = Canvas(recB);
        // Contrasting red background:
        canvasB.drawRect(
          Rect.fromLTWH(0, 0, logicalSize.width, logicalSize.height),
          Paint()..color = const Color(0xFFFF0000),
        );
        canvasB.drawImageRect(
          rawImage,
          rawTexture.region,
          Rect.fromLTWH(0, 0, logicalSize.width, logicalSize.height),
          Paint()..filterQuality = FilterQuality.low,
        );
        final imgB = recB.endRecording().toImageSync(
          logicalSize.width.toInt(),
          logicalSize.height.toInt(),
        );
        final bytesB = await imgB.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(bytesB, isNotNull);
        final pixelsB = bytesB!.buffer.asUint32List();
        expect(pixelsB.length, 400 * 600);

        var directMismatches = 0;
        for (var i = 0; i < pixelsB.length; i++) {
          if (pixelsB[i] != expectedIvoryU32) {
            directMismatches++;
          }
        }
        expect(
          directMismatches,
          0,
          reason:
              'Stage B: Direct drawImageRect rendering must match expected ivory uniformly',
        );

        // ─────────────────────────────────────────────────────────────────────
        // Stage C – Flat mesh rendering (Single-face & Two-face)
        // ─────────────────────────────────────────────────────────────────────
        final mesh = PageCurlMesh.forPage(pageSize: logicalSize, columns: 48);
        final camera = PageCurlCamera.forPage(logicalSize);
        final renderer = PageCurlRenderer();

        // C1: Single-face atlas
        final singleAtlas = await SheetAtlas.pack(
          PageFaceSet(front: rawTexture.share(), back: null),
        );
        expect(singleAtlas.isSingleFace, isTrue);

        final recC1 = ui.PictureRecorder();
        final canvasC1 = Canvas(recC1);
        canvasC1.drawRect(
          Rect.fromLTWH(0, 0, logicalSize.width, logicalSize.height),
          Paint()..color = const Color(0xFFFF0000),
        );
        final okC1 = renderer.paint(
          canvasC1,
          mesh,
          CurlParameters.rest,
          singleAtlas,
          camera: camera,
        );
        expect(
          okC1,
          isTrue,
          reason:
              'Stage C1: renderer.paint must return true for single-face atlas',
        );

        final imgC1 = recC1.endRecording().toImageSync(
          logicalSize.width.toInt(),
          logicalSize.height.toInt(),
        );
        final bytesC1 = await imgC1.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(bytesC1, isNotNull);
        final pixelsC1 = bytesC1!.buffer.asUint32List();

        // Check interior pixels (inset 4px from paper perimeter stroke):
        var c1InteriorMismatches = 0;
        for (var y = 4; y < 596; y++) {
          for (var x = 4; x < 396; x++) {
            if (pixelsC1[y * 400 + x] != expectedIvoryU32) {
              c1InteriorMismatches++;
            }
          }
        }
        expect(
          c1InteriorMismatches,
          0,
          reason:
              'Stage C1: Single-face flat mesh interior must be 100% uniform with zero crosshatch seams',
        );

        // C2: Production-style two-face atlas
        final backRec = ui.PictureRecorder();
        final backCanvas = Canvas(backRec);
        backCanvas.drawRect(
          const Rect.fromLTWH(0, 0, 8, 8),
          Paint()..color = const Color(0xFFF0EEE8),
        );
        final backImg = backRec.endRecording().toImageSync(8, 8);
        final backTexture = PageTexture(
          image: backImg,
          logicalSize: logicalSize,
        );

        final twoFaceAtlas = await SheetAtlas.pack(
          PageFaceSet(front: rawTexture.share(), back: backTexture),
        );
        expect(twoFaceAtlas.isSingleFace, isFalse);
        expect(twoFaceAtlas.image.width, 1602);
        expect(twoFaceAtlas.image.height, 1200);

        final recC2 = ui.PictureRecorder();
        final canvasC2 = Canvas(recC2);
        canvasC2.drawRect(
          Rect.fromLTWH(0, 0, logicalSize.width, logicalSize.height),
          Paint()..color = const Color(0xFFFF0000),
        );
        final okC2 = renderer.paint(
          canvasC2,
          mesh,
          CurlParameters.rest,
          twoFaceAtlas,
          camera: camera,
        );
        expect(
          okC2,
          isTrue,
          reason:
              'Stage C2: renderer.paint must return true for two-face atlas',
        );

        final imgC2 = recC2.endRecording().toImageSync(
          logicalSize.width.toInt(),
          logicalSize.height.toInt(),
        );
        final bytesC2 = await imgC2.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(bytesC2, isNotNull);
        final pixelsC2 = bytesC2!.buffer.asUint32List();

        var c2InteriorMismatches = 0;
        for (var y = 4; y < 596; y++) {
          for (var x = 4; x < 396; x++) {
            if (pixelsC2[y * 400 + x] != expectedIvoryU32) {
              c2InteriorMismatches++;
            }
          }
        }
        expect(
          c2InteriorMismatches,
          0,
          reason:
              'Stage C2: Two-face flat mesh interior must be 100% uniform with zero crosshatch seams',
        );

        // ─────────────────────────────────────────────────────────────────────
        // Stage D – Active curl rendering (Spine curl & Corner fold)
        // ─────────────────────────────────────────────────────────────────────
        // D1: Spine curl (forward turn, progress 0.3)
        // In forward curl, the spine side (x: 10..100) is geometrically flat.
        const spineCurl = CurlParameters(
          progress: 0.3,
          grabV: 0.5,
          direction: 1,
        );
        final recD1 = ui.PictureRecorder();
        final canvasD1 = Canvas(recD1);
        final okD1 = renderer.paint(
          canvasD1,
          mesh,
          spineCurl,
          twoFaceAtlas,
          camera: camera,
        );
        expect(
          okD1,
          isTrue,
          reason: 'Stage D1: renderer.paint must succeed for spine curl',
        );

        final imgD1 = recD1.endRecording().toImageSync(400, 600);
        final bytesD1 = await imgD1.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(bytesD1, isNotNull);
        final pixelsD1 = bytesD1!.buffer.asUint32List();

        // In spine curl, the entire sheet arches/curls in 3D, so legitimate shading occurs.
        // We verify that adjacent rows at the same x in the spine curl have identical luminance (no crosshatch).
        var d1SeamDiscontinuities = 0;
        for (var y = 100; y < 499; y++) {
          for (var x = 10; x < 100; x++) {
            // Compare pixel with pixel directly below it:
            final pA = pixelsD1[y * 400 + x];
            final pB = pixelsD1[(y + 1) * 400 + x];
            if (pA != pB) {
              d1SeamDiscontinuities++;
            }
          }
        }
        expect(
          d1SeamDiscontinuities,
          0,
          reason:
              'Stage D1: Horizontal/diagonal crosshatch seams detected across cylindrical spine curl rows',
        );

        // D2: Corner fold (top-right corner curl, progress 0.35)
        // The bottom-left region (x: 50..150, y: 400..500) remains completely flat.
        final cornerCurl = CurlParameters.forGesture(
          progress: 0.35,
          grabV: 0.1,
          direction: 1,
          cornerEdge: -1,
          cornerLift: 0.1,
        );
        final recD2 = ui.PictureRecorder();
        final canvasD2 = Canvas(recD2);
        final okD2 = renderer.paint(
          canvasD2,
          mesh,
          cornerCurl,
          twoFaceAtlas,
          camera: camera,
        );
        expect(
          okD2,
          isTrue,
          reason: 'Stage D2: renderer.paint must succeed for corner fold',
        );

        final imgD2 = recD2.endRecording().toImageSync(400, 600);
        final bytesD2 = await imgD2.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(bytesD2, isNotNull);
        final pixelsD2 = bytesD2!.buffer.asUint32List();

        var d2FlatMismatches = 0;
        for (var y = 400; y < 500; y++) {
          for (var x = 50; x < 150; x++) {
            if (pixelsD2[y * 400 + x] != expectedIvoryU32) {
              d2FlatMismatches++;
            }
          }
        }
        expect(
          d2FlatMismatches,
          0,
          reason:
              'Stage D2: Flat stationary region during corner fold must have 0 crosshatch artifacts',
        );

        // Cleanup
        singleAtlas.dispose();
        twoFaceAtlas.dispose();
        backTexture.dispose();
        rawTexture.dispose();
        renderer.dispose();
      });
    });
  });
}
