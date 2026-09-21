import 'package:flutter/foundation.dart';

import 'package:flip_book/src/epub/epub_document.dart';
import 'package:flip_book/src/epub/epub_pagination.dart';
import 'package:flip_book/src/epub/epub_reader_settings.dart';

/// Controls EPUB-specific concerns: typography, chapters and reading position.
///
/// Deliberately separate from `FlipBookController`, which owns page navigation
/// and flip behaviour. Typography changes re-paginate the book; the reader's
/// place is preserved across that because it is tracked as an [EpubLocator],
/// not a page number.
///
/// ```dart
/// final epub = EpubController(
///   settings: const EpubReaderSettings(fontSize: 18),
/// );
///
/// epub.zoomIn();                 // reflows: more pages, same page size
/// epub.setLineHeight(1.8);
/// epub.goToChapter(3);
/// ```
class EpubController extends ChangeNotifier {
  EpubController({EpubReaderSettings settings = const EpubReaderSettings()})
    : _settings = settings;

  EpubReaderSettings _settings;
  EpubDocument? _document;
  EpubPagination? _pagination;
  EpubLocator _locator = const EpubLocator(spineIndex: 0);
  int? _pendingSpineIndex;

  /// Current typography and layout.
  EpubReaderSettings get settings => _settings;

  /// The parsed book, once loaded.
  EpubDocument? get document => _document;

  /// Table of contents, empty until the book loads.
  List<EpubTocEntry> get toc => _document?.toc ?? const [];

  /// Current pagination, or `null` before the first layout.
  EpubPagination? get pagination => _pagination;

  /// Whether the book is loaded and paginated.
  bool get isReady => _document != null && _pagination != null;

  /// The reader's current position, stable across reflows.
  EpubLocator get locator => _locator;

  /// Index of the spine document currently being read.
  int get currentSpineIndex => _locator.spineIndex;

  /// Total pages under the current typography, or 0 before layout.
  int get totalPages => _pagination?.totalPages ?? 0;

  /// Fraction of the book read so far, 0..1.
  double get progress {
    final pagination = _pagination;
    if (pagination == null || pagination.totalPages <= 1) return 0;
    return (pagination.pageFor(_locator) / (pagination.totalPages - 1)).clamp(
      0.0,
      1.0,
    );
  }

  /// A spine jump requested but not yet applied by the widget.
  int? get pendingSpineIndex => _pendingSpineIndex;

  /// Called by the widget once it has acted on a pending jump.
  void clearPendingSpineIndex() => _pendingSpineIndex = null;

  // ── Called by the widget ──────────────────────────────────────────────────

  /// Reports the loaded document.
  void attachDocument(EpubDocument document) {
    if (identical(_document, document)) return;
    _document = document;
    _locator = const EpubLocator(spineIndex: 0);
    notifyListeners();
  }

  /// Reports the pagination produced by the latest layout.
  void attachPagination(EpubPagination pagination) {
    if (_pagination == pagination) return;
    _pagination = pagination;
    notifyListeners();
  }

  /// Reports the reader's position after a page change.
  void reportLocator(EpubLocator locator) {
    if (_locator == locator) return;
    _locator = locator;
    notifyListeners();
  }

  // ── Typography ────────────────────────────────────────────────────────────

  /// Replaces the settings wholesale, triggering a re-pagination.
  void setSettings(EpubReaderSettings settings) {
    if (_settings == settings) return;
    _settings = settings;
    notifyListeners();
  }

  /// Sets the body font size. The book re-paginates; the reader keeps their
  /// place.
  void setFontSize(double size) => setSettings(
    _settings.copyWith(
      fontSize: size.clamp(
        EpubReaderSettings.minFontSize,
        EpubReaderSettings.maxFontSize,
      ),
    ),
  );

  /// Sets the line height multiple.
  void setLineHeight(double lineHeight) =>
      setSettings(_settings.copyWith(lineHeight: lineHeight));

  /// Sets the page margin in logical pixels.
  void setMargin(double margin) =>
      setSettings(_settings.copyWith(margin: margin));

  /// Sets the colour scheme.
  void setTheme(EpubTheme theme) =>
      setSettings(_settings.copyWith(theme: theme));

  /// Increases the reading size.
  ///
  /// This is reflow, not canvas zoom: the page still fits the viewport, there
  /// is just more of them.
  void zoomIn([double step = 2.0]) => setSettings(_settings.zoomIn(step));

  /// Decreases the reading size.
  void zoomOut([double step = 2.0]) => setSettings(_settings.zoomOut(step));

  // ── Navigation ────────────────────────────────────────────────────────────

  /// Jumps to a spine document by index.
  void goToSpineIndex(int index) {
    final document = _document;
    if (document == null || document.spine.isEmpty) return;
    _pendingSpineIndex = index.clamp(0, document.spine.length - 1);
    notifyListeners();
  }

  /// Jumps to the document a table-of-contents entry points at.
  ///
  /// [tocIndex] indexes [toc]. Unresolved entries are ignored.
  void goToChapter(int tocIndex) {
    if (tocIndex < 0 || tocIndex >= toc.length) return;
    final entry = toc[tocIndex];
    if (!entry.isResolved) return;
    goToSpineIndex(entry.spineIndex);
  }

  /// Moves to the next spine document.
  void nextChapter() => goToSpineIndex(_locator.spineIndex + 1);

  /// Moves to the previous spine document.
  void previousChapter() => goToSpineIndex(_locator.spineIndex - 1);

  @override
  void dispose() {
    _pendingSpineIndex = null;
    super.dispose();
  }
}
