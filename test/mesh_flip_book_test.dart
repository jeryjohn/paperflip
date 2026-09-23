import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flip_book/flip_book.dart';
import 'package:flip_book/src/rendering/curl_parameters.dart';
import 'package:flip_book/src/rendering/flip_scene.dart';
import 'package:flip_book/src/rendering/page_curl_geometry.dart';
import 'package:flip_book/src/rendering/page_curl_mesh.dart';
import 'package:flip_book/src/rendering/page_curl_renderer.dart';

Widget _book({
  FlipBookController? controller,
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
          child: MeshFlipBook(
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
  testWidgets('renders the current page as a live widget at rest',
      (tester) async {
    await tester.pumpWidget(_book());
    await tester.pumpAndSettle();
    // The live page and the capture host both mount page 1.
    expect(find.text('Page 1'), findsWidgets);
  });

  testWidgets('a drag turns the page', (tester) async {
    final controller = FlipBookController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_book(controller: controller));
    await tester.pumpAndSettle();
    expect(controller.currentPage, 0);

    // Drag left, well past the commit threshold.
    await tester.drag(find.byType(MeshFlipBook), const Offset(-260, 0));
    await tester.pumpAndSettle();

    expect(controller.currentPage, 1);
  });

  testWidgets('a short drag cancels back to the same page', (tester) async {
    final controller = FlipBookController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_book(controller: controller));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MeshFlipBook)),
    );
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.currentPage, 0);
  });

  testWidgets('a drag never leaves the sheet resting mid-turn', (tester) async {
    final controller = FlipBookController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_book(controller: controller));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MeshFlipBook)),
    );
    await gesture.moveBy(const Offset(-150, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.isAnimating, isFalse);
  });

  testWidgets('the controller flips programmatically', (tester) async {
    final controller = FlipBookController();
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
    final controller = FlipBookController();
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
    final controller = FlipBookController();
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
    final controller = FlipBookController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_book(controller: controller, pageCount: 2));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(MeshFlipBook), const Offset(260, 0));
    await tester.pumpAndSettle();
    expect(controller.currentPage, 0);

    await tester.drag(find.byType(MeshFlipBook), const Offset(-260, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(MeshFlipBook), const Offset(-260, 0));
    await tester.pumpAndSettle();
    expect(controller.currentPage, 1);
  });

  testWidgets('tearing down mid-flip does not throw', (tester) async {
    final controller = FlipBookController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_book(controller: controller));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MeshFlipBook)),
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
      final controller = FlipBookController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_book(controller: controller));
      await tester.pumpAndSettle();
      expect(controller.currentPage, 0);

      await tester.drag(find.byType(MeshFlipBook), const Offset(-260, 0));
      await tester.pumpAndSettle();
      expect(controller.currentPage, 1);
    });

    testWidgets('a backward swipe from page > 0 returns to previous page',
        (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_book(controller: controller));
      await tester.pumpAndSettle();

      // Go to page 2 first.
      await controller.goToPage(2, animate: false);
      await tester.pumpAndSettle();
      expect(controller.currentPage, 2);

      // Drag right to flip backward.
      await tester.drag(find.byType(MeshFlipBook), const Offset(260, 0));
      await tester.pumpAndSettle();
      expect(controller.currentPage, 1);
    });
  });

  group('partial-drag cancellation', () {
    testWidgets('a partial forward drag cancels back to current page',
        (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_book(controller: controller));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(MeshFlipBook)),
      );
      // Move only slightly left (below commit threshold).
      await gesture.moveBy(const Offset(-25, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(controller.currentPage, 0);
      expect(controller.isAnimating, isFalse);
    });

    testWidgets('a partial backward drag cancels back to current page',
        (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_book(controller: controller));
      await tester.pumpAndSettle();

      await controller.goToPage(2, animate: false);
      await tester.pumpAndSettle();
      expect(controller.currentPage, 2);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(MeshFlipBook)),
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

    test('PageCurlRenderer direction-aware face and UV selection prevents mirrored text', () {
      // Forward turn: never mirror horizontally
      expect(
        PageCurlRenderer.resolveMirrorHorizontally(direction: 1, showBack: false),
        isFalse,
      );
      expect(
        PageCurlRenderer.resolveMirrorHorizontally(direction: 1, showBack: true),
        isFalse,
      );

      // Backward turn: mirror UVs along U so reading order matches physical screen left-to-right
      expect(
        PageCurlRenderer.resolveMirrorHorizontally(direction: -1, showBack: false),
        isTrue,
      );
      expect(
        PageCurlRenderer.resolveMirrorHorizontally(direction: -1, showBack: true),
        isTrue,
      );

      // Face selection transitions at 0.5 for two-face atlases
      expect(
        PageCurlRenderer.resolveShowBack(isSingleFace: false, progress: 0.3, direction: 1),
        isFalse,
      );
      expect(
        PageCurlRenderer.resolveShowBack(isSingleFace: false, progress: 0.7, direction: 1),
        isTrue,
      );
      expect(
        PageCurlRenderer.resolveShowBack(isSingleFace: false, progress: 0.3, direction: -1),
        isFalse,
      );
      expect(
        PageCurlRenderer.resolveShowBack(isSingleFace: false, progress: 0.7, direction: -1),
        isTrue,
      );

      // Single-face atlases always show front face
      expect(
        PageCurlRenderer.resolveShowBack(isSingleFace: true, progress: 0.9, direction: 1),
        isFalse,
      );
    });

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
      final lastColVertexTexXForward = mesh.textureCoordinates[mesh.columns * 2];
      expect(firstVertexTexXForward, closeTo(region.left, 0.1));
      expect(lastColVertexTexXForward, closeTo(region.right, 0.1));

      // Backward (direction < 0): mirrorHorizontally is true.
      // In backward geometry, col = 0 is at screen right (x = w), and col = cols is at screen left (x = 0).
      // With mirrorHorizontally: true:
      // col = 0 (screen right) -> textureCoordinates[x] is region.right
      // col = cols (screen left) -> textureCoordinates[x] is region.left
      mesh.updateTextureRegion(region, mirrorHorizontally: true);
      final firstVertexTexXBackward = mesh.textureCoordinates[0];
      final lastColVertexTexXBackward = mesh.textureCoordinates[mesh.columns * 2];
      expect(firstVertexTexXBackward, closeTo(region.right, 0.1));
      expect(lastColVertexTexXBackward, closeTo(region.left, 0.1));
    });

    testWidgets(
        'backward and forward page navigation sequence (0 -> 1 -> 2 -> 1 -> 0)',
        (tester) async {
      final controller = FlipBookController();
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
    });

    test('CurlParameters and geometry smoothly transition across 0.5 midpoint',
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
          expect(mesh.worldPositions[i].isFinite, isTrue,
              reason: 'non-finite vertex at progress $p');
        }

        // Lift must be non-negative and transition smoothly without sudden jumps.
        final peakLift = PageCurlLighting.peakLift(mesh);
        expect(peakLift, greaterThanOrEqualTo(0.0));
        if (prevPeakLift != null) {
          final diff = (peakLift - prevPeakLift).abs();
          expect(diff, lessThan(40.0),
              reason: 'sudden jump in peak lift ($diff) around progress $p');
        }
        prevPeakLift = peakLift;
      }
    });

    testWidgets('FlipBook.custom renders using MeshFlipBook', (tester) async {
      final controller = FlipBookController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlipBook.custom(
              pageCount: 5,
              controller: controller,
              pageBuilder: (context, index, constraints) => Center(
                child: Text('Custom Page $index'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MeshFlipBook), findsOneWidget);
      expect(find.text('Custom Page 0'), findsWidgets);

      controller.flipNext();
      await tester.pumpAndSettle();
      expect(controller.currentPage, 1);
      expect(find.text('Custom Page 1'), findsWidgets);
    });

    group('button and programmatic navigation animation pipeline', () {
      testWidgets('Next button animates progress continuously while current page remains stable',
          (tester) async {
        final controller = FlipBookController();
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
        expect(controller.currentPage, 2,
            reason: 'Current page must remain 2 during turn animation');

        final state = tester.state<MeshFlipBookState>(find.byType(MeshFlipBook));
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
          expect(controller.currentPage, 2,
              reason: 'Page index must not change before animation completes');
          final scene = state.debugScene;
          expect(scene.active, isTrue);
          progressValues.add(scene.curl.progress);
        }

        expect(progressValues.isNotEmpty, isTrue);
        expect(progressValues.first, greaterThanOrEqualTo(0.0));
        expect(progressValues.last, greaterThan(progressValues.first));

        await tester.pumpAndSettle();
        expect(controller.isAnimating, isFalse);
        expect(controller.currentPage, 3,
            reason: 'Destination page committed only after animation completes');
      });

      testWidgets('Previous button animates backward turn with correct roles and orientation',
          (tester) async {
        final controller = FlipBookController();
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
        expect(controller.currentPage, 2,
            reason: 'Current page must remain 2 during turn animation');

        final state = tester.state<MeshFlipBookState>(find.byType(MeshFlipBook));
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
          expect(controller.currentPage, 2,
              reason: 'Page index must not change before animation completes');
          final scene = state.debugScene;
          expect(scene.active, isTrue);
          progressValues.add(scene.curl.progress);
        }

        expect(progressValues.isNotEmpty, isTrue);
        expect(progressValues.first, greaterThanOrEqualTo(0.0));
        expect(progressValues.last, greaterThan(progressValues.first));

        await tester.pumpAndSettle();
        expect(controller.isAnimating, isFalse);
        expect(controller.currentPage, 1,
            reason: 'Destination page committed only after animation completes');
      });

      testWidgets('first page + Previous does not navigate or animate',
          (tester) async {
        final controller = FlipBookController();
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

      testWidgets('last page + Next does not navigate or animate',
          (tester) async {
        final controller = FlipBookController();
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

      testWidgets('repeated button presses queue and do not corrupt state',
          (tester) async {
        final controller = FlipBookController();
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
  });
}
