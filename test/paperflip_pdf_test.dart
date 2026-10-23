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

    test(
      'PdfImage returned by page.render() is properly disposed after createImage()',
      () async {
        final uiImage = await createTestImage();
        final mockPdfImage = _MockPdfImage();

        final mockPage = _MockPdfPage(
          index: 0,
          onRender: (w, h) async => mockPdfImage,
        );
        final doc = _MockPdfDocument(customPages: [mockPage]);
        final cache = PdfPageImageCache(
          document: doc,
          createImageOverride: (_) async => uiImage,
        );

        expect(mockPdfImage.isDisposed, isFalse);
        final result = await cache.loadPage(0, fullWidth: 100, fullHeight: 100);

        expect(result, isNotNull);
        // Verify that pdfImage.dispose() was reliably called in the finally block
        expect(mockPdfImage.isDisposed, isTrue);
        expect(cache.hasPageCached(0), isTrue);

        cache.dispose();
        expect(uiImage.debugDisposed, isTrue);
      },
    );

    test(
      'disposing cache while render is in flight disposes PdfImage',
      () async {
        final mockPdfImage = _MockPdfImage();
        final completer = Completer<PdfImage?>();

        final mockPage = _MockPdfPage(
          index: 0,
          onRender: (w, h) => completer.future,
        );
        final doc = _MockPdfDocument(customPages: [mockPage]);
        final cache = PdfPageImageCache(document: doc);

        final loadFuture = cache.loadPage(0, fullWidth: 100, fullHeight: 100);
        expect(cache.hasInFlight(0), isTrue);

        // Dispose cache while render is awaiting
        cache.dispose();
        expect(cache.isDisposed, isTrue);

        // Now complete render
        completer.complete(mockPdfImage);
        final result = await loadFuture;

        expect(result, isNull);
        // mockPdfImage must be disposed and never leaked
        expect(mockPdfImage.isDisposed, isTrue);
      },
    );

    test(
      'disposing cache during createImage disposes PdfImage and resulting ui.Image',
      () async {
        final uiImage = await createTestImage();
        final mockPdfImage = _MockPdfImage();
        final renderCompleter = Completer<PdfImage>();
        final createImageStarted = Completer<void>();
        final createImageCompleter = Completer<ui.Image>();

        final mockPage = _MockPdfPage(
          index: 0,
          onRender: (w, h) => renderCompleter.future,
        );
        final doc = _MockPdfDocument(customPages: [mockPage]);
        final cache = PdfPageImageCache(
          document: doc,
          createImageOverride: (_) {
            createImageStarted.complete();
            return createImageCompleter.future;
          },
        );

        final loadFuture = cache.loadPage(0, fullWidth: 100, fullHeight: 100);
        expect(cache.hasInFlight(0), isTrue);

        // Complete page.render() so execution enters createImageOverride
        renderCompleter.complete(mockPdfImage);
        await createImageStarted.future;

        // Dispose cache while createImage is in flight
        cache.dispose();
        expect(cache.isDisposed, isTrue);

        // Now complete createImage
        createImageCompleter.complete(uiImage);
        final result = await loadFuture;

        expect(result, isNull);
        // Both mockPdfImage and uiImage must be disposed
        expect(mockPdfImage.isDisposed, isTrue);
        expect(uiImage.debugDisposed, isTrue);
      },
    );
  });

  group('PdfPageContent handle ownership regression tests', () {
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

    testWidgets(
      'cache eviction while widget is mounted leaves widget image handle valid',
      (tester) async {
        final cacheImages = <int, ui.Image>{};
        final doc = _MockPdfDocument(pageCount: 10);
        final cache = PdfPageImageCache(
          document: doc,
          renderOverride: (pageIndex, w, h) async {
            final img = await createTestImage();
            cacheImages[pageIndex] = img;
            return img;
          },
        );
        addTearDown(cache.dispose);

        // Mount PdfPageContent for page 0
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 400,
                child: PdfPageContent(
                  document: doc,
                  pageIndex: 0,
                  constraints: const BoxConstraints(
                    maxWidth: 300,
                    maxHeight: 400,
                  ),
                  cache: cache,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final dynamic state = tester.state(find.byType(PdfPageContent));
        // ignore: avoid_dynamic_calls
        final widgetImg = state.debugImage as ui.Image?;
        expect(widgetImg, isNotNull);
        expect(widgetImg!.debugDisposed, isFalse);
        final cacheImg = cacheImages[0]!;
        expect(cacheImg.debugDisposed, isFalse);

        // Now load 8 more pages in cache (1 through 8), which forces page 0 eviction from cache
        for (var i = 1; i <= 8; i++) {
          await cache.loadPage(i, fullWidth: 100, fullHeight: 100);
        }
        expect(cache.hasPageCached(0), isFalse);
        // The cache's own handle for page 0 is now disposed
        expect(cacheImg.debugDisposed, isTrue);

        // But the mounted widget's own cloned handle is STILL NOT DISPOSED and valid!
        expect(widgetImg.debugDisposed, isFalse);

        // Pumping and painting continues without error
        await tester.pump();
        expect(tester.takeException(), isNull);

        // Unmount the widget: widget disposal must now dispose widgetImg
        await tester.pumpWidget(const SizedBox.shrink());
        expect(widgetImg.debugDisposed, isTrue);
      },
    );

    testWidgets(
      'widget disposal disposes widget cloned handle while cache retains its own handle',
      (tester) async {
        ui.Image? cacheImg;
        final doc = _MockPdfDocument(pageCount: 5);
        final cache = PdfPageImageCache(
          document: doc,
          renderOverride: (pageIndex, w, h) async {
            cacheImg = await createTestImage();
            return cacheImg;
          },
        );
        addTearDown(cache.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PdfPageContent(
                document: doc,
                pageIndex: 0,
                constraints: const BoxConstraints(
                  maxWidth: 300,
                  maxHeight: 400,
                ),
                cache: cache,
                backgroundColor: Colors.white,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final dynamic state = tester.state(find.byType(PdfPageContent));
        // ignore: avoid_dynamic_calls
        final widgetImg = state.debugImage as ui.Image?;
        expect(widgetImg, isNotNull);
        expect(widgetImg!.debugDisposed, isFalse);
        expect(cacheImg!.debugDisposed, isFalse);

        // Unmount widget
        await tester.pumpWidget(const SizedBox.shrink());

        // Widget handle is disposed
        expect(widgetImg.debugDisposed, isTrue);
        // Cache handle remains active and valid
        expect(cacheImg!.debugDisposed, isFalse);
        expect(cache.hasPageCached(0), isTrue);
      },
    );

    testWidgets(
      'updating widget pageIndex disposes old cloned handle and acquires new page handle',
      (tester) async {
        final doc = _MockPdfDocument(pageCount: 5);
        final cache = PdfPageImageCache(
          document: doc,
          renderOverride: (pageIndex, w, h) async => createTestImage(),
        );
        addTearDown(cache.dispose);

        final pageNotifier = ValueNotifier<int>(0);
        addTearDown(pageNotifier.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<int>(
                valueListenable: pageNotifier,
                builder: (context, pageIndex, _) => PdfPageContent(
                  document: doc,
                  pageIndex: pageIndex,
                  constraints: const BoxConstraints(
                    maxWidth: 300,
                    maxHeight: 400,
                  ),
                  cache: cache,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final dynamic state = tester.state(find.byType(PdfPageContent));
        // ignore: avoid_dynamic_calls
        final oldWidgetImg = state.debugImage as ui.Image?;
        expect(oldWidgetImg, isNotNull);
        expect(oldWidgetImg!.debugDisposed, isFalse);

        // Switch page to 1
        pageNotifier.value = 1;
        await tester.pumpAndSettle();

        // ignore: avoid_dynamic_calls
        final newWidgetImg = state.debugImage as ui.Image?;
        expect(newWidgetImg, isNotNull);
        expect(newWidgetImg, isNot(same(oldWidgetImg)));
        expect(newWidgetImg!.debugDisposed, isFalse);
        // Old handle was cleanly disposed when replaced
        expect(oldWidgetImg.debugDisposed, isTrue);
      },
    );

    testWidgets(
      'document and cache replacement cancels in-flight fetch and prevents stale display',
      (tester) async {
        final doc1 = _MockPdfDocument(pageCount: 5);
        final doc2 = _MockPdfDocument(pageCount: 5);
        final completer1 = Completer<ui.Image>();
        final cache1 = PdfPageImageCache(
          document: doc1,
          renderOverride: (pageIndex, w, h) => completer1.future,
        );
        final cache2 = PdfPageImageCache(
          document: doc2,
          renderOverride: (pageIndex, w, h) async => createTestImage(),
        );
        addTearDown(cache1.dispose);
        addTearDown(cache2.dispose);

        final notifier =
            ValueNotifier<({PdfDocument doc, PdfPageImageCache cache})>((
              doc: doc1,
              cache: cache1,
            ));
        addTearDown(notifier.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body:
                  ValueListenableBuilder<
                    ({PdfDocument doc, PdfPageImageCache cache})
                  >(
                    valueListenable: notifier,
                    builder: (context, val, _) => PdfPageContent(
                      document: val.doc,
                      pageIndex: 0,
                      constraints: const BoxConstraints(
                        maxWidth: 300,
                        maxHeight: 400,
                      ),
                      cache: val.cache,
                      backgroundColor: Colors.white,
                    ),
                  ),
            ),
          ),
        );
        await tester.pump();

        final dynamic state = tester.state(find.byType(PdfPageContent));
        // ignore: avoid_dynamic_calls
        expect(state.debugImage, isNull);

        // Now replace document & cache with doc2/cache2 before completer1 finishes
        notifier.value = (doc: doc2, cache: cache2);
        await tester.pumpAndSettle();

        // ignore: avoid_dynamic_calls
        final img2 = state.debugImage as ui.Image?;
        expect(img2, isNotNull);
        expect(img2!.debugDisposed, isFalse);

        // If completer1 now finishes late with doc1's image:
        final lateImg1 = await createTestImage();
        completer1.complete(lateImg1);
        await tester.pump();

        // Must still be displaying img2, not doc1's late image
        // ignore: avoid_dynamic_calls
        expect(state.debugImage, same(img2));
      },
    );
  });
}

class _MockPdfDocument implements PdfDocument {
  _MockPdfDocument({this.pageCount = 10, List<PdfPage>? customPages})
    : pages =
          customPages ??
          List.generate(pageCount, (index) => _MockPdfPage(index: index));

  final int pageCount;

  @override
  final List<PdfPage> pages;

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
  _MockPdfPage({required this.index, this.onRender});
  final int index;
  final Future<PdfImage?> Function(double w, double h)? onRender;

  @override
  double get width => 600.0;

  @override
  double get height => 800.0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #render) {
      if (onRender != null) {
        final named = invocation.namedArguments;
        final w = named[#fullWidth] as double? ?? 600.0;
        final h = named[#fullHeight] as double? ?? 800.0;
        return onRender!(w, h);
      }
      return Future<PdfImage?>.value(null);
    }
    return super.noSuchMethod(invocation);
  }
}

class _MockPdfImage implements PdfImage {
  bool isDisposed = false;

  @override
  void dispose() {
    isDisposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
