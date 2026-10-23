import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:paperflip/paperflip.dart';
import 'package:paperflip/src/capture/widget_page_rasterizer.dart';
import 'package:paperflip/src/pages/page_texture.dart';
import 'package:paperflip/src/rendering/curl_parameters.dart';
import 'package:paperflip/src/rendering/flip_scene.dart';
import 'package:paperflip/src/rendering/page_curl_geometry.dart';
import 'package:paperflip/src/rendering/page_curl_mesh.dart';
import 'package:paperflip/src/rendering/page_curl_renderer.dart';
import 'package:paperflip/src/rendering/sheet_atlas.dart';

Future<ui.Image> _createTestImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 10, 10),
    Paint()..color = const Color(0xFF00FF00),
  );
  final picture = recorder.endRecording();
  return picture.toImage(10, 10);
}

Widget _book({
  PaperFlipController? controller,
  int pageCount = 8,
  int initialPage = 0,
  Size size = const Size(300, 400),
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: MeshPaperFlip(
            pageCount: pageCount,
            initialPage: initialPage,
            controller: controller,
            pageBuilder: (context, index, constraints) => ColoredBox(
              color: index.isEven ? Colors.white : Colors.amber,
              child: Center(child: Text('Page ${index + 1}')),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the current page as a live widget at rest', (
    tester,
  ) async {
    await tester.pumpWidget(_book());
    await tester.pumpAndSettle();
    // The live page and the capture host both mount page 1.
    expect(find.text('Page 1'), findsWidgets);
  });

  testWidgets('a drag turns the page', (tester) async {
    final controller = PaperFlipController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_book(controller: controller));
    await tester.pumpAndSettle();
    expect(controller.currentPage, 0);

    // Drag left, well past the commit threshold.
    await tester.drag(find.byType(MeshPaperFlip), const Offset(-260, 0));
    await tester.pumpAndSettle();

    expect(controller.currentPage, 1);
  });

  testWidgets('a short drag cancels back to the same page', (tester) async {
    final controller = PaperFlipController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_book(controller: controller));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MeshPaperFlip)),
    );
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.currentPage, 0);
  });

  testWidgets('a drag never leaves the sheet resting mid-turn', (tester) async {
    final controller = PaperFlipController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_book(controller: controller));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MeshPaperFlip)),
    );
    await gesture.moveBy(const Offset(-150, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.isAnimating, isFalse);
  });

  testWidgets('the controller flips programmatically', (tester) async {
    final controller = PaperFlipController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_book(controller: controller));
    await tester.pumpAndSettle();

    controller.flipNext();
    await tester.pumpAndSettle();
    expect(controller.currentPage, 1);

    controller.flipPrev();
    await tester.pumpAndSettle();
    expect(controller.currentPage, 0);
  });

  testWidgets('repeated flips stack rather than collapsing', (tester) async {
    final controller = PaperFlipController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_book(controller: controller));
    await tester.pumpAndSettle();

    controller.flipNext();
    controller.flipNext();
    controller.flipNext();
    await tester.pumpAndSettle();

    expect(controller.currentPage, 3);
  });

  testWidgets('goToPage resolves and lands on the right page', (tester) async {
    final controller = PaperFlipController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_book(controller: controller));
    await tester.pumpAndSettle();

    var done = false;
    // Deliberately not awaited: if the journey future never resolves the test
    // must fail on the flag, not hang forever.
    unawaited(controller.goToPage(5).then((_) => done = true));
    await tester.pumpAndSettle();

    expect(controller.currentPage, 5);
    expect(done, isTrue);
  });

  testWidgets('it does not flip past the ends', (tester) async {
    final controller = PaperFlipController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_book(controller: controller, pageCount: 2));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(MeshPaperFlip), const Offset(260, 0));
    await tester.pumpAndSettle();
    expect(controller.currentPage, 0);

    await tester.drag(find.byType(MeshPaperFlip), const Offset(-260, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(MeshPaperFlip), const Offset(-260, 0));
    await tester.pumpAndSettle();
    expect(controller.currentPage, 1);
  });

  testWidgets('tearing down mid-flip does not throw', (tester) async {
    final controller = PaperFlipController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_book(controller: controller));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MeshPaperFlip)),
    );
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump(const Duration(milliseconds: 16));

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a resize does not throw', (tester) async {
    await tester.pumpWidget(_book(size: const Size(300, 400)));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_book(size: const Size(420, 300)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('forward and backward flips', () {
    testWidgets('a forward swipe advances to next page', (tester) async {
      final controller = PaperFlipController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_book(controller: controller));
      await tester.pumpAndSettle();
      expect(controller.currentPage, 0);

      await tester.drag(find.byType(MeshPaperFlip), const Offset(-260, 0));
      await tester.pumpAndSettle();
      expect(controller.currentPage, 1);
    });

    testWidgets('a backward swipe from page > 0 returns to previous page', (
      tester,
    ) async {
      final controller = PaperFlipController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_book(controller: controller));
      await tester.pumpAndSettle();

      // Go to page 2 first.
      await controller.goToPage(2, animate: false);
      await tester.pumpAndSettle();
      expect(controller.currentPage, 2);

      // Drag right to flip backward.
      await tester.drag(find.byType(MeshPaperFlip), const Offset(260, 0));
      await tester.pumpAndSettle();
      expect(controller.currentPage, 1);
    });
  });

  group('partial-drag cancellation', () {
    testWidgets('a partial forward drag cancels back to current page', (
      tester,
    ) async {
      final controller = PaperFlipController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_book(controller: controller));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(MeshPaperFlip)),
      );
      // Move only slightly left (below commit threshold).
      await gesture.moveBy(const Offset(-25, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(controller.currentPage, 0);
      expect(controller.isAnimating, isFalse);
    });

    testWidgets('a partial backward drag cancels back to current page', (
      tester,
    ) async {
      final controller = PaperFlipController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_book(controller: controller));
      await tester.pumpAndSettle();

      await controller.goToPage(2, animate: false);
      await tester.pumpAndSettle();
      expect(controller.currentPage, 2);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(MeshPaperFlip)),
      );
      // Move only slightly right (below commit threshold).
      await gesture.moveBy(const Offset(25, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(controller.currentPage, 2);
      expect(controller.isAnimating, isFalse);
    });
  });

  group('page-transition and role continuity', () {
    test('SheetRoles maintains consistent layering forward and backward', () {
      final forwardRoles = SheetRoles.forTurn(currentPage: 2, forward: true);
      expect(forwardRoles.turningFront, 2);
      expect(forwardRoles.revealed, 3);
      expect(forwardRoles.destination, 3);
      expect(forwardRoles.isForward, isTrue);

      final backwardRoles = SheetRoles.forTurn(currentPage: 2, forward: false);
      expect(backwardRoles.turningFront, 2);
      expect(backwardRoles.revealed, 1);
      expect(backwardRoles.destination, 1);
      expect(backwardRoles.isBackward, isTrue);
    });

    test(
      'PageCurlRenderer direction-aware face and UV selection prevents mirrored text',
      () {
        // Forward turn: never mirror horizontally
        expect(
          PageCurlRenderer.resolveMirrorHorizontally(
            direction: 1,
            showBack: false,
          ),
          isFalse,
        );
        expect(
          PageCurlRenderer.resolveMirrorHorizontally(
            direction: 1,
            showBack: true,
          ),
          isFalse,
        );

        // Backward turn: mirror UVs along U so reading order matches physical screen left-to-right
        expect(
          PageCurlRenderer.resolveMirrorHorizontally(
            direction: -1,
            showBack: false,
          ),
          isTrue,
        );
        expect(
          PageCurlRenderer.resolveMirrorHorizontally(
            direction: -1,
            showBack: true,
          ),
          isTrue,
        );

        // Face selection transitions at 0.5 for two-face atlases
        expect(
          PageCurlRenderer.resolveShowBack(
            isSingleFace: false,
            progress: 0.3,
            direction: 1,
          ),
          isFalse,
        );
        expect(
          PageCurlRenderer.resolveShowBack(
            isSingleFace: false,
            progress: 0.7,
            direction: 1,
          ),
          isTrue,
        );
        expect(
          PageCurlRenderer.resolveShowBack(
            isSingleFace: false,
            progress: 0.3,
            direction: -1,
          ),
          isFalse,
        );
        expect(
          PageCurlRenderer.resolveShowBack(
            isSingleFace: false,
            progress: 0.7,
            direction: -1,
          ),
          isTrue,
        );

        // Single-face atlases always show front face
        expect(
          PageCurlRenderer.resolveShowBack(
            isSingleFace: true,
            progress: 0.9,
            direction: 1,
          ),
          isFalse,
        );
      },
    );

    test('UV mapping keeps text orientation matching screen coordinates', () {
      final mesh = PageCurlMesh.forPage(
        pageSize: const Size(300, 400),
        columns: 24,
      );
      const region = Rect.fromLTWH(0, 0, 600, 800);

      // Forward (direction >= 0): mirrorHorizontally is false.
      // col = 0 (screen left) -> textureCoordinates[x] is region.left
      // col = cols (screen right) -> textureCoordinates[x] is region.right
      mesh.updateTextureRegion(region, mirrorHorizontally: false);
      final firstVertexTexXForward = mesh.textureCoordinates[0];
      final lastColVertexTexXForward =
          mesh.textureCoordinates[mesh.columns * 2];
      expect(firstVertexTexXForward, closeTo(region.left, 0.1));
      expect(lastColVertexTexXForward, closeTo(region.right, 0.1));

      // Backward (direction < 0): mirrorHorizontally is true.
      // In backward geometry, col = 0 is at screen right (x = w), and col = cols is at screen left (x = 0).
      // With mirrorHorizontally: true:
      // col = 0 (screen right) -> textureCoordinates[x] is region.right
      // col = cols (screen left) -> textureCoordinates[x] is region.left
      mesh.updateTextureRegion(region, mirrorHorizontally: true);
      final firstVertexTexXBackward = mesh.textureCoordinates[0];
      final lastColVertexTexXBackward =
          mesh.textureCoordinates[mesh.columns * 2];
      expect(firstVertexTexXBackward, closeTo(region.right, 0.1));
      expect(lastColVertexTexXBackward, closeTo(region.left, 0.1));
    });

    testWidgets(
      'backward and forward page navigation sequence (0 -> 1 -> 2 -> 1 -> 0)',
      (tester) async {
        final controller = PaperFlipController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(_book(controller: controller, pageCount: 4));
        await tester.pumpAndSettle();
        expect(controller.currentPage, 0);

        // Forward: 0 -> 1
        controller.flipNext();
        await tester.pumpAndSettle();
        expect(controller.currentPage, 1);

        // Forward: 1 -> 2
        controller.flipNext();
        await tester.pumpAndSettle();
        expect(controller.currentPage, 2);

        // Backward: 2 -> 1
        controller.flipPrev();
        await tester.pumpAndSettle();
        expect(controller.currentPage, 1);

        // Backward: 1 -> 0
        controller.flipPrev();
        await tester.pumpAndSettle();
        expect(controller.currentPage, 0);
      },
    );

    test(
      'CurlParameters and geometry smoothly transition across 0.5 midpoint',
      () {
        const geometry = PageCurlGeometry();
        final mesh = PageCurlMesh.forPage(
          pageSize: const Size(300, 400),
          columns: 24,
        );

        // Sample progress from 0.0 to 1.0 across the 0.5 midpoint.
        double? prevPeakLift;
        for (var p = 0.0; p <= 1.0; p += 0.02) {
          final params = CurlParameters.forGesture(
            progress: p,
            grabV: 0.5,
            direction: 1,
          );

          geometry.deform(mesh, params);

          // Every vertex must stay finite.
          for (var i = 0; i < mesh.vertexCount * 3; i++) {
            expect(
              mesh.worldPositions[i].isFinite,
              isTrue,
              reason: 'non-finite vertex at progress $p',
            );
          }

          // Lift must be non-negative and transition smoothly without sudden jumps.
          final peakLift = PageCurlLighting.peakLift(mesh);
          expect(peakLift, greaterThanOrEqualTo(0.0));
          if (prevPeakLift != null) {
            final diff = (peakLift - prevPeakLift).abs();
            expect(
              diff,
              lessThan(40.0),
              reason: 'sudden jump in peak lift ($diff) around progress $p',
            );
          }
          prevPeakLift = peakLift;
        }
      },
    );

    testWidgets('PaperFlip.custom renders using MeshPaperFlip', (tester) async {
      final controller = PaperFlipController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaperFlip.custom(
              pageCount: 5,
              controller: controller,
              pageBuilder: (context, index, constraints) =>
                  Center(child: Text('Custom Page $index')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MeshPaperFlip), findsOneWidget);
      expect(find.text('Custom Page 0'), findsWidgets);

      controller.flipNext();
      await tester.pumpAndSettle();
      expect(controller.currentPage, 1);
      expect(find.text('Custom Page 1'), findsWidgets);
    });

    group('button and programmatic navigation animation pipeline', () {
      testWidgets('a button turn runs for FlipSettings.duration, not a snap', (
        tester,
      ) async {
        final controller = PaperFlipController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _book(controller: controller, pageCount: 5, initialPage: 1),
        );
        await tester.pumpAndSettle();

        final state = tester.state<MeshPaperFlipState>(
          find.byType(MeshPaperFlip),
        );

        controller.flipNext();
        await tester.pump(); // turn set up; clock starts after this frame
        await tester.pump(const Duration(milliseconds: 16));

        // Default duration is 600 ms. A spring from rest was already past
        // half-way at ~110 ms, which is what read as an instant flip.
        await tester.pump(const Duration(milliseconds: 150));
        expect(controller.isAnimating, isTrue);
        expect(state.debugScene.curl.progress, lessThan(0.5));
        expect(controller.currentPage, 1);

        await tester.pump(const Duration(milliseconds: 300));
        expect(controller.isAnimating, isTrue);
        expect(state.debugScene.curl.progress, greaterThan(0.05));

        await tester.pumpAndSettle();
        expect(controller.currentPage, 2);
      });

      testWidgets('a parent rebuild with a new pageBuilder closure does not '
          'cancel a turn', (tester) async {
        final controller = PaperFlipController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _book(controller: controller, pageCount: 5, initialPage: 1),
        );
        await tester.pumpAndSettle();

        controller.flipNext();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Same widget, fresh inline closure — what a parent setState does.
        await tester.pumpWidget(
          _book(controller: controller, pageCount: 5, initialPage: 1),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(controller.isAnimating, isTrue);

        await tester.pumpAndSettle();
        expect(controller.currentPage, 2);
      });

      testWidgets(
        'Next button animates progress continuously while current page remains stable',
        (tester) async {
          final controller = PaperFlipController();
          addTearDown(controller.dispose);

          await tester.pumpWidget(
            _book(controller: controller, pageCount: 5, initialPage: 2),
          );
          await tester.pumpAndSettle();
          expect(controller.currentPage, 2);

          // Press Next button
          controller.flipNext();
          await tester.pump();

          expect(controller.isAnimating, isTrue);
          expect(
            controller.currentPage,
            2,
            reason: 'Current page must remain 2 during turn animation',
          );

          final state = tester.state<MeshPaperFlipState>(
            find.byType(MeshPaperFlip),
          );
          final roles = state.debugRoles;
          expect(roles, isNotNull);
          expect(roles!.turningFront, 2);
          expect(roles.revealed, 3);
          expect(roles.direction, 1);

          // Pump intermediate frames and verify continuous progress updates
          final progressValues = <double>[];
          for (var i = 0; i < 15; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            if (!controller.isAnimating) break;
            expect(
              controller.currentPage,
              2,
              reason: 'Page index must not change before animation completes',
            );
            final scene = state.debugScene;
            expect(scene.active, isTrue);
            progressValues.add(scene.curl.progress);
          }

          expect(progressValues.isNotEmpty, isTrue);
          expect(progressValues.first, greaterThanOrEqualTo(0.0));
          expect(progressValues.last, greaterThan(progressValues.first));

          await tester.pumpAndSettle();
          expect(controller.isAnimating, isFalse);
          expect(
            controller.currentPage,
            3,
            reason: 'Destination page committed only after animation completes',
          );
        },
      );

      testWidgets(
        'Previous button animates backward turn with correct roles and orientation',
        (tester) async {
          final controller = PaperFlipController();
          addTearDown(controller.dispose);

          await tester.pumpWidget(
            _book(controller: controller, pageCount: 5, initialPage: 2),
          );
          await tester.pumpAndSettle();
          expect(controller.currentPage, 2);

          // Press Previous button
          controller.flipPrev();
          await tester.pump();

          expect(controller.isAnimating, isTrue);
          expect(
            controller.currentPage,
            2,
            reason: 'Current page must remain 2 during turn animation',
          );

          final state = tester.state<MeshPaperFlipState>(
            find.byType(MeshPaperFlip),
          );
          final roles = state.debugRoles;
          expect(roles, isNotNull);
          expect(roles!.turningFront, 2);
          expect(roles.revealed, 1);
          expect(roles.direction, -1);

          // Pump intermediate frames and verify continuous progress updates
          final progressValues = <double>[];
          for (var i = 0; i < 15; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            if (!controller.isAnimating) break;
            expect(
              controller.currentPage,
              2,
              reason: 'Page index must not change before animation completes',
            );
            final scene = state.debugScene;
            expect(scene.active, isTrue);
            progressValues.add(scene.curl.progress);
          }

          expect(progressValues.isNotEmpty, isTrue);
          expect(progressValues.first, greaterThanOrEqualTo(0.0));
          expect(progressValues.last, greaterThan(progressValues.first));

          await tester.pumpAndSettle();
          expect(controller.isAnimating, isFalse);
          expect(
            controller.currentPage,
            1,
            reason: 'Destination page committed only after animation completes',
          );
        },
      );

      testWidgets(
        'backward programmatic turn maintains unmirrored geometry and direction at progress 0.0',
        (tester) async {
          final controller = PaperFlipController();
          addTearDown(controller.dispose);

          await tester.pumpWidget(
            _book(controller: controller, pageCount: 5, initialPage: 2),
          );
          await tester.pumpAndSettle();

          // Trigger backward flip
          controller.flipPrev();
          // First frame: intent consumed, roles resolved, initial curl set to progress 0.0
          await tester.pump();

          final state = tester.state<MeshPaperFlipState>(
            find.byType(MeshPaperFlip),
          );
          final scene = state.debugScene;
          expect(scene.active, isTrue);
          expect(scene.curl.direction, -1);
          expect(scene.curl.progress, 0.0);

          // Verify that at progress 0.0 for a backward turn, the mesh is positioned
          // continuously with the curl deformation (spine at width, free edge at 0).
          final mesh = PageCurlMesh(
            columns: 4,
            rows: 4,
            pageSize: const Size(100, 200),
          );
          const geometry = PageCurlGeometry();
          geometry.deform(mesh, scene.curl);

          final xSpine = mesh.worldPositions[0]; // col=0
          final xFreeEdge = mesh.worldPositions[mesh.columns * 3]; // col=cols
          expect(xSpine, closeTo(100.0, 1e-4));
          expect(xFreeEdge, closeTo(0.0, 1e-4));

          await tester.pumpAndSettle();
          expect(controller.currentPage, 1);
        },
      );

      testWidgets('first page + Previous does not navigate or animate', (
        tester,
      ) async {
        final controller = PaperFlipController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _book(controller: controller, pageCount: 5, initialPage: 0),
        );
        await tester.pumpAndSettle();
        expect(controller.currentPage, 0);

        controller.flipPrev();
        await tester.pump();

        expect(controller.isAnimating, isFalse);
        expect(controller.currentPage, 0);

        await tester.pumpAndSettle();
        expect(controller.currentPage, 0);
      });

      testWidgets('last page + Next does not navigate or animate', (
        tester,
      ) async {
        final controller = PaperFlipController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _book(controller: controller, pageCount: 5, initialPage: 4),
        );
        await tester.pumpAndSettle();
        expect(controller.currentPage, 4);

        controller.flipNext();
        await tester.pump();

        expect(controller.isAnimating, isFalse);
        expect(controller.currentPage, 4);

        await tester.pumpAndSettle();
        expect(controller.currentPage, 4);
      });

      testWidgets('repeated button presses queue and do not corrupt state', (
        tester,
      ) async {
        final controller = PaperFlipController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _book(controller: controller, pageCount: 5, initialPage: 0),
        );
        await tester.pumpAndSettle();

        controller.flipNext();
        await tester.pump(const Duration(milliseconds: 30));
        // Rapid press while animating
        controller.flipNext();

        await tester.pumpAndSettle();
        expect(controller.currentPage, 2);
        expect(controller.isAnimating, isFalse);
      });
    });

    group('lifecycle and controller synchronization', () {
      testWidgets('works without a controller', (tester) async {
        await tester.pumpWidget(_book());
        await tester.pumpAndSettle();
        expect(find.text('Page 1'), findsWidgets);
      });

      testWidgets('clamps an out-of-range initialPage', (tester) async {
        await tester.pumpWidget(_book(pageCount: 3, initialPage: 42));
        await tester.pumpAndSettle();
        expect(find.text('Page 3'), findsWidgets);
      });

      testWidgets('disposing the widget leaves the controller usable', (
        tester,
      ) async {
        final controller = PaperFlipController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(_book(controller: controller));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        // Must not throw after the widget is gone.
        controller.flipNext();
        expect(controller.currentPage, 0);
      });

      testWidgets('swapping the controller re-attaches', (tester) async {
        final first = PaperFlipController();
        final second = PaperFlipController();
        addTearDown(first.dispose);
        addTearDown(second.dispose);

        await tester.pumpWidget(_book(controller: first, pageCount: 6));
        await tester.pumpAndSettle();
        expect(first.pageCount, 6);

        await tester.pumpWidget(_book(controller: second, pageCount: 6));
        await tester.pumpAndSettle();
        expect(second.pageCount, 6);

        second.flipNext();
        await tester.pumpAndSettle();
        expect(second.currentPage, 1);
      });

      testWidgets('a growing pageCount reaches the controller', (tester) async {
        final controller = PaperFlipController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(_book(controller: controller, pageCount: 5));
        await tester.pumpAndSettle();
        expect(controller.pageCount, 5);

        // An EPUB re-paginating grows the count without changing the book.
        await tester.pumpWidget(_book(controller: controller, pageCount: 400));
        await tester.pumpAndSettle();
        expect(controller.pageCount, 400);

        await controller.goToPage(380, animate: false);
        await tester.pumpAndSettle();
        expect(controller.currentPage, 380);
      });

      testWidgets('a shrinking pageCount clamps the current page', (
        tester,
      ) async {
        final controller = PaperFlipController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _book(controller: controller, pageCount: 10, initialPage: 8),
        );
        await tester.pumpAndSettle();
        expect(controller.currentPage, 8);

        await tester.pumpWidget(
          _book(controller: controller, pageCount: 4, initialPage: 8),
        );
        await tester.pumpAndSettle();

        expect(controller.pageCount, 4);
        expect(controller.currentPage, lessThan(4));
      });

      testWidgets('shows page indicator on PaperFlip.custom when enabled', (
        tester,
      ) async {
        final controller = PaperFlipController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PaperFlip.custom(
                pageCount: 5,
                controller: controller,
                showPageIndicator: true,
                pageBuilder: (context, index, constraints) => ColoredBox(
                  color: Colors.white,
                  child: Center(child: Text('Page ${index + 1}')),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('1 / 5'), findsOneWidget);
        controller.flipNext();
        await tester.pumpAndSettle();
        expect(find.text('2 / 5'), findsOneWidget);
      });
    });

    group('PageCaptureGuard & async page readiness', () {
      testWidgets('delays texture capture until PageCaptureGuard is ready', (
        tester,
      ) async {
        final controller = PaperFlipController();
        addTearDown(controller.dispose);

        final readyNotifier = ValueNotifier<bool>(false);
        addTearDown(readyNotifier.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  height: 400,
                  child: MeshPaperFlip(
                    pageCount: 3,
                    controller: controller,
                    pageBuilder: (context, index, constraints) {
                      if (index != 0) {
                        return ColoredBox(
                          color: Colors.green,
                          child: Center(child: Text('Async Page ${index + 1}')),
                        );
                      }
                      return ValueListenableBuilder<bool>(
                        valueListenable: readyNotifier,
                        builder: (context, isReady, _) {
                          return PageCaptureGuard(
                            isReady: isReady,
                            child: const ColoredBox(
                              color: Colors.blue,
                              child: Center(child: Text('Async Page 1')),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // When ready is false, MeshPaperFlip's atlas for page 0 should not be packed
        final dynamic state = tester.state(find.byType(MeshPaperFlip));
        // ignore: avoid_dynamic_calls
        expect(state.debugHasAtlas(0), isFalse);

        // Now set readyNotifier to true and dispatch PageReadyNotification
        readyNotifier.value = true;
        await tester.pump();
        final element = tester.element(find.text('Async Page 1').first);
        const PageReadyNotification(pageIndex: 0).dispatch(element);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        // Now it should be captured and atlas packed
        // ignore: avoid_dynamic_calls
        expect(state.debugHasAtlas(0), isTrue);

        // Flip to next page
        controller.flipNext();
        await tester.pumpAndSettle();
        expect(controller.currentPage, 1);
      });

      testWidgets(
        'repeated flipNext and flipPrev operations beyond page 3 navigate smoothly without stalling',
        (tester) async {
          final controller = PaperFlipController();
          addTearDown(controller.dispose);

          await tester.pumpWidget(_book(controller: controller, pageCount: 8));
          await tester.pumpAndSettle();
          expect(controller.currentPage, 0);

          // Repeatedly flip forwards beyond 3 pages
          for (var p = 1; p <= 7; p++) {
            controller.flipNext();
            await tester.pumpAndSettle();
            expect(
              controller.currentPage,
              p,
              reason: 'Failed navigating to page $p',
            );
          }

          // Repeatedly flip backwards
          for (var p = 6; p >= 0; p--) {
            controller.flipPrev();
            await tester.pumpAndSettle();
            expect(
              controller.currentPage,
              p,
              reason: 'Failed returning to page $p',
            );
          }

          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'permanent capture failure caps retries at 5 and falls back to direct navigation without infinite loops',
        (tester) async {
          final controller = PaperFlipController();
          addTearDown(controller.dispose);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 300,
                    height: 400,
                    child: MeshPaperFlip(
                      pageCount: 4,
                      controller: controller,
                      pageBuilder: (context, index, constraints) {
                        if (index == 1) {
                          // Page 1 is permanently unready for capture
                          return const PageCaptureGuard(
                            isReady: false,
                            child: ColoredBox(color: Colors.red),
                          );
                        }
                        return ColoredBox(
                          color: Colors.green,
                          child: Center(child: Text('Page ${index + 1}')),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          // Allow the bounded next-frame retries to run (capped at 5 attempts)
          for (var i = 0; i < 15; i++) {
            await tester.pump(const Duration(milliseconds: 16));
          }

          final dynamic state = tester.state(find.byType(MeshPaperFlip));
          // ignore: avoid_dynamic_calls
          expect(state.debugRetryCount(1), 5);
          // ignore: avoid_dynamic_calls
          expect(state.debugIsPermanentFailure(1), isTrue);

          // Calling flipNext must not hang or throw, but fallback to direct navigation
          controller.flipNext();
          await tester.pumpAndSettle();
          expect(controller.currentPage, 1);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'parent rebuild with newly allocated builder closure retains stable cache identity without re-capturing',
        (tester) async {
          final parentRebuildNotifier = ValueNotifier<int>(0);
          addTearDown(parentRebuildNotifier.dispose);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ValueListenableBuilder<int>(
                  valueListenable: parentRebuildNotifier,
                  builder: (context, val, _) {
                    // Fresh closure allocated on every rebuild with same contentVersion
                    return MeshPaperFlip(
                      pageCount: 3,
                      contentVersion: 1,
                      pageBuilder: (context, index, constraints) => ColoredBox(
                        color: Colors.white,
                        child: Text('Page $index build $val'),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final dynamic state = tester.state(find.byType(MeshPaperFlip));
          // ignore: avoid_dynamic_calls
          expect(state.debugHasAtlas(0), isTrue);
          // ignore: avoid_dynamic_calls
          expect(state.debugHasTexture(0), isTrue);

          // Trigger parent rebuild with newly allocated closure
          parentRebuildNotifier.value = 1;
          await tester.pump();

          // Cached texture and atlas must be preserved without invalidation
          // ignore: avoid_dynamic_calls
          expect(state.debugHasAtlas(0), isTrue);
          // ignore: avoid_dynamic_calls
          expect(state.debugHasTexture(0), isTrue);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'a page in permanent capture failure recovers when PageReadyNotification is dispatched',
        (tester) async {
          final controller = PaperFlipController();
          addTearDown(controller.dispose);

          final readyNotifier = ValueNotifier<bool>(false);
          addTearDown(readyNotifier.dispose);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 300,
                  height: 400,
                  child: MeshPaperFlip(
                    pageCount: 3,
                    controller: controller,
                    pageBuilder: (context, index, constraints) {
                      if (index == 1) {
                        return ValueListenableBuilder<bool>(
                          valueListenable: readyNotifier,
                          builder: (context, isReady, _) => PageCaptureGuard(
                            isReady: isReady,
                            child: const ColoredBox(color: Colors.purple),
                          ),
                        );
                      }
                      return ColoredBox(
                        color: Colors.teal,
                        child: Text('Page $index'),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          // Exhaust retries to reach permanent failure state
          for (var i = 0; i < 15; i++) {
            await tester.pump(const Duration(milliseconds: 16));
          }

          final dynamic state = tester.state(find.byType(MeshPaperFlip));
          // ignore: avoid_dynamic_calls
          expect(state.debugIsPermanentFailure(1), isTrue);
          // ignore: avoid_dynamic_calls
          expect(state.debugHasAtlas(1), isFalse);

          // Mark page 1 ready and dispatch PageReadyNotification
          readyNotifier.value = true;
          await tester.pump();
          final element = tester.firstElement(find.text('Page 0'));
          const PageReadyNotification(pageIndex: 1).dispatch(element);
          await tester.pump();
          await tester.pumpAndSettle();

          // Page 1 must have its permanent failure cleared and atlas packed
          // ignore: avoid_dynamic_calls
          expect(state.debugIsPermanentFailure(1), isFalse);
          // ignore: avoid_dynamic_calls
          expect(state.debugHasAtlas(1), isTrue);

          // Navigation can now turn to page 1 with curl animation
          controller.flipNext();
          await tester.pumpAndSettle();
          expect(controller.currentPage, 1);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'contentVersion change resets stale atlases and triggers clean recapture',
        (tester) async {
          final versionNotifier = ValueNotifier<int>(1);
          addTearDown(versionNotifier.dispose);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 300,
                    height: 400,
                    child: ValueListenableBuilder<int>(
                      valueListenable: versionNotifier,
                      builder: (context, version, _) {
                        return MeshPaperFlip(
                          pageCount: 3,
                          contentVersion: version,
                          pageBuilder: (context, index, constraints) =>
                              ColoredBox(
                                color: Colors.white,
                                child: Text('V$version P$index'),
                              ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final dynamic state = tester.state(find.byType(MeshPaperFlip));
          // ignore: avoid_dynamic_calls
          expect(state.debugHasAtlas(0), isTrue);

          // Update content version
          versionNotifier.value = 2;
          await tester.pump();
          // After re-settling, new version is captured
          await tester.pumpAndSettle();
          // ignore: avoid_dynamic_calls
          expect(state.debugHasAtlas(0), isTrue);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'disposing MeshPaperFlip while capture is in flight does not leak resources or crash',
        (tester) async {
          final showNotifier = ValueNotifier<bool>(true);
          addTearDown(showNotifier.dispose);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ValueListenableBuilder<bool>(
                  valueListenable: showNotifier,
                  builder: (context, show, _) {
                    if (!show) return const SizedBox.shrink();
                    return MeshPaperFlip(
                      pageCount: 4,
                      pageBuilder: (context, index, constraints) =>
                          const ColoredBox(color: Colors.blue),
                    );
                  },
                ),
              ),
            ),
          );
          // Initial pump mounts MeshPaperFlip and starts capture pipeline
          await tester.pump();

          // Immediately dispose widget by hiding it
          showNotifier.value = false;
          await tester.pump();
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'targeted PageReadyNotification invalidates in-flight capture, disposes stale texture, and does not install it',
        (tester) async {
          final completer = Completer<PageTexture?>();
          final captureStarted = Completer<void>();

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 300,
                  height: 400,
                  child: MeshPaperFlip(
                    pageCount: 4,
                    pageBuilder: (context, index, constraints) => ColoredBox(
                      color: Colors.blue,
                      child: Text('Page $index'),
                    ),
                  ),
                ),
              ),
            ),
          );

          final state = tester.state<MeshPaperFlipState>(
            find.byType(MeshPaperFlip),
          );

          state.debugCaptureOverride =
              (key, {required logicalSize, textureKey}) {
                if (!captureStarted.isCompleted) {
                  captureStarted.complete();
                }
                return completer.future;
              };

          await tester.pump();
          await captureStarted.future;

          // Dispatch targeted notification for page 0
          final element = tester.firstElement(find.text('Page 0'));
          const PageReadyNotification(pageIndex: 0).dispatch(element);
          await tester.pump();

          final testImg = await _createTestImage();
          final oldTexture = PageTexture(
            image: testImg,
            logicalSize: const Size(300, 400),
          );
          expect(oldTexture.isDisposed, isFalse);

          state.debugCaptureOverride = null;
          completer.complete(oldTexture);
          await tester.pump();

          // Old texture must be disposed and not installed in cache
          expect(oldTexture.isDisposed, isTrue);
          expect(state.debugHasTexture(0), isFalse);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'global PageReadyNotification invalidates in-flight capture and disposes stale texture',
        (tester) async {
          final completer = Completer<PageTexture?>();
          final captureStarted = Completer<void>();

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 300,
                  height: 400,
                  child: MeshPaperFlip(
                    pageCount: 4,
                    pageBuilder: (context, index, constraints) => ColoredBox(
                      color: Colors.blue,
                      child: Text('Page $index'),
                    ),
                  ),
                ),
              ),
            ),
          );

          final state = tester.state<MeshPaperFlipState>(
            find.byType(MeshPaperFlip),
          );

          state.debugCaptureOverride =
              (key, {required logicalSize, textureKey}) {
                if (!captureStarted.isCompleted) {
                  captureStarted.complete();
                }
                return completer.future;
              };

          await tester.pump();
          await captureStarted.future;

          // Dispatch global notification
          final element = tester.firstElement(find.text('Page 0'));
          const PageReadyNotification().dispatch(element);
          await tester.pump();

          final testImg = await _createTestImage();
          final oldTexture = PageTexture(
            image: testImg,
            logicalSize: const Size(300, 400),
          );
          state.debugCaptureOverride = null;
          completer.complete(oldTexture);
          await tester.pump();

          expect(oldTexture.isDisposed, isTrue);
          expect(state.debugScene.atlas, isNull);
          expect(state.debugScene.active, isFalse);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'targeted PageReadyNotification invalidates in-flight atlas pack and disposes stale atlas',
        (tester) async {
          final packCompleter = Completer<SheetAtlas>();
          final packStarted = Completer<void>();

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 300,
                  height: 400,
                  child: MeshPaperFlip(
                    pageCount: 4,
                    pageBuilder: (context, index, constraints) => ColoredBox(
                      color: Colors.blue,
                      child: Text('Page $index'),
                    ),
                  ),
                ),
              ),
            ),
          );

          final state = tester.state<MeshPaperFlipState>(
            find.byType(MeshPaperFlip),
          );

          state.debugPackAtlasOverride = (faces) {
            if (!packStarted.isCompleted) {
              packStarted.complete();
            }
            return packCompleter.future;
          };

          await tester.pump();
          await packStarted.future;

          // Dispatch targeted notification for page 0
          final element = tester.firstElement(find.text('Page 0'));
          const PageReadyNotification(pageIndex: 0).dispatch(element);
          await tester.pump();

          final testImg = await _createTestImage();
          final faces = PageFaceSet(
            front: PageTexture(
              image: testImg,
              logicalSize: const Size(300, 400),
            ),
            back: PageTexture(
              image: testImg.clone(),
              logicalSize: const Size(300, 400),
            ),
          );
          final oldAtlas = await SheetAtlas.pack(faces);
          faces.dispose();
          expect(oldAtlas.isDisposed, isFalse);

          state.debugPackAtlasOverride = null;
          packCompleter.complete(oldAtlas);
          await tester.pump();

          // Old atlas must be disposed and not installed in _atlases
          expect(oldAtlas.isDisposed, isTrue);
          expect(state.debugHasAtlas(0), isTrue);
          expect(state.debugScene.atlas, isNot(same(oldAtlas)));
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'global PageReadyNotification invalidates in-flight atlas pack and disposes stale atlas',
        (tester) async {
          final packCompleter = Completer<SheetAtlas>();
          final packStarted = Completer<void>();

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 300,
                  height: 400,
                  child: MeshPaperFlip(
                    pageCount: 4,
                    pageBuilder: (context, index, constraints) => ColoredBox(
                      color: Colors.blue,
                      child: Text('Page $index'),
                    ),
                  ),
                ),
              ),
            ),
          );

          final state = tester.state<MeshPaperFlipState>(
            find.byType(MeshPaperFlip),
          );

          state.debugPackAtlasOverride = (faces) {
            if (!packStarted.isCompleted) {
              packStarted.complete();
            }
            return packCompleter.future;
          };

          await tester.pump();
          await packStarted.future;

          // Dispatch global notification
          final element = tester.firstElement(find.text('Page 0'));
          const PageReadyNotification().dispatch(element);
          await tester.pump();

          final testImg = await _createTestImage();
          final faces = PageFaceSet(
            front: PageTexture(
              image: testImg,
              logicalSize: const Size(300, 400),
            ),
            back: PageTexture(
              image: testImg.clone(),
              logicalSize: const Size(300, 400),
            ),
          );
          final oldAtlas = await SheetAtlas.pack(faces);
          faces.dispose();

          state.debugPackAtlasOverride = null;
          packCompleter.complete(oldAtlas);
          await tester.pump();

          expect(oldAtlas.isDisposed, isTrue);
          expect(state.debugHasAtlas(0), isTrue);
          expect(state.debugScene.atlas, isNot(same(oldAtlas)));
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'stale atlas pack finishing after targeted PageReadyNotification retries fresh atlas preparation and allows navigation',
        (tester) async {
          final controller = PaperFlipController();
          final packCompleter = Completer<SheetAtlas>();
          final packStarted = Completer<void>();
          var packInvocations = 0;

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 300,
                  height: 400,
                  child: MeshPaperFlip(
                    controller: controller,
                    pageCount: 4,
                    pageBuilder: (context, index, constraints) => ColoredBox(
                      color: Colors.blue,
                      child: Text('Page $index'),
                    ),
                  ),
                ),
              ),
            ),
          );

          final state = tester.state<MeshPaperFlipState>(
            find.byType(MeshPaperFlip),
          );

          state.debugPackAtlasOverride = (faces) {
            packInvocations++;
            if (packInvocations == 1) {
              if (!packStarted.isCompleted) {
                packStarted.complete();
              }
              return packCompleter.future;
            }
            return SheetAtlas.pack(faces);
          };

          // 1. Start packing an atlas for page 0
          await tester.pump();
          await packStarted.future;
          expect(state.debugIsPacking(0), isTrue);

          // 2. Dispatch targeted PageReadyNotification for page 0
          final element = tester.firstElement(find.text('Page 0'));
          const PageReadyNotification(pageIndex: 0).dispatch(element);

          // 3. Allow fresh capture to complete while old pack remains pending
          await tester.pump();
          expect(state.debugHasTexture(0), isTrue);
          expect(state.debugIsPacking(0), isTrue);

          // 4. Complete old pack
          final testImg = await _createTestImage();
          final faces = PageFaceSet(
            front: PageTexture(
              image: testImg,
              logicalSize: const Size(300, 400),
            ),
            back: PageTexture(
              image: testImg.clone(),
              logicalSize: const Size(300, 400),
            ),
          );
          final oldAtlas = await SheetAtlas.pack(faces);
          faces.dispose();
          expect(oldAtlas.isDisposed, isFalse);

          packCompleter.complete(oldAtlas);
          await tester.pump();

          // 5. Verify stale atlas is disposed, fresh content is packed, and navigation completes
          expect(oldAtlas.isDisposed, isTrue);
          await tester.pumpAndSettle();
          expect(state.debugHasAtlas(0), isTrue);
          expect(state.debugIsPacking(0), isFalse);

          controller.flipNext();
          await tester.pumpAndSettle();
          expect(controller.currentPage, 1);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'global PageReadyNotification invalidation ensures old operation cannot remove newer operation marker',
        (tester) async {
          final controller = PaperFlipController();
          final oldPackCompleter = Completer<SheetAtlas>();
          final newPackCompleter = Completer<SheetAtlas>();
          final oldPackStarted = Completer<void>();
          final newPackStarted = Completer<void>();
          var packInvocations = 0;

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 300,
                  height: 400,
                  child: MeshPaperFlip(
                    controller: controller,
                    pageCount: 4,
                    pageBuilder: (context, index, constraints) => ColoredBox(
                      color: Colors.blue,
                      child: Text('Page $index'),
                    ),
                  ),
                ),
              ),
            ),
          );

          final state = tester.state<MeshPaperFlipState>(
            find.byType(MeshPaperFlip),
          );

          state.debugPackAtlasOverride = (faces) {
            packInvocations++;
            if (packInvocations == 1) {
              if (!oldPackStarted.isCompleted) {
                oldPackStarted.complete();
              }
              return oldPackCompleter.future;
            } else if (packInvocations == 2) {
              if (!newPackStarted.isCompleted) {
                newPackStarted.complete();
              }
              return newPackCompleter.future;
            }
            return SheetAtlas.pack(faces);
          };

          // 1. Start Operation 1 packing atlas 0
          await tester.pump();
          await oldPackStarted.future;
          expect(state.debugIsPacking(0), isTrue);

          // 2. Dispatch global readiness notification (invalidates textures and clears _packing)
          final element = tester.firstElement(find.text('Page 0'));
          const PageReadyNotification().dispatch(element);

          // 3. New capture pass runs and Operation 2 starts packing page 0
          await tester.pump();
          await newPackStarted.future;
          expect(state.debugIsPacking(0), isTrue);

          // 4. Complete Operation 1 (the old pack)
          final testImg1 = await _createTestImage();
          final faces1 = PageFaceSet(
            front: PageTexture(
              image: testImg1,
              logicalSize: const Size(300, 400),
            ),
            back: PageTexture(
              image: testImg1.clone(),
              logicalSize: const Size(300, 400),
            ),
          );
          final oldAtlas = await SheetAtlas.pack(faces1);
          faces1.dispose();
          expect(oldAtlas.isDisposed, isFalse);

          oldPackCompleter.complete(oldAtlas);
          await tester.pump();

          // Old atlas was stale and must be disposed
          expect(oldAtlas.isDisposed, isTrue);
          // Crucial: Old operation must NOT remove Operation 2's marker!
          expect(state.debugIsPacking(0), isTrue);

          // 5. Complete Operation 2
          final testImg2 = await _createTestImage();
          final faces2 = PageFaceSet(
            front: PageTexture(
              image: testImg2,
              logicalSize: const Size(300, 400),
            ),
            back: PageTexture(
              image: testImg2.clone(),
              logicalSize: const Size(300, 400),
            ),
          );
          final freshAtlas = await SheetAtlas.pack(faces2);
          faces2.dispose();
          newPackCompleter.complete(freshAtlas);
          await tester.pumpAndSettle();

          // Fresh atlas is available and packing entry is released
          expect(state.debugHasAtlas(0), isTrue);
          expect(state.debugIsPacking(0), isFalse);

          // Navigation completes successfully
          controller.flipNext();
          await tester.pumpAndSettle();
          expect(controller.currentPage, 1);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'invalidated atlas pack throwing after readiness notification retries and allows navigation',
        (tester) async {
          final controller = PaperFlipController();
          final packStarted = Completer<void>();
          final packErrorTrigger = Completer<void>();
          var packInvocations = 0;

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 300,
                  height: 400,
                  child: MeshPaperFlip(
                    controller: controller,
                    pageCount: 4,
                    pageBuilder: (context, index, constraints) => ColoredBox(
                      color: Colors.blue,
                      child: Text('Page $index'),
                    ),
                  ),
                ),
              ),
            ),
          );

          final state = tester.state<MeshPaperFlipState>(
            find.byType(MeshPaperFlip),
          );

          state.debugPackAtlasOverride = (faces) async {
            packInvocations++;
            if (packInvocations == 1) {
              if (!packStarted.isCompleted) {
                packStarted.complete();
              }
              await packErrorTrigger.future;
              throw StateError('Simulated atlas packing failure while stale');
            }
            return SheetAtlas.pack(faces);
          };

          // 1. Start packing atlas 0
          await tester.pump();
          await packStarted.future;
          expect(state.debugIsPacking(0), isTrue);

          // 2. Dispatch targeted PageReadyNotification for page 0
          final element = tester.firstElement(find.text('Page 0'));
          const PageReadyNotification(pageIndex: 0).dispatch(element);

          // 3. Allow fresh capture to complete while old pack remains pending
          await tester.pump();
          expect(state.debugHasTexture(0), isTrue);
          expect(state.debugIsPacking(0), isTrue);

          // 4. Stale pack throws
          packErrorTrigger.complete();
          await tester.pumpAndSettle();

          // 5. Fresh atlas was packed via retry and navigation succeeds
          expect(state.debugHasAtlas(0), isTrue);
          expect(state.debugIsPacking(0), isFalse);

          controller.flipNext();
          await tester.pumpAndSettle();
          expect(controller.currentPage, 1);
          expect(tester.takeException(), isNull);
        },
      );
    });
  });
}
