import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:flip_book/src/flip_book_controller.dart';
import 'package:flip_book/src/flip_book_pdf.dart';
import 'package:flip_book/src/flip_settings.dart';
import 'package:flip_book/src/page_selector_dialog.dart';
import 'package:flip_book/src/volume/volume_key_manager.dart';

/// Devices with this much RAM or less use the lightweight (non-flip) viewer.
const int _defaultLowMemoryThresholdMB = 3072; // 3 GB

/// A full-screen PDF reader with a realistic page-flip experience.
///
/// This is a self-contained reading screen built on top of [FlipBookPdf]
/// (the animated flip viewer) and `pdfrx`'s [PdfViewer] (a memory-efficient
/// viewer used on low-memory devices and while zooming). It provides an app
/// bar with a page counter, auto-hiding floating controls, a zoom toggle, a
/// jump-to-page dialog, and prev/next page buttons.
///
/// Every parameter is optional. At minimum you'll usually supply a [pdfUrl]
/// (or one of the other source parameters); with no source the reader shows
/// an empty-source message.
///
/// ```dart
/// FlipBookReader(
///   title: 'My Magazine',
///   pdfUrl: 'https://example.com/doc.pdf',
/// );
/// ```
class FlipBookReader extends StatefulWidget {
  const FlipBookReader({
    super.key,
    this.title,
    this.pdfUrl,
    this.pdfAssetPath,
    this.pdfFilePath,
    this.controller,
    this.initialPage,
    this.lowMemoryThresholdMB,
    this.forceLightweightViewer,
    this.maxZoomScale,
    this.primaryColor,
    this.controlsAutoHideDuration,
    this.showAppBar,
    this.errorTitleBuilder,
    this.errorMessageBuilder,
    this.flip = const FlipSettings(),
    this.useVolumeKeys = false,
  });


  /// Title shown in the app bar. Defaults to an empty string.
  final String? title;

  /// Network URL of the PDF to display.
  final String? pdfUrl;

  /// Asset path of a bundled PDF (e.g. `assets/doc.pdf`).
  final String? pdfAssetPath;

  /// Local file path of a PDF.
  final String? pdfFilePath;

  /// Optional controller for programmatic page control of the flip viewer.
  final FlipBookController? controller;

  /// Page to open on first build (1-based). Defaults to 1.
  final int? initialPage;

  /// RAM threshold (MB) below which the lightweight viewer is used.
  /// Defaults to [_defaultLowMemoryThresholdMB] (3 GB).
  final int? lowMemoryThresholdMB;

  /// When `true`, always use the lightweight viewer regardless of device RAM.
  /// When `false`, never auto-switch based on memory. When `null` (default),
  /// the decision is made by probing device memory on Android.
  final bool? forceLightweightViewer;

  /// Maximum zoom scale for the lightweight viewer. Defaults to 3.0.
  final double? maxZoomScale;

  /// Accent colour for controls. Defaults to the theme's primary colour.
  final Color? primaryColor;

  /// How long controls stay visible before auto-hiding. Defaults to 3s.
  final Duration? controlsAutoHideDuration;

  /// Page-flip animation configuration passed to the flip viewer.
  ///
  /// Has no effect while the lightweight [PdfViewer] fallback is active (on
  /// low-memory devices or while zooming).
  final FlipSettings flip;

  /// Whether to show the app bar. Defaults to `true`.
  final bool? showAppBar;

  /// Maps an error to a title string. Falls back to a generic title.
  final String Function(Object error)? errorTitleBuilder;

  /// Maps an error to a message string. Falls back to a generic message.
  final String Function(Object error)? errorMessageBuilder;

  /// Whether physical volume buttons navigate pages on supported devices (Android).
  final bool useVolumeKeys;

  @override
  State<FlipBookReader> createState() => _FlipBookReaderState();
}

