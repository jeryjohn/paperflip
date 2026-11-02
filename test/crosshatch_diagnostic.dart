import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperflip/src/capture/widget_page_rasterizer.dart';
import 'package:paperflip/src/pages/page_texture.dart';
import 'package:paperflip/src/rendering/curl_parameters.dart';
import 'package:paperflip/src/rendering/page_curl_camera.dart';
import 'package:paperflip/src/rendering/page_curl_geometry.dart';
import 'package:paperflip/src/rendering/page_curl_mesh.dart';
import 'package:paperflip/src/rendering/page_curl_renderer.dart';
import 'package:paperflip/src/rendering/sheet_atlas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Crosshatch Diagnostic Tests A, B, C, D', (tester) async {
    const logicalSize = Size(400, 600);
    const pixelRatio = 2.0;
    final captureKey = GlobalKey();

    // ─────────────────────────────────────────────────────────────────────────
    // Test A – Raw texture
    // ─────────────────────────────────────────────────────────────────────────
    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: logicalSize.width,
          height: logicalSize.height,
          child: RepaintBoundary(
            key: captureKey,
            child: const ColoredBox(color: Colors.white),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rasterizer = WidgetPageRasterizer(pixelRatio: pixelRatio);
    final rawTexture = await rasterizer.capture(
      captureKey,
      logicalSize: logicalSize,
      textureKey: const PageTextureKey(
        sourceId: 'diag',
        pageId: 0,
        logicalSize: logicalSize,
        pixelRatio: pixelRatio,
      ),
    );

    expect(rawTexture, isNotNull);
    final rawImage = rawTexture!.image;
    print('Test A: Raw texture captured: ${rawImage.width}x${rawImage.height}');

    final rawByteData = await rawImage.toByteData(format: ui.ImageByteFormat.png);
    File('build/diag_test_a_raw.png').createSync(recursive: true);
    File('build/diag_test_a_raw.png').writeAsBytesSync(rawByteData!.buffer.asUint8List());

    final rawRgba = await rawImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    final rawPixels = rawRgba!.buffer.asUint32List();
    var nonWhiteRaw = 0;
    for (final px in rawPixels) {
      if (px != 0xFFFFFFFF) nonWhiteRaw++;
    }
    print('Test A Result: Non-white pixels in raw texture = $nonWhiteRaw out of ${rawPixels.length}');

    // ─────────────────────────────────────────────────────────────────────────
    // Test B – Flat rendering
    // ─────────────────────────────────────────────────────────────────────────
    final mesh = PageCurlMesh.forPage(pageSize: logicalSize, columns: 48);
    final camera = PageCurlCamera.forPage(logicalSize);
    final renderer = PageCurlRenderer();

    // Case B1: Single-face atlas
    final singleAtlas = SheetAtlas.fromImage(
      image: rawImage.clone(),
      frontRegion: rawTexture.region,
      backRegion: rawTexture.region,
      logicalSize: logicalSize,
      ownsImage: true,
    );

    // Case B2: Two-face atlas (like MeshPaperFlip prepares with back page)
    final backRecorder = ui.PictureRecorder();
    final backCanvas = Canvas(backRecorder);
    backCanvas.drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = Colors.white);
    final backImg = backRecorder.endRecording().toImageSync(8, 8);
    final backTexture = PageTexture(image: backImg, logicalSize: logicalSize);

    final twoFaceAtlas = await SheetAtlas.pack(
      PageFaceSet(front: rawTexture.share(), back: backTexture),
    );
    print('Test B: TwoFaceAtlas size: ${twoFaceAtlas.image.width}x${twoFaceAtlas.image.height}, front=${twoFaceAtlas.frontRegion}, back=${twoFaceAtlas.backRegion}');

    // Render Flat with Single-Face
    final recB1 = ui.PictureRecorder();
    final canvasB1 = Canvas(recB1);
    renderer.paint(canvasB1, mesh, CurlParameters.rest, singleAtlas, camera: camera);
    final imgB1 = recB1.endRecording().toImageSync(logicalSize.width.toInt(), logicalSize.height.toInt());
    final b1Rgba = await imgB1.toByteData(format: ui.ImageByteFormat.rawRgba);
    final b1Pixels = b1Rgba!.buffer.asUint32List();
    var b1NonWhite = 0;
    for (final px in b1Pixels) {
      if (px != 0xFFFFFFFF) b1NonWhite++;
    }
    print('Test B1 (SingleFace Flat): Non-white pixels = $b1NonWhite out of ${b1Pixels.length}');

    // Render Flat with Two-Face
    final recB2 = ui.PictureRecorder();
    final canvasB2 = Canvas(recB2);
    renderer.paint(canvasB2, mesh, CurlParameters.rest, twoFaceAtlas, camera: camera);
    final imgB2 = recB2.endRecording().toImageSync(logicalSize.width.toInt(), logicalSize.height.toInt());
    final b2Rgba = await imgB2.toByteData(format: ui.ImageByteFormat.rawRgba);
    final b2Pixels = b2Rgba!.buffer.asUint32List();
    var b2NonWhite = 0;
    for (final px in b2Pixels) {
      if (px != 0xFFFFFFFF) b2NonWhite++;
    }
    print('Test B2 (TwoFace Flat): Non-white pixels = $b2NonWhite out of ${b2Pixels.length}');

    // ─────────────────────────────────────────────────────────────────────────
    // Test C – Deformed rendering (Active curl)
    // ─────────────────────────────────────────────────────────────────────────
    final cornerCurl = CurlParameters.forGesture(
      progress: 0.35,
      grabV: 0.1,
      direction: 1,
      cornerEdge: -1,
      cornerLift: 0.1,
    );

    // Deformed with Two-Face atlas
    final recC = ui.PictureRecorder();
    final canvasC = Canvas(recC);
    // Draw over white background
    canvasC.drawRect(Offset.zero & logicalSize, Paint()..color = Colors.white);
    renderer.paint(canvasC, mesh, cornerCurl, twoFaceAtlas, camera: camera);
    final imgC = recC.endRecording().toImageSync(logicalSize.width.toInt(), logicalSize.height.toInt());
    final cByteData = await imgC.toByteData(format: ui.ImageByteFormat.png);
    File('build/diag_test_c_curl.png').writeAsBytesSync(cByteData!.buffer.asUint8List());

    final cRgba = await imgC.toByteData(format: ui.ImageByteFormat.rawRgba);
    final cPixels = cRgba!.buffer.asUint32List();
    print('Test C: Deformed corner curl rendered, dimensions=${imgC.width}x${imgC.height}');

    // Let's inspect the flat region of the deformed mesh:
    // For progress=0.35, cornerEdge=-1 (bottom-right or top-right? grabV=0.1 is top-right).
    // The bottom-left portion (x: 50..150, y: 400..500) of the page is completely flat!
    // Let's inspect pixels in that flat portion:
    var flatRegionVariations = 0;
    final flatPixel0 = cPixels[450 * logicalSize.width.toInt() + 100];
    for (var y = 400; y < 500; y++) {
      for (var x = 50; x < 150; x++) {
        final px = cPixels[y * logicalSize.width.toInt() + x];
        if (px != 0xFFFFFFFF) {
          flatRegionVariations++;
        }
      }
    }
    print('Test C Result: Non-white pixels in flat stationary region of deformed mesh = $flatRegionVariations out of 10000');

    // ─────────────────────────────────────────────────────────────────────────
    // Test D – Direct image rendering vs Mesh texture rendering
    // ─────────────────────────────────────────────────────────────────────────
    // Direct drawImageRect
    final recDDirect = ui.PictureRecorder();
    final canvasDDirect = Canvas(recDDirect);
    canvasDDirect.drawImageRect(
      rawImage,
      rawTexture.region,
      Offset.zero & logicalSize,
      Paint()..filterQuality = FilterQuality.low,
    );
    final imgDDirect = recDDirect.endRecording().toImageSync(logicalSize.width.toInt(), logicalSize.height.toInt());
    final dDirectRgba = await imgDDirect.toByteData(format: ui.ImageByteFormat.rawRgba);
    final dDirectPixels = dDirectRgba!.buffer.asUint32List();

    var diffDirectVsMesh = 0;
    for (var i = 0; i < dDirectPixels.length; i++) {
      if (dDirectPixels[i] != b2Pixels[i]) {
        diffDirectVsMesh++;
      }
    }
    print('Test D Result: Differences between direct drawImageRect and flat mesh = $diffDirectVsMesh out of ${dDirectPixels.length}');

    singleAtlas.dispose();
    twoFaceAtlas.dispose();
    backTexture.dispose();
    rawTexture.dispose();
    renderer.dispose();
  });
}
