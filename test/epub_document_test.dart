import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flip_book/flip_book.dart';

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
  });
}
