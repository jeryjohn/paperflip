import 'package:flutter/material.dart';

/// A simple dialog that lets the user jump to a specific page.
///
/// Shows a grid of page numbers; tapping one invokes [onPageSelected] with the
/// 1-based page number. All parameters are optional — when [pageCount] is not
/// supplied (or is zero) the dialog shows an empty state.
class PageSelectorDialog extends StatelessWidget {
  const PageSelectorDialog({
    super.key,
    this.pageCount = 0,
    this.currentPage = 1,
    this.onPageSelected,
    this.title = 'Jump to page',
    this.accentColor,
  });

  /// Total number of pages to choose from.
  final int pageCount;

  /// The currently displayed page (1-based) — highlighted in the grid.
  final int currentPage;

  /// Called with the selected 1-based page number.
  final ValueChanged<int>? onPageSelected;

  /// Dialog title.
  final String title;

  /// Optional accent colour for the selected page chip. Falls back to the
  /// theme's primary colour.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? Theme.of(context).primaryColor;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 480),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: pageCount <= 0
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('No pages available.'),
                      )
                    : GridView.builder(
                        shrinkWrap: true,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1.2,
                        ),
                        itemCount: pageCount,
                        itemBuilder: (context, index) {
                          final page = index + 1;
                          final isCurrent = page == currentPage;
                          return Material(
                            color: isCurrent
                                ? accent
                                : accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => onPageSelected?.call(page),
                              child: Center(
                                child: Text(
                                  '$page',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isCurrent
                                        ? Colors.white
                                        : const Color(0xFF374151),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
