import 'package:flip_book/flip_book.dart';
import 'package:flutter/material.dart';

/// Representation of an EPUB book source in the common reader.
class CommonBook {
  const CommonBook({
    required this.title,
    required this.subtitle,
    required this.url,
  });

  final String title;
  final String subtitle;
  final String url;

  EpubSource get source => EpubSource.network(url);
}

const defaultCommonBook = CommonBook(
  title: "Alice's Adventures in Wonderland",
  subtitle: 'Illustrated by Arthur Rackham',
  url: 'https://www.gutenberg.org/cache/epub/28885/pg28885-images.epub',
);

const commonBooks = <CommonBook>[
  defaultCommonBook,
  CommonBook(
    title: "Alice's Adventures in Wonderland",
    subtitle: 'The "Storyland" Series',
    url: 'https://www.gutenberg.org/cache/epub/19033/pg19033-images.epub',
  ),
  CommonBook(
    title: "Alice's Adventures Under Ground",
    subtitle: 'Facsimile of the original manuscript',
    url: 'https://www.gutenberg.org/cache/epub/19002/pg19002-images.epub',
  ),
];

/// The Common (EPUB) reader showcase class.
///
/// Demonstrates reflowable typography, chapter pagination, themes, and
/// realistic page curls on real EPUB content.
class CommonScreen extends StatefulWidget {
  const CommonScreen({
    super.key,
    this.book = defaultCommonBook,
    this.initialSource,
  });

  final CommonBook book;
  final EpubSource? initialSource;

  @override
  State<CommonScreen> createState() => _CommonScreenState();
}

class _CommonScreenState extends State<CommonScreen> {
  final FlipBookController _flipController = FlipBookController();
  final EpubController _epubController = EpubController(
    settings: const EpubReaderSettings(
      fontSize: 18,
      lineHeight: 1.6,
      margin: 24,
      theme: EpubTheme.light,
    ),
  );

  bool _showSettings = false;
  late CommonBook _selectedBook;

  @override
  void initState() {
    super.initState();
    _selectedBook = widget.book;
  }

  @override
  void dispose() {
    _flipController.dispose();
    _epubController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _epubController.settings;
    final theme = settings.theme;

    return Scaffold(
      key: const Key('common_screen'),
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        foregroundColor: theme.foreground,
        elevation: 0,
        title: Text(
          _selectedBook.title,
          style: TextStyle(
            color: theme.foreground,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            key: const Key('common_toc_button'),
            tooltip: 'Table of Contents',
            icon: const Icon(Icons.list_alt_rounded),
            onPressed: _showTocModal,
          ),
          IconButton(
            key: const Key('common_settings_button'),
            tooltip: 'Typography & Theme',
            icon: const Icon(Icons.text_fields_rounded),
            onPressed: () => setState(() => _showSettings = !_showSettings),
          ),
          IconButton(
            key: const Key('common_prev_button'),
            tooltip: 'Previous Page',
            icon: const Icon(Icons.chevron_left),
            onPressed: _flipController.flipPrev,
          ),
          IconButton(
            key: const Key('common_next_button'),
            tooltip: 'Next Page',
            icon: const Icon(Icons.chevron_right),
            onPressed: _flipController.flipNext,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_showSettings) _buildSettingsBar(theme, settings),
            Expanded(
              child: FlipBook.epub(
                key: ValueKey(_selectedBook.url),
                source: widget.initialSource ?? _selectedBook.source,
                controller: _flipController,
                epubController: _epubController,
                showPageIndicator: true,
                loadingBuilder: (context) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(theme.foreground),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Paginating ${_selectedBook.title}…',
                        style: TextStyle(color: theme.foreground.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ),
                errorBuilder: (context, error) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Color(0xFFC0392B)),
                        const SizedBox(height: 16),
                        const Text(
                          'Could not load EPUB stream',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$error',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: () => setState(() {}),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsBar(EpubTheme theme, EpubReaderSettings settings) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.background,
        border: Border(
          bottom: BorderSide(
            color: theme.foreground.withValues(alpha: 0.12),
          ),
        ),
      ),
      child: Row(
        children: [
          const Text('Size: ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          IconButton(
            icon: const Icon(Icons.remove, size: 16),
            onPressed: () {
              if (settings.fontSize > 12) {
                _epubController.setFontSize(settings.fontSize - 2);
              }
            },
          ),
          Text('${settings.fontSize.toInt()}', style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            onPressed: () {
              if (settings.fontSize < 32) {
                _epubController.setFontSize(settings.fontSize + 2);
              }
            },
          ),
          const Spacer(),
          const Text('Theme: ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          _themeButton('Light', EpubTheme.light, settings),
          const SizedBox(width: 4),
          _themeButton('Sepia', EpubTheme.sepia, settings),
          const SizedBox(width: 4),
          _themeButton('Dark', EpubTheme.dark, settings),
        ],
      ),
    );
  }

  Widget _themeButton(String label, EpubTheme theme, EpubReaderSettings settings) {
    final active = settings.theme == theme;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: active,
      onSelected: (_) => _epubController.setTheme(theme),
      visualDensity: VisualDensity.compact,
    );
  }

  void _showTocModal() {
    final toc = _epubController.toc;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        if (toc.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24.0),
            child: Center(child: Text('Table of contents is loading or unavailable.')),
          );
        }
        return ListView.builder(
          itemCount: toc.length,
          itemBuilder: (context, i) {
            final entry = toc[i];
            return ListTile(
              title: Text(entry.title),
              onTap: () {
                Navigator.of(context).pop();
                _epubController.goToChapter(entry.spineIndex);
              },
            );
          },
        );
      },
    );
  }
}
