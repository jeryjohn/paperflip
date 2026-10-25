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
        EpubSource.network('https://example.com/a.epub'),
        EpubSource.network('https://example.com/a.epub'),
      );
      expect(
        EpubSource.network('https://example.com/a.epub'),
        isNot(EpubSource.network('https://example.com/b.epub')),
      );
      expect(
        const EpubSource.file('/tmp/a.epub'),
        isNot(EpubSource.network('/tmp/a.epub')),
        reason: 'different kinds with the same string are not equal',
      );
    });

    test('cache keys are namespaced per kind', () {
      expect(
        EpubSource.network('x').cacheKey,
        isNot(const EpubSource.asset('x').cacheKey),
      );
    });

    test('network sources with equivalent headers are equal', () {
      final s1 = EpubSource.network(
        'https://example.com/book.epub',
        headers: const {
          'Authorization': 'Bearer token123',
          'Accept': 'application/epub+zip',
        },
      );
      final s2 = EpubSource.network(
        'https://example.com/book.epub',
        headers: const {
          'Accept': 'application/epub+zip',
          'Authorization': 'Bearer token123',
        },
      );
      expect(s1, equals(s2));
      expect(s1.cacheKey, equals(s2.cacheKey));
      expect(s1.hashCode, equals(s2.hashCode));
    });

    test('network sources with different headers have distinct identity', () {
      final s1 = EpubSource.network(
        'https://example.com/book.epub',
        headers: const {'Authorization': 'Bearer token1'},
      );
      final s2 = EpubSource.network(
        'https://example.com/book.epub',
        headers: const {'Authorization': 'Bearer token2'},
      );
      expect(s1, isNot(equals(s2)));
      expect(s1.cacheKey, isNot(equals(s2.cacheKey)));
    });

    test(
      'network sources never expose sensitive headers in cacheKey or toString',
      () {
        const secret = 'super-secret-auth-token-xyz';
        final s = EpubSource.network(
          'https://example.com/book.epub',
          headers: const {'Authorization': 'Bearer $secret'},
        );
        expect(s.cacheKey, isNot(contains(secret)));
        expect(s.displayName, isNot(contains(secret)));
        expect(s.toString(), isNot(contains(secret)));
      },
    );

    test('network source caller-supplied id takes precedence', () {
      final s1 = EpubSource.network(
        'https://example.com/book.epub',
        id: 'revision-1',
      );
      final s2 = EpubSource.network(
        'https://example.com/book.epub',
        id: 'revision-2',
      );
      expect(s1, isNot(equals(s2)));
      expect(s1.cacheKey, contains('revision-1'));
      expect(s2.cacheKey, contains('revision-2'));
    });

    test(
      'mutating caller headers map after construction does not alter identity',
      () {
        final mutableHeaders = <String, String>{
          'Authorization': 'Bearer initial',
        };
        final source = EpubSource.network(
          'https://example.com/book.epub',
          headers: mutableHeaders,
        );
        final initialKey = source.cacheKey;
        final initialHash = source.hashCode;

        mutableHeaders['Authorization'] = 'Bearer mutated';
        mutableHeaders['Extra'] = 'value';

        expect(source.cacheKey, equals(initialKey));
        expect(source.hashCode, equals(initialHash));
      },
    );

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

    test(
      'detects content changes in middle regions that were previously unsampled',
      () {
        final bytesA = Uint8List(8192);
        bytesA[0] = 1;
        final bytesB = Uint8List(8192);
        bytesB[0] = 1;
        // Offset 2048 was between the first 1024 bytes and the middle sample in the old code
        bytesB[2048] = 42;

        final sourceA = EpubSource.data(bytesA);
        final sourceB = EpubSource.data(bytesB);

        expect(sourceA, isNot(equals(sourceB)));
        expect(sourceA.cacheKey, isNot(equals(sourceB.cacheKey)));
        expect(sourceA.hashCode, isNot(equals(sourceB.hashCode)));
      },
    );

    test(
      'mutating input byte array after construction does not alter stored source or identity',
      () async {
        final rawBytes = Uint8List.fromList([10, 20, 30, 40]);
        final source = EpubSource.data(rawBytes);
        final expectedKey = source.cacheKey;

        rawBytes[0] = 99;
        rawBytes[1] = 88;

        expect(source.cacheKey, equals(expectedKey));
        final loaded = await source.load();
        expect(loaded[0], 10);
        expect(loaded[1], 20);
      },
    );

    test(
      'mutating data returned from load or bytes getter does not alter stored source',
      () async {
        final source = EpubSource.data(Uint8List.fromList([1, 2, 3]));
        final loaded = await source.load();
        loaded[0] = 99;

        final loadedAgain = await source.load();
        expect(loadedAgain[0], 1);

        if (source is EpubDataSource) {
          final exposed = source.bytes;
          exposed[0] = 77;
          final loadedThird = await source.load();
          expect(loadedThird[0], 1);
        }
      },
    );

    test(
      'handles empty input and realistically large inputs efficiently',
      () async {
        final emptySource = EpubSource.data(Uint8List(0));
        expect(emptySource.cacheKey, contains('0_'));

        // 500 KB test payload
        final largeBytes = Uint8List(500 * 1024);
        largeBytes[250 * 1024] = 0xAA;
        final stopwatch = Stopwatch()..start();
        final largeSource = EpubSource.data(largeBytes);
        stopwatch.stop();

        expect(largeSource.cacheKey, contains('${500 * 1024}_'));
        // Hashing 500 KB should complete in well under 200 ms without BigInt allocation overhead
        expect(stopwatch.elapsedMilliseconds, lessThan(200));
      },
    );

    test(
      'regression: produces deterministic repeatable digests for known content bytes',
      () {
        final empty = EpubSource.data(Uint8List(0));
        expect(empty.cacheKey, equals('data:memory:0_050c5d1f26bd533f'));

        final sample = EpubSource.data(Uint8List.fromList([1, 2, 3, 4, 5]));
        expect(sample.cacheKey, equals('data:memory:5_106e446b2b4def4a'));

        final pattern = Uint8List(300);
        for (var i = 0; i < pattern.length; i++) {
          pattern[i] = (i * 31 + 7) & 0xFF;
        }
        final patternSource = EpubSource.data(pattern);
        expect(
          patternSource.cacheKey,
          equals('data:memory:300_5886c93f0439e5e0'),
        );
        // Ensure repeated calls produce the exact same digest
        expect(
          EpubSource.data(pattern).cacheKey,
          equals(patternSource.cacheKey),
        );
      },
    );

    test(
      'regression: changed input bytes in any position alter the digest',
      () {
        final baseBytes = Uint8List.fromList([10, 20, 30, 40, 50, 60]);
        final baseKey = EpubSource.data(baseBytes).cacheKey;

        // First byte changed
        final startChanged = Uint8List.fromList([11, 20, 30, 40, 50, 60]);
        expect(EpubSource.data(startChanged).cacheKey, isNot(equals(baseKey)));

        // Middle byte changed
        final midChanged = Uint8List.fromList([10, 20, 31, 40, 50, 60]);
        expect(EpubSource.data(midChanged).cacheKey, isNot(equals(baseKey)));

        // Last byte changed
        final endChanged = Uint8List.fromList([10, 20, 30, 40, 50, 61]);
        expect(EpubSource.data(endChanged).cacheKey, isNot(equals(baseKey)));

        // Single bit flip
        final bitFlipped = Uint8List.fromList([10, 20, 30, 40 ^ 0x01, 50, 60]);
        expect(EpubSource.data(bitFlipped).cacheKey, isNot(equals(baseKey)));

        // Truncated length
        final truncated = Uint8List.fromList([10, 20, 30, 40, 50]);
        expect(EpubSource.data(truncated).cacheKey, isNot(equals(baseKey)));

        // Appended byte
        final appended = Uint8List.fromList([10, 20, 30, 40, 50, 60, 70]);
        expect(EpubSource.data(appended).cacheKey, isNot(equals(baseKey)));
      },
    );

    test(
      'regression: produces deterministic repeatable digests for network headers',
      () {
        final s = EpubSource.network(
          'https://example.com/test.epub',
          headers: const {
            'Authorization': 'Bearer 12345',
            'Accept': 'application/epub+zip',
          },
        );
        expect(
          s.cacheKey,
          equals('network:https://example.com/test.epub#278cf6ed3633e672'),
        );

        // Header case variation maintains determinism
        final sCase = EpubSource.network(
          'https://example.com/test.epub',
          headers: const {
            'authorization': 'Bearer 12345',
            'ACCEPT': 'application/epub+zip',
          },
        );
        expect(sCase.cacheKey, equals(s.cacheKey));
      },
    );

    test('regression: changed network headers alter the digest', () {
      const url = 'https://example.com/test.epub';
      final base = EpubSource.network(
        url,
        headers: const {'Authorization': 'Bearer 12345', 'X-Version': '1'},
      );
      final baseKey = base.cacheKey;

      // Changed value
      final valueChanged = EpubSource.network(
        url,
        headers: const {'Authorization': 'Bearer 12346', 'X-Version': '1'},
      );
      expect(valueChanged.cacheKey, isNot(equals(baseKey)));

      // Changed key
      final keyChanged = EpubSource.network(
        url,
        headers: const {'Auth': 'Bearer 12345', 'X-Version': '1'},
      );
      expect(keyChanged.cacheKey, isNot(equals(baseKey)));

      // Added header
      final added = EpubSource.network(
        url,
        headers: const {
          'Authorization': 'Bearer 12345',
          'X-Version': '1',
          'X-Extra': 'true',
        },
      );
      expect(added.cacheKey, isNot(equals(baseKey)));

      // Removed header
      final removed = EpubSource.network(
        url,
        headers: const {'Authorization': 'Bearer 12345'},
      );
      expect(removed.cacheKey, isNot(equals(baseKey)));
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
