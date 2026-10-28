import 'package:paperflip/paperflip.dart';
import 'package:flutter/material.dart';

/// The clean, professional EPUB reader detailed page.
class CommonScreen extends StatefulWidget {
  const CommonScreen({super.key});

  @override
  State<CommonScreen> createState() => _CommonScreenState();
}

class _CommonScreenState extends State<CommonScreen> {
  final PaperFlipController _flipController = PaperFlipController();
  final EpubController _epubController = EpubController(
    settings: const EpubReaderSettings(
      fontSize: 18,
      lineHeight: 1.6,
      margin: 24,
      theme: EpubTheme.light,
    ),
  );
  bool _useVolumeKeys = false;

  @override
  void dispose() {
    _flipController.dispose();
    _epubController.dispose();
    super.dispose();
  }

  void _openJumpToPage() {
    final pageCount = _flipController.pageCount;
    final currentPage = _flipController.currentPage + 1;
    showDialog<void>(
      context: context,
      builder: (ctx) => PageSelectorDialog(
        pageCount: pageCount > 0 ? pageCount : 50,
        currentPage: currentPage,
        accentColor: const Color(0xFF2E654D),
        title: 'Jump to Page',
        onPageSelected: (page) {
          Navigator.of(ctx).pop();
          _flipController.jumpToPage(page - 1);
        },
      ),
    );
  }

  void _openSettings() {
    final activeTheme = _epubController.settings.theme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: activeTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final settings = _epubController.settings;
          final theme = settings.theme;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.foreground.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Reader Settings',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: theme.foreground,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: theme.foreground,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Volume keys toggle
                  SwitchListTile(
                    tileColor: theme.foreground.withValues(alpha: 0.04),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 2,
                    ),
                    secondary: Icon(
                      _useVolumeKeys ? Icons.volume_up : Icons.volume_off,
                      color: const Color(0xFF2E654D),
                    ),
                    title: Text(
                      'Use volume button',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: theme.foreground,
                      ),
                    ),
                    subtitle: Text(
                      'Turn pages using hardware volume keys',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.foreground.withValues(alpha: 0.6),
                      ),
                    ),
                    value: _useVolumeKeys,
                    activeThumbColor: const Color(0xFF2E654D),
                    onChanged: (val) {
                      setState(() => _useVolumeKeys = val);
                      setSheet(() {});
                    },
                  ),
                  const SizedBox(height: 18),

                  // Color themes
                  Text(
                    'Theme: ',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: theme.foreground,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _themeChip('Light', EpubTheme.light, theme, setSheet),
                      const SizedBox(width: 8),
                      _themeChip('Sepia', EpubTheme.sepia, theme, setSheet),
                      const SizedBox(width: 8),
                      _themeChip('Dark', EpubTheme.dark, theme, setSheet),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Zoom / Text size
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Zoom (Font Size)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: theme.foreground,
                        ),
                      ),
                      Text(
                        '${settings.fontSize.toInt()} pt',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2E654D),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton.filledTonal(
                        icon: const Icon(Icons.remove, size: 16),
                        onPressed: settings.fontSize > 12
                            ? () {
                                _epubController.setFontSize(
                                  settings.fontSize - 2,
                                );
                                setSheet(() {});
                                setState(() {});
                              }
                            : null,
                      ),
                      Expanded(
                        child: Slider(
                          value: settings.fontSize.clamp(12.0, 32.0),
                          min: 12.0,
                          max: 32.0,
                          activeColor: const Color(0xFF2E654D),
                          onChanged: (val) {
                            _epubController.setFontSize(val);
                            setSheet(() {});
                            setState(() {});
                          },
                        ),
                      ),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.add, size: 16),
                        onPressed: settings.fontSize < 32
                            ? () {
                                _epubController.setFontSize(
                                  settings.fontSize + 2,
                                );
                                setSheet(() {});
                                setState(() {});
                              }
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _themeChip(
    String label,
    EpubTheme target,
    EpubTheme active,
    StateSetter setSheet,
  ) {
    final isSelected = target == active;
    return Expanded(
      child: ChoiceChip(
        label: Center(child: Text(label)),
        selected: isSelected,
        onSelected: (_) {
          _epubController.setTheme(target);
          setSheet(() {});
          setState(() {});
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = _epubController.settings.theme;
    return Scaffold(
      key: const Key('common_screen'),
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        foregroundColor: theme.foreground,
        title: Text(
          "Alice's Adventures in Wonderland",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: theme.foreground,
          ),
        ),
        actions: [
          // Jump to page option
          IconButton(
            tooltip: 'Jump to page',
            icon: const Icon(Icons.bookmark_outline_rounded),
            onPressed: _openJumpToPage,
          ),
          // Settings symbol
          IconButton(
            key: const Key('common_settings_button'),
            tooltip: 'Reader Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: PaperFlip.epub(
                source: EpubSource.network(
                  'https://www.gutenberg.org/cache/epub/28885/pg28885-images.epub',
                ),
                controller: _flipController,
                epubController: _epubController,
                useVolumeKeys: _useVolumeKeys,
                showPageIndicator: true,
                loadingBuilder: (_) =>
                    const Center(child: CircularProgressIndicator()),
                errorBuilder: (_, error) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not load EPUB: $error'),
                  ),
                ),
              ),
            ),

            // Left side non-distracting button
            Positioned(
              left: 10,
              top: 0,
              bottom: 0,
              child: Center(
                child: _sideButton(
                  key: const Key('common_prev_button'),
                  icon: Icons.chevron_left_rounded,
                  theme: theme,
                  onTap: _flipController.flipPrev,
                ),
              ),
            ),

            // Right side non-distracting button
            Positioned(
              right: 10,
              top: 0,
              bottom: 0,
              child: Center(
                child: _sideButton(
                  key: const Key('common_next_button'),
                  icon: Icons.chevron_right_rounded,
                  theme: theme,
                  onTap: _flipController.flipNext,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sideButton({
    required Key key,
    required IconData icon,
    required EpubTheme theme,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: theme.foreground.withValues(alpha: 0.08),
          shape: BoxShape.circle,
          border: Border.all(
            color: theme.foreground.withValues(alpha: 0.16),
            width: 1,
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            size: 22,
            color: theme.foreground.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }
}
