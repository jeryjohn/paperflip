import 'package:flutter/widgets.dart';

/// Colour scheme for EPUB text.
enum EpubTheme {
  /// Dark text on white.
  light,

  /// Warm dark text on a cream background.
  sepia,

  /// Light text on near-black.
  dark;

  /// Background behind the page content.
  Color get background => switch (this) {
    EpubTheme.light => const Color(0xFFFFFFFF),
    EpubTheme.sepia => const Color(0xFFFBF0D9),
    EpubTheme.dark => const Color(0xFF121212),
  };

  /// Body text colour.
  Color get foreground => switch (this) {
    EpubTheme.light => const Color(0xFF1A1A1A),
    EpubTheme.sepia => const Color(0xFF5B4636),
    EpubTheme.dark => const Color(0xFFE0E0E0),
  };
}

/// How EPUB content is laid out.
enum EpubReadingMode {
  /// Content is split into viewport-sized pages and turned with the page-flip
  /// engine.
  paginated,
}

/// Typography and layout for the EPUB reader.
///
/// Changing any of these re-paginates the book. The page always fits the
/// viewport — a larger [fontSize] produces *more pages*, never a bigger page
/// the reader has to pan around.
///
/// ```dart
/// FlipBook.epub(
///   source: EpubSource.network('https://example.com/book.epub'),
///   reader: const EpubReaderSettings(fontSize: 18, lineHeight: 1.5),
/// )
/// ```
@immutable
class EpubReaderSettings {
  const EpubReaderSettings({
    this.fontSize = 16.0,
    this.lineHeight = 1.5,
    this.margin = 20.0,
    this.theme = EpubTheme.light,
    this.readingMode = EpubReadingMode.paginated,
    this.fontFamily,
  }) : assert(fontSize > 0, 'fontSize must be positive'),
       assert(lineHeight > 0, 'lineHeight must be positive'),
       assert(margin >= 0, 'margin cannot be negative');

  /// Base body font size in logical pixels.
  final double fontSize;

  /// Line height as a multiple of [fontSize].
  final double lineHeight;

  /// Padding between the page edge and the text, in logical pixels.
  final double margin;

  /// Colour scheme.
  final EpubTheme theme;

  /// Layout mode. Only [EpubReadingMode.paginated] is implemented.
  final EpubReadingMode readingMode;

  /// Optional font family override for body text.
  final String? fontFamily;

  /// Smallest font size [zoomOut] will go to.
  static const double minFontSize = 10.0;

  /// Largest font size [zoomIn] will go to.
  static const double maxFontSize = 40.0;

  /// Returns a copy one step larger, clamped to [maxFontSize].
  EpubReaderSettings zoomIn([double step = 2.0]) =>
      copyWith(fontSize: (fontSize + step).clamp(minFontSize, maxFontSize));

  /// Returns a copy one step smaller, clamped to [minFontSize].
  EpubReaderSettings zoomOut([double step = 2.0]) =>
      copyWith(fontSize: (fontSize - step).clamp(minFontSize, maxFontSize));

  EpubReaderSettings copyWith({
    double? fontSize,
    double? lineHeight,
    double? margin,
    EpubTheme? theme,
    EpubReadingMode? readingMode,
    String? fontFamily,
  }) {
    return EpubReaderSettings(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      margin: margin ?? this.margin,
      theme: theme ?? this.theme,
      readingMode: readingMode ?? this.readingMode,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EpubReaderSettings &&
        other.fontSize == fontSize &&
        other.lineHeight == lineHeight &&
        other.margin == margin &&
        other.theme == theme &&
        other.readingMode == readingMode &&
        other.fontFamily == fontFamily;
  }

  @override
  int get hashCode =>
      Object.hash(fontSize, lineHeight, margin, theme, readingMode, fontFamily);

  @override
  String toString() =>
      'EpubReaderSettings(fontSize: $fontSize, '
      'lineHeight: $lineHeight, margin: $margin, theme: $theme)';
}
