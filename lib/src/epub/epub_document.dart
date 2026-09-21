import 'dart:async';

import 'package:epub_plus/epub_plus.dart' as ep;
import 'package:flutter/foundation.dart';

import 'package:flip_book/src/epub/epub_source.dart';

/// One document in the book's reading order.
///
/// This is a **spine** item, not a table-of-contents entry. The two are not the
/// same: a TOC entry is a labelled anchor that may point into the middle of a
/// spine document, and several TOC entries commonly share one document.
@immutable
class EpubSpineItem {
  const EpubSpineItem({
    required this.index,
    required this.href,
    required this.html,
  });

  /// Position in the reading order.
  final int index;

  /// The document's path inside the archive.
  final String href;

  /// Raw XHTML for this document.
  final String html;
}

/// A table-of-contents entry.
@immutable
class EpubTocEntry {
  const EpubTocEntry({
    required this.title,
    required this.spineIndex,
    required this.depth,
    this.anchor,
  });

  /// Label shown to the reader.
  final String title;

  /// Which spine document this entry points at, or `-1` when it could not be
  /// resolved.
  final int spineIndex;

  /// Nesting level, 0 for top-level entries.
  final int depth;

  /// Optional fragment identifier within the document.
  final String? anchor;

  bool get isResolved => spineIndex >= 0;
}

/// A parsed EPUB: metadata, reading order, table of contents and resources.
///
/// This wraps the underlying parser so the rest of the package never depends on
/// it directly — the engine is meant to stay swappable.
class EpubDocument {
  EpubDocument._({
    required this.title,
    required this.author,
    required this.spine,
    required this.toc,
    required Map<String, Uint8List> images,
    required this.coverImage,
  }) : _images = images;

  /// Book title, or the source name when the EPUB omits one.
  final String title;

  /// Book author, empty when unknown.
  final String author;

  /// Documents in reading order.
  final List<EpubSpineItem> spine;

  /// Flattened table of contents.
  final List<EpubTocEntry> toc;

  /// Cover image bytes, when the book has one.
  final Uint8List? coverImage;

  final Map<String, Uint8List> _images;

  /// Opens and parses [source].
  ///
  /// Parsing happens on a background isolate where the platform supports it,
  /// since a large EPUB takes a noticeable amount of time to unzip.
  static Future<EpubDocument> open(EpubSource source) async {
    final Uint8List bytes;
    try {
      bytes = await source.load();
    } on EpubLoadException {
      rethrow;
    } catch (e) {
      throw EpubLoadException('Could not read ${source.displayName}: $e');
    }

    final ep.EpubBook book;
    try {
      book = await ep.EpubReader.readBook(bytes);
    } catch (e) {
      throw EpubLoadException(
        'Not a readable EPUB (${source.displayName}): $e',
      );
    }

    return _fromBook(book, fallbackTitle: source.displayName);
  }

