import 'dart:async';

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
  });
}
