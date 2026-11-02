import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperflip/src/capture/widget_page_rasterizer.dart';
import 'package:paperflip/src/rendering/curl_parameters.dart';
import 'package:paperflip/src/rendering/page_curl_camera.dart';
import 'package:paperflip/src/rendering/page_curl_mesh.dart';
import 'package:paperflip/src/rendering/page_curl_renderer.dart';
import 'package:paperflip/src/rendering/sheet_atlas.dart';
import 'package:paperflip/src/pages/page_texture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Diagnostic test: uniform page texture and mesh pipeline inspection', (tester) async {
    const logicalSize = Size(400, 600);
    const ivoryColor = Color(0xFFFBF0D9); // A: 255, R: 251, G: 240, B: 217

    final key = GlobalKey();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: logicalSize.width,
            height: logicalSize.height,
            child: RepaintBoundary(
              key: key,
              child: const ColoredBox(color: ivoryColor),
            ),
          ),
        ),
      ),
    );

    await tester.runAsync(() async {
      // 1. Raw page texture capture
      final rasterizer = WidgetPageRasterizer(pixelRatio: 2.0);
      final texture = await rasterizer.capture(key, logicalSize: logicalSize);
      expect(texture, isNotNull);
      final rawImage = texture!.image;

      final rawBytes = await rawImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(rawBytes, isNotNull);
      final rawU32 = rawBytes!.buffer.asUint32List();

      // Check pixel uniformity in raw captured texture
      final firstPixel = rawU32[0];
      var rawMismatches = 0;
      for (var i = 0; i < rawU32.length; i++) {
        if (rawU32[i] != firstPixel) {
          rawMismatches++;
        }
      }
      // ignore: avoid_print
      print('Stage 1 (Raw Texture): dimensions=${rawImage.width}x${rawImage.height}, total pixels=${rawU32.length}, mismatches=$rawMismatches');

      // 2. Stationary page rendered through the mesh pipeline
      print('Starting Stage 2: packing atlas with back face (as in MeshPaperFlip)...');
      final paperRecorder = ui.PictureRecorder();
      final paperCanvas = Canvas(paperRecorder);
      paperCanvas.drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = const Color(0xFFF0EEE8));
      final paperPic = paperRecorder.endRecording();
      final paperImg = paperPic.toImageSync(8, 8);
      paperPic.dispose();

      // Pack two-face atlas
      final packRecorder = ui.PictureRecorder();
      final packCanvas = Canvas(packRecorder);
      const gutter = 2.0;
      final cellW = rawImage.width.toDouble();
      final cellH = rawImage.height.toDouble();
      final totalW = (cellW * 2 + gutter).ceil();
      final totalH = cellH.ceil();
      final frontRegion = Rect.fromLTWH(0, 0, cellW, cellH);
      final backRegion = Rect.fromLTWH(cellW + gutter, 0, cellW, cellH);

      final packPaint = Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = false;

      packCanvas.drawImageRect(texture.image, texture.region, frontRegion, packPaint);
      packCanvas.drawImageRect(paperImg, Rect.fromLTWH(0, 0, 8, 8), backRegion, packPaint);
      final packPic = packRecorder.endRecording();
      final packedAtlasImg = packPic.toImageSync(totalW, totalH);
      packPic.dispose();

      final atlas = SheetAtlas.fromImage(
        image: packedAtlasImg,
        frontRegion: frontRegion,
        backRegion: backRegion,
        logicalSize: logicalSize,
        ownsImage: true,
      );

      print('Atlas packed. Creating mesh...');
      final mesh = PageCurlMesh.forPage(pageSize: logicalSize, columns: 48);
      final camera = PageCurlCamera.forPage(logicalSize);
      final renderer = PageCurlRenderer();

      // Paint flat state
      print('Recording flat paint...');
      final recorderFlat = ui.PictureRecorder();
      final canvasFlat = Canvas(recorderFlat);

      renderer.paint(
        canvasFlat,
        mesh,
        CurlParameters.rest,
        atlas,
        camera: camera,
      );
      print('renderer.paint completed. Ending recording...');

      final picFlat = recorderFlat.endRecording();
      print('Ending recording done. Calling toImageSync...');
      final imgFlat = picFlat.toImageSync(logicalSize.width.toInt(), logicalSize.height.toInt());
      print('toImageSync done. Calling toByteData...');
      final bytesFlat = await imgFlat.toByteData(format: ui.ImageByteFormat.rawRgba);
      print('toByteData done.');
      expect(bytesFlat, isNotNull);
      final flatU32 = bytesFlat!.buffer.asUint32List();

      // Analyze flat mesh render
      final flatMap = <int, int>{};
      for (var i = 0; i < flatU32.length; i++) {
        flatMap[flatU32[i]] = (flatMap[flatU32[i]] ?? 0) + 1;
      }
      // ignore: avoid_print
      print('Stage 2 (Stationary Mesh): distinct colors count=${flatMap.length}');
      for (final entry in flatMap.entries.take(10)) {
        final c = entry.key;
        final r = c & 0xFF;
        final g = (c >> 8) & 0xFF;
        final b = (c >> 16) & 0xFF;
        final a = (c >> 24) & 0xFF;
        // ignore: avoid_print
        print('  Color 0x${c.toRadixString(16)} (R:$r, G:$g, B:$b, A:$a): ${entry.value} pixels');
      }

      // 3. Page rendered during curl animation
      final recorderCurl = ui.PictureRecorder();
      final canvasCurl = Canvas(recorderCurl);

      const curlParams = CurlParameters(
        progress: 0.2,
        grabV: 0.5,
        direction: 1,
      );

      renderer.paint(
        canvasCurl,
        mesh,
        curlParams,
        atlas,
        camera: camera,
      );

      final picCurl = recorderCurl.endRecording();
      final imgCurl = picCurl.toImageSync(logicalSize.width.toInt(), logicalSize.height.toInt());
      final bytesCurl = await imgCurl.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(bytesCurl, isNotNull);
      final curlU32 = bytesCurl!.buffer.asUint32List();

      final width = logicalSize.width.toInt();
      final height = logicalSize.height.toInt();

      // Check a horizontal line of pixels across the flat/stationary region
      // In progress=0.2, the right side of the page (e.g. x from 300 to 380, y=300) is flat.
      print('Scanning horizontal line at y=300, x=300..350:');
      final lineVals = <int>[];
      for (var x = 300; x < 350; x++) {
        final pixel = curlU32[300 * width + x];
        lineVals.add((pixel >> 16) & 0xFF); // Red channel
      }
      print('Red values across x=300..349: $lineVals');

      // Check a 10x10 patch in the flat region
      print('10x10 patch at x=320..330, y=295..305:');
      for (var y = 295; y < 305; y++) {
        final row = <int>[];
        for (var x = 320; x < 330; x++) {
          row.add((curlU32[y * width + x] >> 16) & 0xFF);
        }
        print('y=$y: $row');
      }

      texture.dispose();
      atlas.dispose();
      renderer.dispose();
    });
  });
}
