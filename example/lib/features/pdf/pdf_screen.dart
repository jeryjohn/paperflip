import 'package:paperflip/paperflip.dart';
import 'package:flutter/material.dart';

class PdfScreen extends StatefulWidget {
  const PdfScreen({
    super.key,
    this.pdfUrl =
        'https://examplefiles.org/files/documents/pdf-sample-50-pages.pdf',
  });

  final String pdfUrl;

  @override
  State<PdfScreen> createState() => _PdfScreenState();
}

class _PdfScreenState extends State<PdfScreen> {
  final _controller = PaperFlipController();
  bool _useVolumeKeys = true;
  int _currentPage = 0;
  int _pageCount = 50;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (mounted && _currentPage != _controller.currentPage) {
        setState(() => _currentPage = _controller.currentPage);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openJumpToPage() {
    showDialog<void>(
      context: context,
      builder: (ctx) => PageSelectorDialog(
        pageCount: _pageCount,
        currentPage: _currentPage + 1,
        accentColor: const Color(0xFFB03A2E),
        title: 'Jump to Page',
        onPageSelected: (page) {
          Navigator.of(ctx).pop();
          _controller.jumpToPage(page - 1);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('pdf_screen'),
      backgroundColor: const Color(0xFFF3F1ED),
      appBar: AppBar(
        title: Text('PDF Reader ($_pageCount Pages)'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                'Page ${_currentPage + 1} of $_pageCount',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF555555),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Jump to page',
            icon: const Icon(Icons.bookmark_outline_rounded),
            onPressed: _openJumpToPage,
          ),
          IconButton(
            tooltip: _useVolumeKeys
                ? 'Volume keys enabled'
                : 'Volume keys disabled',
            icon: Icon(
              _useVolumeKeys ? Icons.volume_up : Icons.volume_off,
              color: _useVolumeKeys ? const Color(0xFFB03A2E) : Colors.grey,
            ),
            onPressed: () => setState(() => _useVolumeKeys = !_useVolumeKeys),
          ),
          IconButton(
            key: const Key('pdf_prev_button'),
            tooltip: 'Previous page',
            icon: const Icon(Icons.chevron_left),
            onPressed: _controller.flipPrev,
          ),
          IconButton(
            key: const Key('pdf_next_button'),
            tooltip: 'Next page',
            icon: const Icon(Icons.chevron_right),
            onPressed: _controller.flipNext,
          ),
        ],
      ),
      body: SafeArea(
        child: PaperFlip.pdf(
          source: PdfDocumentRefUri(Uri.parse(widget.pdfUrl)),
          controller: _controller,
          useVolumeKeys: _useVolumeKeys,
          flip: const FlipSettings(enabled: true),
          onPageCountAvailable: (count) {
            if (mounted && count != _pageCount) {
              setState(() => _pageCount = count);
            }
          },
          loadingBuilder: (_) =>
              const Center(child: CircularProgressIndicator()),
          errorBuilder: (context, error) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 44,
                  color: Color(0xFFB03A2E),
                ),
                const SizedBox(height: 12),
                Text(
                  'Failed to load PDF online:\n$error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => setState(() {}),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry Loading'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