  static EpubDocument _fromBook(
    ep.EpubBook book, {
    required String fallbackTitle,
  }) {
    final htmlFiles = book.content?.html ?? const {};

    // Reading order comes from the spine: manifest id -> href -> content.
    // book.chapters is the NCX table of contents, where several entries can
    // share one document, so it must not be used to segment content.
    final manifestItems =
        book.schema?.package?.manifest?.items ?? const <ep.EpubManifestItem>[];
    final manifest = <String, String>{};
    for (final item in manifestItems) {
      final id = item.id;
      final href = item.href;
      if (id != null && href != null) manifest[id] = href;
    }

    final spine = <EpubSpineItem>[];
    final hrefToSpineIndex = <String, int>{};
    final spineRefs =
        book.schema?.package?.spine?.items ?? const <ep.EpubSpineItemRef>[];
    for (final ref in spineRefs) {
      final href = manifest[ref.idRef];
      if (href == null) continue;
      final content = htmlFiles[href]?.content;
      if (content == null || content.trim().isEmpty) continue;
      hrefToSpineIndex[href] = spine.length;
      hrefToSpineIndex[_basename(href)] = spine.length;
      spine.add(EpubSpineItem(index: spine.length, href: href, html: content));
    }

    // Fall back to manifest order if the spine was unusable, so a malformed
    // book still renders something rather than throwing.
    if (spine.isEmpty) {
      for (final entry in htmlFiles.entries) {
        final content = entry.value.content;
        if (content == null || content.trim().isEmpty) continue;
        hrefToSpineIndex[entry.key] = spine.length;
        hrefToSpineIndex[_basename(entry.key)] = spine.length;
        spine.add(
          EpubSpineItem(index: spine.length, href: entry.key, html: content),
        );
      }
    }

    final toc = <EpubTocEntry>[];
    void walk(List<ep.EpubChapter> chapters, int depth) {
      for (final chapter in chapters) {
        final file = chapter.contentFileName;
        final index = file == null
            ? -1
            : hrefToSpineIndex[file] ?? hrefToSpineIndex[_basename(file)] ?? -1;
        final title = (chapter.title ?? '').trim();
        if (title.isNotEmpty) {
          toc.add(
            EpubTocEntry(
              title: _collapseWhitespace(title),
              spineIndex: index,
              depth: depth,
              anchor: chapter.anchor,
            ),
          );
        }
        walk(chapter.subChapters, depth + 1);
      }
    }

    walk(book.chapters, 0);

    final images = <String, Uint8List>{};
    for (final entry in (book.content?.images ?? const {}).entries) {
      final data = entry.value.content;
      if (data == null) continue;
      final bytes = Uint8List.fromList(data);
      images[entry.key] = bytes;
      images[_basename(entry.key)] = bytes;
    }

    Uint8List? cover;
    for (final item in manifestItems) {
      final href = item.href;
      if (href == null) continue;
      final isCover =
          (item.id ?? '').toLowerCase().contains('cover') ||
          (item.properties ?? '').contains('cover-image');
      if (!isCover) continue;
      cover = images[href] ?? images[_basename(href)];
      if (cover != null) break;
    }
    cover ??= images.entries
        .where((e) => e.key.toLowerCase().contains('cover'))
        .map((e) => e.value)
        .firstOrNull;

    final title = (book.title ?? '').trim();
    return EpubDocument._(
      title: title.isEmpty ? fallbackTitle : _collapseWhitespace(title),
      author: (book.author ?? '').trim(),
      spine: spine,
      toc: toc,
      images: images,
      coverImage: cover,
    );
  }

  /// Bytes for an image referenced from the book's HTML, or `null`.
  ///
  /// Resolves against the referencing document so relative paths such as
  /// `../images/plate.jpg` work, and falls back to a basename match for books
  /// whose manifest paths do not line up with their markup.
  Uint8List? imageFor(String src, {String? fromHref}) {
    final cleaned = _stripQuery(Uri.decodeFull(src));
    final direct = _images[cleaned];
    if (direct != null) return direct;

    if (fromHref != null) {
      final base = _dirname(fromHref);
      final joined = _normalize(base.isEmpty ? cleaned : '$base/$cleaned');
      final resolved = _images[joined];
      if (resolved != null) return resolved;
    }

    return _images[_basename(cleaned)];
  }

  /// Number of documents in the reading order.
  int get spineLength => spine.length;

  static String _basename(String path) {
    final i = path.lastIndexOf('/');
    return i == -1 ? path : path.substring(i + 1);
  }

  static String _dirname(String path) {
    final i = path.lastIndexOf('/');
    return i == -1 ? '' : path.substring(0, i);
  }

  static String _stripQuery(String path) {
    final q = path.indexOf('?');
    return q == -1 ? path : path.substring(0, q);
  }

  /// Resolves `.` and `..` segments in a archive-relative path.
  static String _normalize(String path) {
    final parts = <String>[];
    for (final segment in path.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(segment);
    }
    return parts.join('/');
  }

  static String _collapseWhitespace(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();
}
