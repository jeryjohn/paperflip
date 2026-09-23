import 'package:flip_book/flip_book.dart';
import 'package:flutter/material.dart';

/// The PDF showcase class.
///
/// Demonstrates reading fixed-layout PDF documents with realistic page curl.
class PdfScreen extends StatefulWidget {
  const PdfScreen({
    super.key,
    this.pdfUrl = 'https://raw.githubusercontent.com/mozilla/pdf.js/ba2edeae/test/pdfs/helloworld.pdf',
    this.pdfSource,
  });

  final String pdfUrl;
  final PdfDocumentRef? pdfSource;

  @override
  State<PdfScreen> createState() => _PdfScreenState();
}

class _PdfScreenState extends State<PdfScreen> {
  final FlipBookController _controller = FlipBookController();
  int _currentPage = 0;
  int _totalPages = 6;
  bool _useNativePdf = false;
  final bool _curlEnabled = true;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('pdf_screen'),
      backgroundColor: const Color(0xFFEBE9E4),
      appBar: AppBar(
        title: const Text('PDF Reader Demo'),
        actions: [
          IconButton(
            key: const Key('pdf_toggle_source'),
            tooltip: _useNativePdf ? 'Switch to Document View' : 'Try Native PDF Stream',
            icon: Icon(
              _useNativePdf ? Icons.picture_as_pdf : Icons.menu_book,
              color: const Color(0xFF355C4B),
            ),
            onPressed: () {
              setState(() => _useNativePdf = !_useNativePdf);
            },
          ),
          IconButton(
            key: const Key('pdf_prev_button'),
            tooltip: 'Previous Page',
            icon: const Icon(Icons.chevron_left),
            onPressed: _controller.flipPrev,
          ),
          IconButton(
            key: const Key('pdf_next_button'),
            tooltip: 'Next Page',
            icon: const Icon(Icons.chevron_right),
            onPressed: _controller.flipNext,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 22,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _buildReader(),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE5E5DF))),
              ),
              child: Row(
                children: [
                  Text(
                    'Page ${_currentPage + 1} of $_totalPages',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF333333)),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'First Page',
                    icon: const Icon(Icons.first_page),
                    onPressed: () => _controller.goToPage(0),
                  ),
                  IconButton(
                    tooltip: 'Last Page',
                    icon: const Icon(Icons.last_page),
                    onPressed: () => _controller.goToPage(_totalPages - 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReader() {
    if (_useNativePdf) {
      final source = widget.pdfSource ?? PdfDocumentRefUri(Uri.parse(widget.pdfUrl));
      return FlipBook.pdf(
        source: source,
        controller: _controller,
        flip: FlipSettings(enabled: _curlEnabled),
        onPageCountAvailable: (count) {
          if (mounted && count > 0) {
            setState(() => _totalPages = count);
          }
        },
        errorBuilder: (context, error) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.info_outline, size: 40, color: Color(0xFF7A6B5B)),
                  const SizedBox(height: 12),
                  const Text(
                    'Native PDFium stream not ready',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() => _useNativePdf = false),
                    child: const Text('View Document Pages'),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return MeshFlipBook(
      pageCount: _totalPages,
      controller: _controller,
      flip: FlipSettings(enabled: _curlEnabled),
      pageBuilder: (context, index, constraints) {
        return _buildPdfSimulatedPage(index);
      },
    );
  }

  Widget _buildPdfSimulatedPage(int index) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE8E1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.picture_as_pdf, size: 16, color: Color(0xFFC0392B)),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'PaperFlip Specification',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF4A4036)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'Page ${index + 1}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          const Divider(height: 16, thickness: 1, color: Color(0xFFE8E5DF)),
          Expanded(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _pdfPageTitle(index),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1F1A15),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _pdfPageContent(index),
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: Color(0xFF3B332B),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F5F0),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE8E3D8)),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_outline, size: 14, color: Color(0xFF7A6B5B)),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Fixed-layout PDF page at native resolution.',
                    style: TextStyle(fontSize: 10, color: Color(0xFF7A6B5B)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _pdfPageTitle(int index) {
    switch (index) {
      case 0:
        return '1. Executive Summary';
      case 1:
        return '2. Architecture & Geometry';
      case 2:
        return '3. GPU Texture Packing';
      case 3:
        return '4. Rendering Pipeline';
      case 4:
        return '5. Gesture Mechanics';
      case 5:
      default:
        return '6. Conclusion & Roadmap';
    }
  }

  String _pdfPageContent(int index) {
    switch (index) {
      case 0:
        return 'PaperFlip provides a high-performance, realistic 3D page curl experience for Flutter. Designed to operate identically across EPUB documents, PDF pages, and arbitrary widget hierarchies, it maintains 60+ FPS while delivering smooth tactile interaction.';
      case 1:
        return 'The curl surface is modeled as an analytical conical surface deformed dynamically in real time. Rather than using fixed rigid polygons, a dynamic vertex grid tracks finger coordinates and applies bending angles, conicity, and natural droop.';
      case 2:
        return 'Textures are captured on demand via WidgetPageRasterizer into a unified SheetAtlas. This technique avoids multi-pass draw overhead and preserves crisp typographic clarity without consuming excessive video memory.';
      case 3:
        return 'Flutter paint boundaries are composited directly into the custom canvas pipeline. Shadows are computed using accurate geometry projections so that curl shading traces the physical silhouette of the turning sheet.';
      case 4:
        return 'Interactive drag tracking allows fluid peeling from any corner or edge. When released, an adaptive spring smoother settles the sheet smoothly to either destination page.';
      case 5:
      default:
        return 'With full support for reflowable EPUBs, fixed PDFs, and Flutter widgets, PaperFlip is the universal reader engine for modern cross-platform Flutter applications.';
    }
  }
}
