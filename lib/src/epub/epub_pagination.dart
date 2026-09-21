import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// A position in the book that survives re-pagination.
///
/// Deliberately **not** a page number: page numbers are invalid the moment
/// anything reflows. A locator names a spine document plus how far through it
/// the reader has got, so it can be mapped back onto whatever pagination the
/// new typography produces.
@immutable
class EpubLocator {
  const EpubLocator({required this.spineIndex, this.progress = 0.0})
    : assert(progress >= 0.0 && progress <= 1.0, 'progress must be 0..1');

  /// Which document in the reading order.
  final int spineIndex;

  /// How far through that document, from 0 (start) to 1 (end).
  final double progress;

  EpubLocator copyWith({int? spineIndex, double? progress}) => EpubLocator(
    spineIndex: spineIndex ?? this.spineIndex,
    progress: progress ?? this.progress,
  );

  @override
  bool operator ==(Object other) =>
      other is EpubLocator &&
      other.spineIndex == spineIndex &&
      (other.progress - progress).abs() < 1e-9;

  @override
  int get hashCode => Object.hash(spineIndex, progress);

  @override
  String toString() =>
      'EpubLocator(spine: $spineIndex, progress: ${progress.toStringAsFixed(3)})';
}

/// Which document a global page belongs to, and where inside it.
@immutable
class EpubPageRef {
  const EpubPageRef({
    required this.spineIndex,
    required this.pageInDocument,
    required this.pagesInDocument,
  });

  final int spineIndex;

  /// Zero-based page index within the document.
  final int pageInDocument;

  /// How many pages that document occupies.
  final int pagesInDocument;

  /// Vertical offset, in logical pixels, to translate the document by.
  double offsetFor(double pageHeight) => pageInDocument * pageHeight;
}

/// Maps measured document heights onto a flat sequence of viewport-sized pages.
///
/// This is the whole of the "zoom is reflow" rule: bigger text means a taller
/// laid-out document, which means *more pages*, never a bigger page.
@immutable
class EpubPagination {
  EpubPagination({
    required this.pageHeight,
    required Map<int, double> heights,
    required int spineLength,
  }) : assert(pageHeight > 0, 'pageHeight must be positive'),
       _spineLength = spineLength {
    var running = 0;
    for (var i = 0; i < spineLength; i++) {
      final height = heights[i];
      // A document that has not been measured yet counts as one page, so the
      // book is navigable while measurement is still catching up.
      final pages = height == null
          ? 1
          : math.max(1, (height / pageHeight).ceil());
      _pagesPerDocument.add(pages);
      _startPage.add(running);
      _measured.add(height != null);
      running += pages;
    }
    _totalPages = math.max(1, running);
  }

  /// Height of one page's content area, in logical pixels.
  final double pageHeight;

  final int _spineLength;
  final List<int> _pagesPerDocument = [];
  final List<int> _startPage = [];
  final List<bool> _measured = [];
  late final int _totalPages;

  /// Total pages across the whole book.
  int get totalPages => _totalPages;

  /// Number of documents in the reading order.
  int get spineLength => _spineLength;

  /// Whether every document has been measured.
  bool get isComplete => !_measured.contains(false);

  /// How many documents have been measured so far.
  int get measuredCount => _measured.where((m) => m).length;

  /// Pages occupied by [spineIndex].
  int pagesIn(int spineIndex) =>
      _pagesPerDocument[spineIndex.clamp(0, _spineLength - 1)];

  /// The first global page of [spineIndex].
  int startPageOf(int spineIndex) =>
      _startPage[spineIndex.clamp(0, _spineLength - 1)];

  /// Resolves a global page number to a document and offset within it.
  EpubPageRef resolve(int globalPage) {
    final page = globalPage.clamp(0, _totalPages - 1);
    // Binary search for the document whose page range contains `page`.
    var low = 0;
    var high = _spineLength - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (_startPage[mid] <= page) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return EpubPageRef(
      spineIndex: low,
      pageInDocument: page - _startPage[low],
      pagesInDocument: _pagesPerDocument[low],
    );
  }

  /// The locator for a global page, for storing a reading position.
  EpubLocator locatorAt(int globalPage) {
    final ref = resolve(globalPage);
    final progress = ref.pagesInDocument <= 1
        ? 0.0
        : ref.pageInDocument / ref.pagesInDocument;
    return EpubLocator(
      spineIndex: ref.spineIndex,
      progress: progress.clamp(0.0, 1.0),
    );
  }

  /// The global page that best matches [locator] under this pagination.
  ///
  /// This is what restores the reader's place after a font-size, margin or
  /// orientation change.
  int pageFor(EpubLocator locator) {
    final spine = locator.spineIndex.clamp(0, _spineLength - 1);
    final pages = _pagesPerDocument[spine];
    final within = (locator.progress * pages).floor().clamp(0, pages - 1);
    return (_startPage[spine] + within).clamp(0, _totalPages - 1);
  }

  @override
  bool operator ==(Object other) =>
      other is EpubPagination &&
      other.pageHeight == pageHeight &&
      other._totalPages == _totalPages &&
      listEquals(other._pagesPerDocument, _pagesPerDocument);

  @override
  int get hashCode => Object.hash(pageHeight, _totalPages, _spineLength);

  @override
  String toString() =>
      'EpubPagination($_totalPages pages across '
      '$_spineLength documents, measured $measuredCount)';
}
