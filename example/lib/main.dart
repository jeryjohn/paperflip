import 'package:flip_book/flip_book.dart';
import 'package:flutter/material.dart';

void main() => runApp(const PaperFlipDemo());

/// Public-domain EPUBs from Project Gutenberg, streamed over the network.
class Book {
  const Book({required this.title, required this.subtitle, required this.url});

  final String title;
  final String subtitle;
  final String url;

  EpubSource get source => EpubSource.network(url);
}

const _books = <Book>[
  Book(
    title: "Alice's Adventures in Wonderland",
    subtitle: 'Illustrated by Arthur Rackham',
    url: 'https://www.gutenberg.org/cache/epub/28885/pg28885-images.epub',
  ),
  Book(
    title: "Alice's Adventures in Wonderland",
    subtitle: 'The "Storyland" Series',
    url: 'https://www.gutenberg.org/cache/epub/19033/pg19033-images.epub',
  ),
  Book(
    title: "Alice's Adventures Under Ground",
    subtitle: 'Facsimile of the original manuscript',
    url: 'https://www.gutenberg.org/cache/epub/19002/pg19002-images.epub',
  ),
];

class PaperFlipDemo extends StatelessWidget {
  const PaperFlipDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PaperFlip',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF8B5E3C),
        useMaterial3: true,
      ),
      home: const LibraryScreen(),
    );
  }
}

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PaperFlip')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionHeader('EPUB — reflowable'),
          for (final book in _books)
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(book.title),
                subtitle: Text(book.subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => EpubReaderScreen(book: book),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          const _SectionHeader('Custom widget pages'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.auto_stories_outlined),
              title: const Text('Widget pages'),
              subtitle: const Text('Any Flutter widget as a page'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CustomPagesScreen(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1.2,
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      );
}

/// Reads an EPUB, with live typography controls.
///
/// Changing the reading size re-paginates the book: the page count changes and
/// the page itself always stays inside the viewport. The reader keeps their
/// place because the position is tracked as an [EpubLocator], not a page
/// number.
class EpubReaderScreen extends StatefulWidget {
  const EpubReaderScreen({super.key, required this.book});

  final Book book;

  @override
  State<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends State<EpubReaderScreen> {
  final _flip = FlipBookController();
  final _epub = EpubController(
    settings: const EpubReaderSettings(fontSize: 17, lineHeight: 1.55),
  );

  @override
  void initState() {
    super.initState();
    _epub.addListener(_onEpubChanged);
    _flip.addListener(_onEpubChanged);
  }

  @override
  void dispose() {
    _epub.removeListener(_onEpubChanged);
    _flip.removeListener(_onEpubChanged);
    _epub.dispose();
    _flip.dispose();
    super.dispose();
  }

  void _onEpubChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pagination = _epub.pagination;
    final total = pagination?.totalPages ?? 0;
    final page = _flip.currentPage + 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _epub.document?.title ?? widget.book.title,
          style: const TextStyle(fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_epub.toc.isNotEmpty)
            IconButton(
              tooltip: 'Contents',
              icon: const Icon(Icons.list),
              onPressed: _showContents,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FlipBook.epub(
              source: widget.book.source,
              controller: _flip,
              epubController: _epub,
              flip: const FlipSettings(
                duration: Duration(milliseconds: 450),
              ),
              showPageIndicator: false,
            ),
          ),
          _TypographyBar(
            epub: _epub,
            status: total == 0
                ? 'Paginating…'
                : 'Page $page of $total  ·  ${_epub.settings.fontSize.round()}pt',
          ),
        ],
      ),
    );
  }

  void _showContents() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView.builder(
        itemCount: _epub.toc.length,
        itemBuilder: (_, i) {
          final entry = _epub.toc[i];
          return ListTile(
            dense: true,
            enabled: entry.isResolved,
            contentPadding: EdgeInsets.only(
              left: 16.0 + entry.depth * 16.0,
              right: 16,
            ),
            title: Text(
              entry.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              _epub.goToChapter(i);
            },
          );
        },
      ),
    );
  }
}

/// Live reading-size controls. Every change re-paginates the book.
class _TypographyBar extends StatelessWidget {
  const _TypographyBar({required this.epub, required this.status});

  final EpubController epub;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Smaller text (reflows)',
                icon: const Icon(Icons.text_decrease),
                onPressed: epub.zoomOut,
              ),
              IconButton(
                tooltip: 'Larger text (reflows)',
                icon: const Icon(Icons.text_increase),
                onPressed: epub.zoomIn,
              ),
              const SizedBox(width: 4),
              PopupMenuButton<EpubTheme>(
                tooltip: 'Theme',
                icon: const Icon(Icons.palette_outlined),
                initialValue: epub.settings.theme,
                onSelected: epub.setTheme,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: EpubTheme.light, child: Text('Light')),
                  PopupMenuItem(value: EpubTheme.sepia, child: Text('Sepia')),
                  PopupMenuItem(value: EpubTheme.dark, child: Text('Dark')),
                ],
              ),
              Expanded(
                child: Text(
                  status,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// The lowest tier: any Flutter widget as a page.
class CustomPagesScreen extends StatefulWidget {
  const CustomPagesScreen({super.key});

  @override
  State<CustomPagesScreen> createState() => _CustomPagesScreenState();
}

class _CustomPagesScreenState extends State<CustomPagesScreen> {
  final _controller = FlipBookController();
  bool _animate = true;

  static const _palette = [
    Color(0xFFFDF6EC),
    Color(0xFFF3F7F4),
    Color(0xFFF7F0F7),
    Color(0xFFEFF3F9),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Widget pages'),
        actions: [
          IconButton(
            tooltip: _animate ? 'Disable curl' : 'Enable curl',
            icon: Icon(_animate ? Icons.animation : Icons.block),
            onPressed: () => setState(() => _animate = !_animate),
          ),
          IconButton(
            tooltip: 'Previous',
            icon: const Icon(Icons.chevron_left),
            onPressed: _controller.flipPrev,
          ),
          IconButton(
            tooltip: 'Next',
            icon: const Icon(Icons.chevron_right),
            onPressed: _controller.flipNext,
          ),
          IconButton(
            tooltip: 'Jump to page 7',
            icon: const Icon(Icons.bookmark_outline),
            onPressed: () => _controller.goToPage(6),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: FlipBook.custom(
                pageCount: 12,
                controller: _controller,
                flip: FlipSettings(enabled: _animate),
                pageBuilder: (context, index, constraints) => ColoredBox(
                  color: _palette[index % _palette.length],
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${index + 1}',
                          style: const TextStyle(
                            fontSize: 64,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Drag from any edge',
                          style: TextStyle(
                            color: Colors.black.withValues(alpha: 0.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