class _FlipBookReaderState extends State<FlipBookReader>
    implements VolumeKeyClient {
  bool? _isLowMemoryDevice;

  late final PdfViewerController _pdfController;
  late final FlipBookController _flipController;
  bool _ownsFlipController = false;

  int _pageCount = 0;
  int _currentPage = 1; // 1-based for display
  bool _zoomMode = false; // only used for the flip viewer

  bool _controlsVisible = false;
  Timer? _hideControlsTimer;

  Duration get _controlsAutoHideDuration =>
      widget.controlsAutoHideDuration ?? const Duration(seconds: 3);

  int get _lowMemoryThresholdMB =>
      widget.lowMemoryThresholdMB ?? _defaultLowMemoryThresholdMB;

  double get _maxZoomScale => widget.maxZoomScale ?? 3.0;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
    if (widget.controller != null) {
      _flipController = widget.controller!;
    } else {
      _flipController = FlipBookController();
      _ownsFlipController = true;
    }
    _currentPage = (widget.initialPage ?? 1).clamp(1, 1 << 30);
    // The flip viewer drives page changes through the controller; without
    // this the reader's "N of M" counter never advances in flip mode.
    _flipController.addListener(_onFlipPageChanged);

    if (widget.useVolumeKeys) {
      VolumeKeyManager.instance.registerClient(this);
    }

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _checkDeviceMemory();
  }

  @override
  void didUpdateWidget(covariant FlipBookReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.useVolumeKeys != widget.useVolumeKeys) {
      if (widget.useVolumeKeys) {
        VolumeKeyManager.instance.registerClient(this);
      } else {
        VolumeKeyManager.instance.unregisterClient(this);
      }
    }
  }

  @override
  void dispose() {
    VolumeKeyManager.instance.unregisterClient(this);
    // Hand orientation back to the host app rather than forcing portrait:
    // an empty list re-applies whatever the platform manifest allows. Flutter
    // exposes no way to read the previous preference, so this is the closest
    // we can get to "restore".
    SystemChrome.setPreferredOrientations(const []);
    _hideControlsTimer?.cancel();
    _flipController.removeListener(_onFlipPageChanged);
    if (_ownsFlipController) _flipController.dispose();
    super.dispose();
  }

  @override
  void onVolumeUp() {
    if (_isLowMemoryDevice == true || _zoomMode) {
      if (_pageCount > 0 && _currentPage < _pageCount) {
        _jumpToPage(_currentPage + 1);
      }
    } else {
      _flipController.flipNext();
    }
  }

  @override
  void onVolumeDown() {
    if (_isLowMemoryDevice == true || _zoomMode) {
      if (_pageCount > 0 && _currentPage > 1) {
        _jumpToPage(_currentPage - 1);
      }
    } else {
      _flipController.flipPrev();
    }
  }


  bool get _controlsPinned => _zoomMode;

  void _showControls({bool autoHide = true}) {
    _hideControlsTimer?.cancel();
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    if (autoHide && !_controlsPinned) {
      _hideControlsTimer = Timer(_controlsAutoHideDuration, () {
        if (!mounted) return;
        setState(() => _controlsVisible = false);
      });
    }
  }

  void _toggleControls() {
    if (_controlsPinned) {
      _showControls(autoHide: false);
      return;
    }
    if (_controlsVisible) {
      _hideControlsTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  Future<void> _checkDeviceMemory() async {
    // Explicit override wins — no probing.
    if (widget.forceLightweightViewer != null) {
      if (mounted) {
        setState(() => _isLowMemoryDevice = widget.forceLightweightViewer);
      }
      return;
    }

    bool isLowMemory = false;
    try {
      if (Platform.isAndroid) {
        final memInfo = await File('/proc/meminfo').readAsString();
        final match = RegExp(r'MemTotal:\s+(\d+)\s+kB').firstMatch(memInfo);
        if (match != null) {
          final totalMemKB = int.parse(match.group(1)!);
          final totalMemMB = totalMemKB ~/ 1024;
          log('Device total RAM: ${totalMemMB}MB');
          isLowMemory = totalMemMB < _lowMemoryThresholdMB;
        }
      }
    } catch (e) {
      log('Error checking device memory: $e');
      // Default to lightweight viewer on error to be safe.
      isLowMemory = true;
    }
    if (mounted) {
      setState(() => _isLowMemoryDevice = isLowMemory);
    }
  }

  /// Mirrors the flip controller's zero-based page onto the reader's
  /// one-based [_currentPage].
  void _onFlipPageChanged() {
    if (!mounted) return;
    final page = _flipController.currentPage + 1;
    if (page == _currentPage) return;
    setState(() => _currentPage = page);
  }

  /// The resolved document ref, built once per source rather than per build.
  ///
  /// This used to be a plain getter, so every rebuild minted a fresh
  /// [PdfDocumentRef]; [FlipBookPdf] compares its source with `!=`, so an
  /// unstable identity re-triggered a full document load on every setState.
  PdfDocumentRef? _cachedSource;
  String? _cachedSourceKey;

  PdfDocumentRef? get _source {
    final key = _sourceKey;
    if (key == null) {
      _cachedSource = null;
      _cachedSourceKey = null;
      return null;
    }
    if (key != _cachedSourceKey) {
      _cachedSourceKey = key;
      _cachedSource = _buildSource();
    }
    return _cachedSource;
  }

  /// Identity of the configured source, used to decide when to rebuild it.
  String? get _sourceKey {
    if (widget.pdfFilePath != null && widget.pdfFilePath!.isNotEmpty) {
      return 'file:${widget.pdfFilePath}';
    }
    if (widget.pdfAssetPath != null && widget.pdfAssetPath!.isNotEmpty) {
      return 'asset:${widget.pdfAssetPath}';
    }
    if (widget.pdfUrl != null && widget.pdfUrl!.isNotEmpty) {
      return 'uri:${widget.pdfUrl}';
    }
    return null;
  }

  PdfDocumentRef? _buildSource() {
    if (widget.pdfFilePath != null && widget.pdfFilePath!.isNotEmpty) {
      return PdfDocumentRefFile(widget.pdfFilePath!);
    }
    if (widget.pdfAssetPath != null && widget.pdfAssetPath!.isNotEmpty) {
      return PdfDocumentRefAsset(widget.pdfAssetPath!);
    }
    if (widget.pdfUrl != null && widget.pdfUrl!.isNotEmpty) {
      return PdfDocumentRefUri(Uri.parse(widget.pdfUrl!));
    }
    return null;
  }

  /// Detect error type and return an appropriate title.
  String _errorTitle(Object error) {
    if (widget.errorTitleBuilder != null) {
      return widget.errorTitleBuilder!(error);
    }
    final s = error.toString().toLowerCase();
    if (s.contains('404') ||
        s.contains('not found') ||
        s.contains('file does not exist') ||
        s.contains('no such file') ||
        s.contains('no host specified')) {
      return 'File not found';
    }
    return 'Something went wrong';
  }

  /// Detect error type and return an appropriate message.
  String _errorMessage(Object error) {
    if (widget.errorMessageBuilder != null) {
      return widget.errorMessageBuilder!(error);
    }
    final s = error.toString().toLowerCase();
    if (s.contains('404') ||
        s.contains('not found') ||
        s.contains('file does not exist') ||
        s.contains('no such file') ||
        s.contains('no host specified')) {
      return 'The requested file could not be found.';
    }
    if (s.contains('network') ||
        s.contains('connection') ||
        s.contains('timeout')) {
      return 'Please check your internet connection and try again.';
    }
    return 'An unexpected error occurred. Please try again.';
  }

  Color _accent(BuildContext context) =>
      widget.primaryColor ?? Theme.of(context).primaryColor;

  /// Jump to a specific page (1-based) using the active viewer's controller.
  void _jumpToPage(int pageNumber) {
    if (_isLowMemoryDevice == true || _zoomMode) {
      _pdfController.goToPage(pageNumber: pageNumber);
    } else {
      _flipController.goToPage(pageNumber - 1);
    }
  }

  Future<void> _handleZoom() async {
    _showControls();
    if (_isLowMemoryDevice == true) {
      if (!_pdfController.isReady) return;
      await _pdfController.zoomUp(loop: true);
      return;
    }
    setState(() => _zoomMode = !_zoomMode);
    if (_zoomMode) {
      _showControls(autoHide: false);
    } else {
      _showControls();
    }
  }

  Future<void> _openPageSelector() async {
    if (_pageCount <= 0) return;
    _showControls(autoHide: false);
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => PageSelectorDialog(
        pageCount: _pageCount,
        currentPage: _currentPage,
        accentColor: _accent(context),
        onPageSelected: (page) {
          Navigator.of(context).pop();
          _jumpToPage(page);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent(context);
    final showAppBar = widget.showAppBar ?? true;

    return Scaffold(
      backgroundColor: const Color(0xFFE8E4DC),
      appBar: showAppBar
          ? AppBar(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 4,
              shadowColor: Colors.black26,
              centerTitle: true,
              title: Text(
                widget.title ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
              actions: [
                if (_pageCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Center(
                      child: Text(
                        '$_currentPage of $_pageCount',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ),
              ],
            )
          : null,
      body: _isLowMemoryDevice == null
          ? const Center(child: CircularProgressIndicator())
          : GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggleControls,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: (_isLowMemoryDevice! || _zoomMode)
                        ? _buildLightweightPdfViewer()
                        : _buildFlipPdfViewer(),
                  ),
                  if (!(_isLowMemoryDevice! || _zoomMode) && _pageCount > 0)
                    Positioned(
                      bottom: 16,
                      left: 16,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FloatingActionButton.small(
                            heroTag: 'prevPageBtn',
                            onPressed: () => _flipController.flipPrev(),
                            backgroundColor: accent,
                            tooltip: 'Previous Page',
                            elevation: 4,
                            child: const Icon(Icons.arrow_back_ios_new_rounded,
                                color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          FloatingActionButton.small(
                            heroTag: 'nextPageBtn',
                            onPressed: () => _flipController.flipNext(),
                            backgroundColor: accent,
                            tooltip: 'Next Page',
                            elevation: 4,
                            child: const Icon(Icons.arrow_forward_ios_rounded,
                                color: Colors.white, size: 20),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
      floatingActionButton: _pageCount > 0
          ? AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: (_controlsVisible || _controlsPinned) ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !(_controlsVisible || _controlsPinned),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FloatingActionButton(
                      heroTag: 'zoomBtn',
                      onPressed: _handleZoom,
                      backgroundColor: _zoomMode
                          ? accent.withValues(alpha: 0.85)
                          : accent,
                      tooltip: _zoomMode ? 'Exit zoom' : 'Zoom',
                      child: Icon(
                        _zoomMode
                            ? Icons.zoom_out_rounded
                            : Icons.zoom_in_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton(
                      heroTag: 'pageBtn',
                      onPressed: _openPageSelector,
                      backgroundColor: accent,
                      tooltip: 'Jump to page',
                      child: const Icon(Icons.menu_book_rounded,
                          color: Colors.white),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  /// Memory-efficient PDF viewer using pdfrx's [PdfViewer]. Used on
  /// low-memory devices and when zoom mode is active.
  Widget _buildLightweightPdfViewer() {
    final source = _source;
    if (source == null) {
      return _buildErrorWidget(
          'No PDF source', 'No PDF URL, asset, or file path was provided.');
    }

    return PdfViewer(
      source,
      controller: _pdfController,
      initialPageNumber: _currentPage,
      params: PdfViewerParams(
        sizeDelegateProvider:
            PdfViewerSizeDelegateProviderLegacy(maxScale: _maxZoomScale),
        onViewerReady: (document, controller) {
          if (!mounted) return;
          setState(() {
            _pageCount = document.pages.length;
            _currentPage = controller.pageNumber ?? 1;
          });
        },
        onPageChanged: (pageNumber) {
          if (!mounted || pageNumber == null) return;
          setState(() => _currentPage = pageNumber);
        },
        loadingBannerBuilder: (context, bytesDownloaded, totalBytes) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  totalBytes != null
                      ? 'Loading PDF... ${(bytesDownloaded / totalBytes * 100).toStringAsFixed(0)}%'
                      : 'Loading PDF...',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          );
        },
        errorBannerBuilder: (context, error, stackTrace, documentRef) {
          return _buildErrorWidget(_errorTitle(error), _errorMessage(error));
        },
      ),
    );
  }

  /// Page-flip animated PDF viewer using [FlipBookPdf].
  Widget _buildFlipPdfViewer() {
    final source = _source;
    if (source == null) {
      return _buildErrorWidget(
          'No PDF source', 'No PDF URL, asset, or file path was provided.');
    }

    return FlipBookPdf(
      source: source,
      controller: _flipController,
      initialPage: (_currentPage - 1).clamp(0, 1 << 30),
      flip: widget.flip,
      showPageIndicator: false,
      // Without this the flip path never reports a page count, leaving the
      // app-bar counter, the prev/next FABs and the page selector hidden
      // unless the user happened to enter zoom or low-memory mode.
      onDocumentLoaded: (pageCount) {
        if (!mounted || pageCount == _pageCount) return;
        setState(() => _pageCount = pageCount);
      },
      loadingBuilder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
      errorBuilder: (context, error) =>
          _buildErrorWidget(_errorTitle(error), _errorMessage(error)),
    );
  }

  Widget _buildErrorWidget(String title, String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Color(0xFFCC0000)),
          const SizedBox(height: 16),
          Text(title,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(message, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}
