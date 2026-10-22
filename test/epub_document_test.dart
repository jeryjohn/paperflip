import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:paperflip/paperflip.dart';

/// Real Gutenberg EPUBs, fetched once into the scratchpad by tool/fetch_books.sh.
/// These tests skip when the fixtures are absent so CI without network passes.
const _fixtureDir = String.fromEnvironment(
  'EPUB_FIXTURES',
  defaultValue: 'test/fixtures',
);

final _books = <String, String>{
  'Alice in Wonderland (Tenniel)': 'pg19033.epub',
  'Alice Under Ground (facsimile)': 'pg19002.epub',
  'Alice in Wonderland (Rackham)': 'pg28885.epub',
};

Uint8List? _read(String name) {
  final file = File('$_fixtureDir/$name');
  if (!file.existsSync()) return null;
  return file.readAsBytesSync();
}

void main() {
  group('EpubSource', () {
    test('sources compare by value', () {
      expect(
        const EpubSource.network('https://example.com/a.epub'),
        const EpubSource.network('https://example.com/a.epub'),
      );
      expect(
        const EpubSource.network('https://example.com/a.epub'),
        isNot(const EpubSource.network('https://example.com/b.epub')),
      );
      expect(
        const EpubSource.file('/tmp/a.epub'),
        isNot(const EpubSource.network('/tmp/a.epub')),
        reason: 'different kinds with the same string are not equal',
      );
    });

    test('cache keys are namespaced per kind', () {
      expect(
        const EpubSource.network('x').cacheKey,
        isNot(const EpubSource.asset('x').cacheKey),
      );
    });

    test('network sources with equivalent headers are equal', () {
      const s1 = EpubSource.network(
        'https://example.com/book.epub',
        headers: {
          'Authorization': 'Bearer token123',
          'Accept': 'application/epub+zip',
        },
      );
      const s2 = EpubSource.network(
        'https://example.com/book.epub',
        headers: {
          'Accept': 'application/epub+zip',
          'Authorization': 'Bearer token123',
        },
      );
      expect(s1, equals(s2));
      expect(s1.cacheKey, equals(s2.cacheKey));
      expect(s1.hashCode, equals(s2.hashCode));
    });

    test('network sources with different headers have distinct identity', () {
      const s1 = EpubSource.network(
        'https://example.com/book.epub',
        headers: {'Authorization': 'Bearer token1'},
      );
      const s2 = EpubSource.network(
        'https://example.com/book.epub',
        headers: {'Authorization': 'Bearer token2'},
      );
      expect(s1, isNot(equals(s2)));
      expect(s1.cacheKey, isNot(equals(s2.cacheKey)));
    });

    test(
      'network sources never expose sensitive headers in cacheKey or toString',
      () {
        const secret = 'super-secret-auth-token-xyz';
        const s = EpubSource.network(
          'https://example.com/book.epub',
          headers: {'Authorization': 'Bearer $secret'},
        );
        expect(s.cacheKey, isNot(contains(secret)));
        expect(s.displayName, isNot(contains(secret)));
        expect(s.toString(), isNot(contains(secret)));
      },
    );

    test('network source caller-supplied id takes precedence', () {
      const s1 = EpubSource.network(
        'https://example.com/book.epub',
        id: 'revision-1',
      );
      const s2 = EpubSource.network(
        'https://example.com/book.epub',
        id: 'revision-2',
      );
      expect(s1, isNot(equals(s2)));
      expect(s1.cacheKey, contains('revision-1'));
      expect(s2.cacheKey, contains('revision-2'));
    });

    test(
      'in-memory data sources compare by value and detect content changes',
      () {
        final bytesA1 = Uint8List.fromList([1, 2, 3, 4, 5]);
        final bytesA2 = Uint8List.fromList([1, 2, 3, 4, 5]);
        final bytesB = Uint8List.fromList([1, 2, 9, 4, 5]);

        final sA1 = EpubSource.data(bytesA1);
        final sA2 = EpubSource.data(bytesA2);
        final sB = EpubSource.data(bytesB);

        // Equivalent bytes produce the same identity and are equal
        expect(sA1, equals(sA2));
        expect(sA1.cacheKey, equals(sA2.cacheKey));

        // Changed bytes produce a different identity
        expect(sA1, isNot(equals(sB)));
        expect(sA1.cacheKey, isNot(equals(sB.cacheKey)));
      },
    );

    test('in-memory data sources support explicit caller-supplied id', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final s1 = EpubSource.data(bytes, id: 'doc-v1');
      final s2 = EpubSource.data(bytes, id: 'doc-v2');

      expect(s1, isNot(equals(s2)));
      expect(s1.cacheKey, contains('doc-v1'));
      expect(s2.cacheKey, contains('doc-v2'));
    });

    test('a missing file reports a useful error', () async {
      await expectLater(
        const EpubSource.file('/definitely/not/here.epub').load(),
        throwsA(isA<EpubLoadException>()),
      );
    });
  });

  group('EpubDocument', () {
    for (final entry in _books.entries) {
      final label = entry.key;
      final filename = entry.value;

      test('$label: spine is reading order, not the TOC', () async {
        final bytes = _read(filename);
        if (bytes == null) {
          markTestSkipped('fixture $filename not present');
          return;
        }

        final doc = await EpubDocument.open(EpubSource.data(bytes));

        expect(doc.spine, isNotEmpty);
        expect(doc.title, isNotEmpty);

        // The whole point: each spine entry is a distinct document. The NCX
        // TOC repeats the same file across several entries, so paginating off
        // it would render the same text more than once.
        final hrefs = doc.spine.map((s) => s.href).toList();
        expect(
          hrefs.toSet().length,
          hrefs.length,
          reason: 'spine hrefs must be unique',
        );

        final htmls = doc.spine.map((s) => s.html).toList();
        expect(
          htmls.toSet().length,
          greaterThan(1),
          reason: 'spine documents must not all be the same content',
        );

        // Indices are contiguous and ordered.
        for (var i = 0; i < doc.spine.length; i++) {
          expect(doc.spine[i].index, i);
        }
      });

      test('$label: exposes a table of contents', () async {
        final bytes = _read(filename);
        if (bytes == null) {
          markTestSkipped('fixture $filename not present');
          return;
        }

        final doc = await EpubDocument.open(EpubSource.data(bytes));

        expect(doc.toc, isNotEmpty);
        // Most entries should resolve to a real spine document.
        final resolved = doc.toc.where((e) => e.isResolved).length;
        expect(
          resolved,
          greaterThan(0),
          reason: 'no TOC entry resolved to a spine index',
        );
        for (final entry in doc.toc) {
          expect(entry.title.trim(), entry.title);
          expect(entry.title, isNotEmpty);
          if (entry.isResolved) {
            expect(entry.spineIndex, lessThan(doc.spine.length));
          }
        }
      });

      test('$label: resolves images referenced by the markup', () async {
        final bytes = _read(filename);
        if (bytes == null) {
          markTestSkipped('fixture $filename not present');
          return;
        }

        final doc = await EpubDocument.open(EpubSource.data(bytes));

        // Collect every <img src> across the book and check we can resolve it.
        final srcPattern = RegExp(r'''<img[^>]+src=["']([^"']+)["']''');
        var total = 0;
        var resolved = 0;
        for (final item in doc.spine) {
          for (final match in srcPattern.allMatches(item.html)) {
            total++;
            if (doc.imageFor(match.group(1)!, fromHref: item.href) != null) {
              resolved++;
            }
          }
        }

        if (total == 0) {
          markTestSkipped('no images referenced');
          return;
        }
        expect(
          resolved,
          total,
          reason: 'unresolved image references: ${total - resolved} of $total',
        );
      });
    }

    test('rejects bytes that are not an EPUB', () async {
      final garbage = Uint8List.fromList(List<int>.filled(64, 0x41));
      await expectLater(
        EpubDocument.open(EpubSource.data(garbage)),
        throwsA(isA<EpubLoadException>()),
      );
    });

    test(
      'image resolution rejects external network URLs and data URIs',
      () async {
        final bytes = _read('pg28885.epub');
        if (bytes == null) {
          markTestSkipped('fixture pg28885.epub not present');
          return;
        }
        final doc = await EpubDocument.open(EpubSource.data(bytes));

        // External HTTP/HTTPS
        expect(doc.imageFor('https://example.com/image.jpg'), isNull);
        expect(doc.imageFor('http://example.com/image.jpg'), isNull);
        expect(doc.imageFor('//example.com/image.jpg'), isNull);

        // Data URIs
        expect(
          doc.imageFor(
            'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
          ),
          isNull,
        );

        // Missing resource
        expect(doc.imageFor('non_existent_image_12345.jpg'), isNull);

        // Relative path with query / fragment strips and resolves
        final known = doc.spine.firstWhere((s) => s.html.contains('<img'));
        final match = RegExp(
          r'''<img[^>]+src=["']([^"']+)["']''',
        ).firstMatch(known.html);
        if (match != null) {
          final rawSrc = match.group(1)!;
          final normal = doc.imageFor(rawSrc, fromHref: known.href);
          expect(normal, isNotNull);

          // With fragment attached
          final withFragment = doc.imageFor(
            '$rawSrc#xywh=0,0,10,10',
            fromHref: known.href,
          );
          expect(withFragment, isNotNull);
          expect(withFragment, equals(normal));

          // With query param attached
          final withQuery = doc.imageFor('$rawSrc?v=123', fromHref: known.href);
          expect(withQuery, isNotNull);
          expect(withQuery, equals(normal));
        }
      },
    );
  });
}
