import 'dart:math' as math;

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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF355C4B),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8F7F3),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF8F7F3),
          foregroundColor: Color(0xFF1C2923),
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: Color(0xFF1C2923),
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        dividerColor: const Color(0xFFE2E4DF),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
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
      appBar: AppBar(
        toolbarHeight: 76,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('PaperFlip'),
            SizedBox(height: 2),
            Text(
              'Your digital bookshelf',
              style: TextStyle(
                color: Color(0xFF65726B),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const _LibraryWelcome(),
          const SizedBox(height: 28),
          const _SectionHeader('Continue reading'),
          const SizedBox(height: 8),
          for (final book in _books)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _LibraryTile(
                icon: Icons.menu_book_outlined,
                title: book.title,
                subtitle: book.subtitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => EpubReaderScreen(book: book),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 14),
          const _SectionHeader('Explore the demo'),
          const SizedBox(height: 8),
          _LibraryTile(
            icon: Icons.auto_stories_outlined,
            title: 'Widget pages',
            subtitle: 'Use any Flutter widget as a page',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CustomPagesScreen(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _LibraryTile(
            icon: Icons.grid_on_outlined,
            title: 'Curl geometry harness',
            subtitle: 'Inspect stretching, folds, and mesh detail',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CurlHarnessScreen(),
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
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF34443C),
              ),
        ),
      );
}

class _LibraryWelcome extends StatelessWidget {
  const _LibraryWelcome();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF315949), Color(0xFF45725D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26315549),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'READING ROOM',
                  style: TextStyle(
                    color: Color(0xFFCEE0D4),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'A quieter way\nto turn pages.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    height: 1.12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${_books.length} illustrated EPUBs ready to explore',
                  style: const TextStyle(
                    color: Color(0xFFE3EEE7),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: Color(0x24FFFFFF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_stories_rounded,
              color: Colors.white,
              size: 29,
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: const Color(0xFF24332C),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF6A766F),
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
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
              child: MeshFlipBook(
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

/// The ruled diagnostic page from the implementation plan's test harness.
///
/// Every element is here because a specific class of geometry bug makes it
/// obviously wrong — far more useful than a photograph while tuning:
///
/// * **horizontal rules** — stretching or compression along the curl;
/// * **vertical rules** — uneven spacing means arc length is not preserved;
/// * **the diagonal** — reveals a transposed or mirrored UV;
/// * **the circle** — any non-uniform scale shows up as an ellipse;
/// * **the border** — a camera or projection error stops it filling the page;
/// * **the page number** — front/back face mapping errors are unmissable.
class DiagnosticPage extends StatelessWidget {
  const DiagnosticPage({super.key, required this.pageNumber});

  final int pageNumber;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DiagnosticPainter(pageNumber: pageNumber),
      child: const SizedBox.expand(),
    );
  }
}

class _DiagnosticPainter extends CustomPainter {
  const _DiagnosticPainter({required this.pageNumber});

  final int pageNumber;

  static const _paper = Color(0xFFFBF8F0);
  static const _ink = Color(0xFF2B2622);
  static const _accent = Color(0xFFC2452D);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = _paper);

    final inset = math.min(w, h) * 0.02;
    canvas.drawRect(
      Rect.fromLTWH(inset, inset, w - inset * 2, h - inset * 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, inset * 0.18)
        ..color = _ink,
    );

    final rule = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.75, inset * 0.07)
      ..color = _ink.withValues(alpha: 0.28);

    for (var i = 1; i < 24; i++) {
      final y = h * i / 24;
      canvas.drawLine(Offset(inset, y), Offset(w - inset, y), rule);
    }
    for (var i = 1; i < 12; i++) {
      final x = w * i / 12;
      canvas.drawLine(Offset(x, inset), Offset(x, h - inset), rule);
    }

    final mark = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, inset * 0.14)
      ..color = _accent;
    canvas.drawLine(Offset(inset, inset), Offset(w - inset, h - inset), mark);

    final radius = math.min(w, h) * 0.22;
    canvas.drawCircle(Offset(w / 2, h / 2), radius, mark);

    const corners = ['TL', 'TR', 'BL', 'BR'];
    final at = <Offset>[
      Offset(inset * 2.4, inset * 2.4),
      Offset(w - inset * 2.4, inset * 2.4),
      Offset(inset * 2.4, h - inset * 2.4),
      Offset(w - inset * 2.4, h - inset * 2.4),
    ];
    for (var i = 0; i < 4; i++) {
      _text(canvas, corners[i], at[i], math.min(w, h) * 0.045,
          _ink.withValues(alpha: 0.7));
    }

    _text(canvas, '$pageNumber', Offset(w / 2, h / 2), math.min(w, h) * 0.3,
        _ink, weight: FontWeight.w700);
    _text(
      canvas,
      'drag me',
      Offset(w / 2, h / 2 + radius + math.min(w, h) * 0.055),
      math.min(w, h) * 0.035,
      _accent,
    );
  }

  void _text(Canvas canvas, String value, Offset center, double fontSize,
      Color color, {FontWeight weight = FontWeight.w400}) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
  }

  @override
  bool shouldRepaint(covariant _DiagnosticPainter old) =>
      old.pageNumber != pageNumber;
}

/// Drives the curl renderer with the diagnostic page and exposes the knobs
/// worth tuning by eye.
class CurlHarnessScreen extends StatefulWidget {
  const CurlHarnessScreen({super.key});

  @override
  State<CurlHarnessScreen> createState() => _CurlHarnessScreenState();
}

class _CurlHarnessScreenState extends State<CurlHarnessScreen> {
  final _controller = FlipBookController();
  bool _showMesh = false;
  bool _showShadow = true;
  double _columns = 32;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Curl geometry harness'),
        actions: [
          IconButton(
            tooltip: _showMesh ? 'Hide mesh' : 'Show mesh',
            icon: Icon(_showMesh ? Icons.grid_on : Icons.grid_off),
            onPressed: () => setState(() => _showMesh = !_showMesh),
          ),
          IconButton(
            tooltip: _showShadow ? 'Hide shadow' : 'Show shadow',
            icon: Icon(
              _showShadow ? Icons.wb_shade : Icons.wb_shade_outlined,
            ),
            onPressed: () => setState(() => _showShadow = !_showShadow),
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
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: MeshFlipBook(
                      pageCount: 24,
                      controller: _controller,
                      meshColumns: _columns.round(),
                      showShadow: _showShadow,
                      debugShowMesh: _showMesh,
                      pageBuilder: (context, index, constraints) =>
                          DiagnosticPage(pageNumber: index + 1),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text('Mesh columns'),
                    Expanded(
                      child: Slider(
                        value: _columns,
                        min: 8,
                        max: 64,
                        divisions: 56,
                        label: '${_columns.round()}',
                        onChanged: (v) => setState(() => _columns = v),
                      ),
                    ),
                    SizedBox(
                      width: 28,
                      child: Text('${_columns.round()}'),
                    ),
                  ],
                ),
                Text(
                  'Grab near the top or bottom edge for a cone, near the '
                  'middle for a cylinder.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
