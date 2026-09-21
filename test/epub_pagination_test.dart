import 'package:flutter_test/flutter_test.dart';

import 'package:flip_book/flip_book.dart';

/// Heights for a 3-document book at a given font scale.
Map<int, double> _heights(double scale) => {
  0: 1000 * scale,
  1: 2500 * scale,
  2: 400 * scale,
};

EpubPagination _paginate({
  double pageHeight = 500,
  double scale = 1.0,
  int spineLength = 3,
}) => EpubPagination(
  pageHeight: pageHeight,
  heights: _heights(scale),
  spineLength: spineLength,
);

void main() {
  group('EpubPagination layout', () {
    test('splits documents into viewport-sized pages', () {
      final p = _paginate();
      // 1000/500 = 2, 2500/500 = 5, 400/500 -> 1
      expect(p.pagesIn(0), 2);
      expect(p.pagesIn(1), 5);
      expect(p.pagesIn(2), 1);
      expect(p.totalPages, 8);
    });

    test('start pages are cumulative', () {
      final p = _paginate();
      expect(p.startPageOf(0), 0);
      expect(p.startPageOf(1), 2);
      expect(p.startPageOf(2), 7);
    });

    test('resolves every global page to the right document', () {
      final p = _paginate();
      expect(p.resolve(0).spineIndex, 0);
      expect(p.resolve(1).spineIndex, 0);
      expect(p.resolve(2).spineIndex, 1);
      expect(p.resolve(6).spineIndex, 1);
      expect(p.resolve(7).spineIndex, 2);

      expect(p.resolve(0).pageInDocument, 0);
      expect(p.resolve(1).pageInDocument, 1);
      expect(p.resolve(2).pageInDocument, 0);
      expect(p.resolve(6).pageInDocument, 4);
    });

    test('clamps out-of-range pages', () {
      final p = _paginate();
      expect(p.resolve(-5).spineIndex, 0);
      expect(p.resolve(999).spineIndex, 2);
    });

    test('a document shorter than a page still occupies one page', () {
      final p = EpubPagination(
        pageHeight: 500,
        heights: const {0: 10},
        spineLength: 1,
      );
      expect(p.pagesIn(0), 1);
      expect(p.totalPages, 1);
    });

    test('unmeasured documents count as one page and are reported', () {
      final p = EpubPagination(
        pageHeight: 500,
        heights: const {0: 1000},
        spineLength: 3,
      );
      expect(p.isComplete, isFalse);
      expect(p.measuredCount, 1);
      expect(p.totalPages, 2 + 1 + 1);
    });

    test('page offsets translate the document correctly', () {
      final p = _paginate();
      final ref = p.resolve(6); // document 1, page 4
      expect(ref.offsetFor(500), 2000);
    });
  });

  group('EpubPagination reflow', () {
    test('larger text produces more pages, never a larger page', () {
      final small = _paginate();
      final large = _paginate(scale: 1.6);

      expect(large.totalPages, greaterThan(small.totalPages));
      // The page height -- the viewport -- is unchanged. This is the rule:
      // zoom is reflow, not scaling.
      expect(large.pageHeight, small.pageHeight);
    });

    test('reading position survives a font-size increase', () {
      final small = _paginate();
      // Reader is on global page 4: document 1, part-way through.
      final locator = small.locatorAt(4);
      expect(locator.spineIndex, 1);

      final large = _paginate(scale: 1.6);
      final restored = large.pageFor(locator);

      // Still in the same document, and at a comparable depth through it.
      final ref = large.resolve(restored);
      expect(ref.spineIndex, 1);
      final before = small.resolve(4).pageInDocument / small.pagesIn(1);
      final after = ref.pageInDocument / large.pagesIn(1);
      expect((after - before).abs(), lessThan(0.25));
    });

    test('position survives a round trip back to the original size', () {
      final small = _paginate();
      const originalPage = 5;
      final locator = small.locatorAt(originalPage);

      final large = _paginate(scale: 2.0);
      final atLarge = large.pageFor(locator);
      final backLocator = large.locatorAt(atLarge);
      final back = small.pageFor(backLocator);

      expect(
        small.resolve(back).spineIndex,
        small.resolve(originalPage).spineIndex,
      );
      expect((back - originalPage).abs(), lessThanOrEqualTo(1));
    });

    test('position survives an orientation change (shorter page)', () {
      final portrait = _paginate(pageHeight: 800);
      final locator = portrait.locatorAt(portrait.totalPages - 1);

      final landscape = _paginate(pageHeight: 300);
      final restored = landscape.pageFor(locator);

      expect(landscape.resolve(restored).spineIndex, locator.spineIndex);
    });

    test('the first page maps to the first page at any size', () {
      final small = _paginate();
      final locator = small.locatorAt(0);
      expect(locator.spineIndex, 0);
      expect(locator.progress, 0.0);
      expect(_paginate(scale: 3.0).pageFor(locator), 0);
    });

    test('a locator is never a page number', () {
      final p = _paginate();
      final a = p.locatorAt(3);
      final b = p.locatorAt(4);
      // Both are in document 1 but at different depths.
      expect(a.spineIndex, b.spineIndex);
      expect(a.progress, lessThan(b.progress));
    });
  });

  group('EpubLocator', () {
    test('compares by value', () {
      expect(
        const EpubLocator(spineIndex: 2, progress: 0.5),
        const EpubLocator(spineIndex: 2, progress: 0.5),
      );
      expect(
        const EpubLocator(spineIndex: 2, progress: 0.5),
        isNot(const EpubLocator(spineIndex: 3, progress: 0.5)),
      );
    });

    test('rejects out-of-range progress', () {
      expect(
        () => EpubLocator(spineIndex: 0, progress: 1.5),
        throwsAssertionError,
      );
    });
  });

  group('EpubReaderSettings', () {
    test('zoom steps are clamped', () {
      const s = EpubReaderSettings(fontSize: EpubReaderSettings.maxFontSize);
      expect(s.zoomIn().fontSize, EpubReaderSettings.maxFontSize);
      const t = EpubReaderSettings(fontSize: EpubReaderSettings.minFontSize);
      expect(t.zoomOut().fontSize, EpubReaderSettings.minFontSize);
    });

    test('zoom changes only the font size', () {
      const s = EpubReaderSettings(fontSize: 16, lineHeight: 1.8, margin: 30);
      final z = s.zoomIn();
      expect(z.fontSize, 18);
      expect(z.lineHeight, 1.8);
      expect(z.margin, 30);
    });

    test('compares by value', () {
      expect(const EpubReaderSettings(), const EpubReaderSettings());
      expect(
        const EpubReaderSettings(fontSize: 16),
        isNot(const EpubReaderSettings(fontSize: 18)),
      );
    });

    test('rejects invalid values', () {
      expect(() => EpubReaderSettings(fontSize: 0), throwsAssertionError);
      expect(() => EpubReaderSettings(lineHeight: 0), throwsAssertionError);
      expect(() => EpubReaderSettings(margin: -1), throwsAssertionError);
    });
  });
}
