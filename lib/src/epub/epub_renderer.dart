import 'package:flutter/widgets.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import 'package:flip_book/src/epub/epub_document.dart';
import 'package:flip_book/src/epub/epub_reader_settings.dart';

/// Renders one EPUB spine document as a Flutter widget tree.
///
/// Deliberately returns plain Flutter widgets rather than embedding a WebView:
/// only pure-Flutter content can be composited into the page-curl animation
/// (platform views render blank under `RepaintBoundary.toImage`).
class EpubRenderer extends StatelessWidget {
  const EpubRenderer({
    super.key,
    required this.document,
    required this.item,
    required this.settings,
  });

  final EpubDocument document;
  final EpubSpineItem item;
  final EpubReaderSettings settings;

  /// Number of times a chapter subtree has been built.
  ///
  /// Exposed for tests: the flip engine rebuilds its layers every animation
  /// frame, so this rising with frame count means page content is not being
  /// served from prepared chapters.
  static int debugBuildCount = 0;

  @override
  Widget build(BuildContext context) {
    debugBuildCount++;
    final theme = settings.theme;

    return DefaultTextStyle(
      style: TextStyle(
        color: theme.foreground,
        fontSize: settings.fontSize,
        height: settings.lineHeight,
        fontFamily: settings.fontFamily,
      ),
      child: HtmlWidget(
        item.html,
        // Rebuild when typography changes so pagination stays in step.
        key: ValueKey(
          '${item.href}|${settings.fontSize}|${settings.lineHeight}'
          '|${settings.fontFamily}|${theme.name}',
        ),
        textStyle: TextStyle(
          color: theme.foreground,
          fontSize: settings.fontSize,
          height: settings.lineHeight,
          fontFamily: settings.fontFamily,
        ),
        customWidgetBuilder: _buildCustomWidget,
        customStylesBuilder: _buildCustomStyles,
        // Build synchronously. The async path returns a placeholder on the
        // first frames, and pagination measures whatever is laid out -- which
        // silently produced a ~52px "height" for every chapter instead of the
        // real one.
        buildAsync: false,
        // Images and text come from the archive, never the network.
        onTapUrl: (_) async => false,
        // Let the renderer reuse its parsed tree; the key above already
        // scopes the cache to this document and typography.
        enableCaching: true,
        renderMode: RenderMode.column,
      ),
    );
  }

  /// Serves `<img>` from the EPUB archive instead of the network.
  Widget? _buildCustomWidget(dom.Element element) {
    if (element.localName != 'img') return null;

    final src = element.attributes['src'];
    if (src == null || src.isEmpty) return null;

    final bytes = document.imageFor(src, fromHref: item.href);
    if (bytes == null) {
      // Unresolvable image: render nothing rather than a broken-network box.
      return const SizedBox.shrink();
    }

    final alt = element.attributes['alt'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Semantics(
          label: alt,
          image: true,
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  /// Applies the reader's colour scheme over the book's own stylesheet.
  Map<String, String>? _buildCustomStyles(dom.Element element) {
    switch (element.localName) {
      case 'body':
      case 'p':
      case 'div':
      case 'span':
      case 'li':
        return {'color': _cssColor(settings.theme.foreground)};
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return {
          'color': _cssColor(settings.theme.foreground),
          'text-align': 'center',
        };
      default:
        return null;
    }
  }

  static String _cssColor(Color color) {
    final r = (color.r * 255).round().clamp(0, 255);
    final g = (color.g * 255).round().clamp(0, 255);
    final b = (color.b * 255).round().clamp(0, 255);
    return 'rgb($r, $g, $b)';
  }
}
