import 'package:flip_book/flip_book.dart';
import 'package:flutter/material.dart';

import 'common.dart';
import 'custom.dart';
import 'pdf.dart';

/// The Home screen where all showcase classes are called:
/// 1. [CommonScreen] (EPUB / Reflowable)
/// 2. [PdfScreen] (PDF Documents)
/// 3. [CustomScreen] (Custom Widget Pages)
/// 4. [FlipBookReader] (Full PDF Reader with Zoom & Hardware Volume Keys)
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('home_screen'),
      backgroundColor: const Color(0xFFF7F6F2),
      appBar: AppBar(
        toolbarHeight: 74,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'PaperFlip',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: Color(0xFF1B2823),
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Interactive 3D Page-Flip Reader Showcase',
              style: TextStyle(
                color: Color(0xFF65726B),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const _WelcomeBanner(),
          const SizedBox(height: 24),
          const _SectionHeader(
            title: 'Reader Modes',
            subtitle: 'Choose one of the 4 reader implementations',
          ),
          const SizedBox(height: 12),

          // 1. Common (EPUB)
          _ShowcaseCard(
            key: const Key('home_common_tile'),
            title: 'Common (EPUB Reader)',
            subtitle: 'Reflowable text, typography controls, HTML spine slicing',
            badge: 'EPUB',
            icon: Icons.menu_book_rounded,
            accentColor: const Color(0xFF355C4B),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CommonScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // 2. PDF
          _ShowcaseCard(
            key: const Key('home_pdf_tile'),
            title: 'PDF Reader',
            subtitle: 'Fixed-layout document rendering with realistic sheet curl',
            badge: 'PDF',
            icon: Icons.picture_as_pdf_rounded,
            accentColor: const Color(0xFFB03A2E),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PdfScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // 3. Custom
          _ShowcaseCard(
            key: const Key('home_custom_tile'),
            title: 'Custom Widgets',
            subtitle: 'Any Flutter widget tree transformed into curling paper',
            badge: 'WIDGETS',
            icon: Icons.dashboard_customize_rounded,
            accentColor: const Color(0xFF2E658C),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CustomScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // 4. FlipBookReader
          _ShowcaseCard(
            key: const Key('home_flip_reader_tile'),
            title: 'FlipBookReader (Full UI)',
            subtitle: 'Full screen PDF reader with zoom, page dialog, and hardware volume navigation',
            badge: 'FULL READER',
            icon: Icons.chrome_reader_mode_rounded,
            accentColor: const Color(0xFF6B4C85),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const FlipBookReader(
                    title: 'TraceMonkey (Volume Keys Enabled)',
                    pdfUrl: pdfUrl,
                    useVolumeKeys: true,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 28),


          const _SectionHeader(
            title: 'EPUB Bookshelf',
            subtitle: 'Project Gutenberg public domain titles',
          ),
          const SizedBox(height: 12),

          for (final book in commonBooks)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _BookCard(
                book: book,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CommonScreen(book: book),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1F352B), Color(0xFF325344)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1F352B).withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_stories,
                  color: Color(0xFFE2EEDF),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Universal Reader Engine',
                  style: TextStyle(
                    color: Color(0xFFE2EEDF),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Experience seamless 3D mesh curls, zero heap garbage during animation, and support across EPUB, PDF, and custom Flutter pages.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1B2823),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF708078),
          ),
        ),
      ],
    );
  }
}

class _ShowcaseCard extends StatelessWidget {
  const _ShowcaseCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String badge;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: accentColor.withValues(alpha: 0.08),
        highlightColor: accentColor.withValues(alpha: 0.04),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E7E2)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1C2923),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: accentColor,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6E7A74),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFFADB5B0)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({required this.book, required this.onTap});

  final CommonBook book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE9ECE7)),
          ),
          child: Row(
            children: [
              const Icon(Icons.book_outlined, color: Color(0xFF355C4B), size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF222B26),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      book.subtitle,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A8680)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFFADB5B0)),
            ],
          ),
        ),
      ),
    );
  }
}
