import 'package:flip_book/flip_book.dart';
import 'package:flutter/material.dart';

const pdfUrl =
    'https://raw.githubusercontent.com/mozilla/pdf.js/ba2edeae/test/pdfs/tracemonkey.pdf';

class PdfScreen extends StatefulWidget {
  const PdfScreen({super.key});

  @override
  State<PdfScreen> createState() => _PdfScreenState();
}

class _PdfScreenState extends State<PdfScreen> {
  late final FlipBookController controller;
  late final PdfDocumentRef pdfSource;
  bool _useVolumeKeys = true;

  @override
  void initState() {
    super.initState();

    controller = FlipBookController();

    // Keep the source stable across rebuilds.
    pdfSource = PdfDocumentRefUri(
      Uri.parse(pdfUrl),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Reader'),
        actions: [
          IconButton(
            tooltip: _useVolumeKeys
                ? 'Volume keys enabled (Vol Up: Next, Vol Down: Prev)'
                : 'Volume keys disabled',
            icon: Icon(
              _useVolumeKeys ? Icons.volume_up : Icons.volume_off,
              color: _useVolumeKeys ? const Color(0xFFB03A2E) : Colors.grey,
            ),
            onPressed: () {
              setState(() => _useVolumeKeys = !_useVolumeKeys);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_useVolumeKeys
                      ? 'Volume keys enabled: Hardware buttons now turn pages'
                      : 'Volume keys disabled: Default system volume restored'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Previous page',
            icon: const Icon(Icons.chevron_left),
            onPressed: controller.flipPrev,
          ),
          IconButton(
            tooltip: 'Next page',
            icon: const Icon(Icons.chevron_right),
            onPressed: controller.flipNext,
          ),
        ],
      ),
      body: SafeArea(
        child: FlipBook.pdf(
          source: pdfSource,
          controller: controller,
          useVolumeKeys: _useVolumeKeys,
          flip: const FlipSettings(
            enabled: true,
          ),

          showPageIndicator: false,
          loadingBuilder: (context) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          },
          errorBuilder: (context, error) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load PDF:\n$error',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}