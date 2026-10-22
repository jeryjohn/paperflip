import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:paperflip/paperflip.dart';

class _FakeDocumentRef extends PdfDocumentRef {
  _FakeDocumentRef(this.id, {this.completer})
    : super(key: PdfDocumentRefKey(id));

  final String id;
  final Completer<PdfDocument>? completer;
  int loadCount = 0;

  @override
  Future<PdfDocument> loadDocument(
    PdfDocumentLoaderProgressCallback progressCallback,
  ) async {
    loadCount++;
    if (completer != null) {
      return completer!.future;
    }
    throw UnimplementedError('Simulated test loading failure');
  }

  @override
  bool get firstAttemptByEmptyPassword => true;

  @override
  PdfPasswordProvider? get passwordProvider => null;
}

void main() {
  group('PaperFlipPdf lifecycle and equality tests', () {
    testWidgets('shows loadingBuilder while document is loading', (
      tester,
    ) async {
      final completer = Completer<PdfDocument>();
      final ref = _FakeDocumentRef('doc-1', completer: completer);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaperFlipPdf(
              source: ref,
              loadingBuilder: (context) => const Text('Custom Loading...'),
            ),
          ),
        ),
      );

      expect(find.text('Custom Loading...'), findsOneWidget);
      expect(ref.loadCount, 1);
    });

    testWidgets('shows errorBuilder on document load failure', (tester) async {
      final ref = _FakeDocumentRef('doc-err');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaperFlipPdf(
              source: ref,
              errorBuilder: (context, error) => Text('Error: $error'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Error:'), findsOneWidget);
    });

    testWidgets(
      'does not reload document when rebuilt with different instance but same key',
      (tester) async {
        final completer = Completer<PdfDocument>();
        final ref1 = _FakeDocumentRef('doc-same', completer: completer);
        final ref2 = _FakeDocumentRef('doc-same', completer: completer);

        final notifier = ValueNotifier<PdfDocumentRef>(ref1);
        addTearDown(notifier.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<PdfDocumentRef>(
                valueListenable: notifier,
                builder: (context, source, _) {
                  return PaperFlipPdf(
                    source: source,
                    loadingBuilder: (context) => const Text('Loading...'),
                  );
                },
              ),
            ),
          ),
        );

        expect(ref1.loadCount, 1);
        expect(ref2.loadCount, 0);

        // Rebuild with ref2 (same key 'doc-same')
        notifier.value = ref2;
        await tester.pump();

        // ref2 should NOT have had its loadDocument called because source.key is identical
        expect(ref2.loadCount, 0);
        expect(ref1.loadCount, 1);

        // Rebuild with genuinely different key
        final ref3 = _FakeDocumentRef('doc-different', completer: completer);
        notifier.value = ref3;
        await tester.pump();

        // ref3 should now load because key changed
        expect(ref3.loadCount, 1);
      },
    );

    testWidgets(
      'changing PDF source reloads new document and updates PaperFlipPdf',
      (tester) async {
        final doc1 = _MockPdfDocument(pageCount: 5);
        final doc2 = _MockPdfDocument(pageCount: 5);
        final ref1 = _FakeDocumentRef(
          'source-1',
          completer: Completer<PdfDocument>()..complete(doc1),
        );
        final ref2 = _FakeDocumentRef(
          'source-2',
          completer: Completer<PdfDocument>()..complete(doc2),
        );

        final sourceNotifier = ValueNotifier<PdfDocumentRef>(ref1);
        addTearDown(sourceNotifier.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<PdfDocumentRef>(
                valueListenable: sourceNotifier,
                builder: (context, source, _) {
                  return PaperFlipPdf(source: source);
                },
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byType(MeshPaperFlip), findsOneWidget);

        // Change source to ref2
        sourceNotifier.value = ref2;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byType(MeshPaperFlip), findsOneWidget);
        expect(ref1.loadCount, 1);
        expect(ref2.loadCount, 1);
      },
    );
  });

  group('PdfPageImageCache lifecycle regression tests', () {
    Future<ui.Image> createTestImage() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 10, 10),
        Paint()..color = const Color(0xFF00FF00),
      );
      final picture = recorder.endRecording();
      return picture.toImage(10, 10);
    }

    test(
      'disposing cache while rendering is in flight disposes returned image without leak',
      () async {
        final completer = Completer<ui.Image?>();
        final doc = _MockPdfDocument(pageCount: 5);
        final cache = PdfPageImageCache(
          document: doc,
          renderOverride: (pageIndex, w, h) => completer.future,
        );

        // Start load in flight
        final loadFuture = cache.loadPage(0, fullWidth: 100, fullHeight: 100);
        expect(cache.hasInFlight(0), isTrue);

        // Dispose cache while render is in flight
        cache.dispose();
        expect(cache.isDisposed, isTrue);

        // Now complete the render operation
        final image = await createTestImage();
        completer.complete(image);

        final result = await loadFuture;
        expect(result, isNull);
        expect(cache.cachedCount, 0);
        // Verify image was disposed immediately rather than leaked
        expect(image.debugDisposed, isTrue);
      },
    );

    test('prevents new loads after disposal', () async {
      var renderCalled = false;
      final doc = _MockPdfDocument(pageCount: 5);
      final cache = PdfPageImageCache(
        document: doc,
        renderOverride: (pageIndex, w, h) async {
          renderCalled = true;
          return createTestImage();
        },
      );

      cache.dispose();
      final result = await cache.loadPage(0, fullWidth: 100, fullHeight: 100);
      expect(result, isNull);
      expect(renderCalled, isFalse);
      expect(cache.getImageSync(0), isNull);
    });

    test(
      'LRU cache evicts and disposes oldest images when max entries is exceeded',
      () async {
        final images = <int, ui.Image>{};
        final doc = _MockPdfDocument(pageCount: 12);
        final cache = PdfPageImageCache(
          document: doc,
          renderOverride: (pageIndex, w, h) async {
            final img = await createTestImage();
            images[pageIndex] = img;
            return img;
          },
        );

        // Load 8 pages (filling the cache)
        for (var i = 0; i < 8; i++) {
          await cache.loadPage(i, fullWidth: 100, fullHeight: 100);
        }
        expect(cache.cachedCount, 8);
        expect(cache.hasPageCached(0), isTrue);
        expect(images[0]!.debugDisposed, isFalse);

        // Load 9th page (should evict page 0)
        await cache.loadPage(8, fullWidth: 100, fullHeight: 100);
        expect(cache.cachedCount, 8);
        expect(cache.hasPageCached(0), isFalse);
        expect(cache.hasPageCached(8), isTrue);
        // Evicted image for page 0 MUST be disposed
        expect(images[0]!.debugDisposed, isTrue);

        cache.dispose();
        // All remaining images should be disposed
        for (var i = 1; i <= 8; i++) {
          expect(images[i]!.debugDisposed, isTrue);
        }
      },
    );

    test(
      'render failure does not leave cache or page permanently broken',
      () async {
        var shouldFail = true;
        final doc = _MockPdfDocument(pageCount: 5);
        final cache = PdfPageImageCache(
          document: doc,
          renderOverride: (pageIndex, w, h) async {
            if (shouldFail) {
              throw Exception('Simulated render error');
            }
            return createTestImage();
          },
        );

        final failedResult = await cache.loadPage(
          0,
          fullWidth: 100,
          fullHeight: 100,
        );
        expect(failedResult, isNull);
        expect(cache.hasPageCached(0), isFalse);
        expect(cache.hasInFlight(0), isFalse);

        // Subsequent attempt after error recovers successfully
        shouldFail = false;
        final successResult = await cache.loadPage(
          0,
          fullWidth: 100,
          fullHeight: 100,
        );
        expect(successResult, isNotNull);
        expect(cache.hasPageCached(0), isTrue);
        cache.dispose();
      },
    );

    test(
      'in-flight render deduplication shares a single render operation',
      () async {
        var renderCount = 0;
        final completer = Completer<ui.Image?>();
        final doc = _MockPdfDocument(pageCount: 5);
        final cache = PdfPageImageCache(
          document: doc,
          renderOverride: (pageIndex, w, h) {
            renderCount++;
            return completer.future;
          },
        );

        final f1 = cache.loadPage(0, fullWidth: 100, fullHeight: 100);
        final f2 = cache.loadPage(0, fullWidth: 100, fullHeight: 100);
        expect(cache.hasInFlight(0), isTrue);
        expect(renderCount, 1);

        final img = await createTestImage();
        completer.complete(img);

        final res1 = await f1;
        final res2 = await f2;
        expect(res1, equals(res2));
        expect(cache.hasInFlight(0), isFalse);
        cache.dispose();
      },
    );
  });
}

class _MockPdfDocument implements PdfDocument {
  _MockPdfDocument({this.pageCount = 10});
  final int pageCount;

  @override
  late final List<PdfPage> pages = List.generate(
    pageCount,
    (index) => _MockPdfPage(index: index),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #loadPagesProgressively ||
        invocation.memberName == #dispose) {
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

class _MockPdfPage implements PdfPage {
  _MockPdfPage({required this.index});
  final int index;

  @override
  double get width => 600.0;

  @override
  double get height => 800.0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
