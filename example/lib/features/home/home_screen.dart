import 'package:flutter/material.dart';

import '../custom/custom_screen.dart';
import '../epub/epub_screen.dart';
import '../pdf/pdf_screen.dart';
import 'widgets/custom_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('home_screen'),
      backgroundColor: const Color(0xFFF6F7F5),
      appBar: AppBar(
        titleSpacing: 20,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Flip Book Example',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: Color(0xFF111827),
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE5E7EB), height: 1),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        children: [
          // 1. EPUB
          CustomCard(
            key: const Key('home_common_tile'),
            badge: 'EPUB',
            title: 'Alice in Wonderland',
            subtitle: 'Random epub • from Project Gutenberg website',
            icon: Icons.menu_book_rounded,
            iconColor: const Color(0xFF2E654D),
            iconBg: const Color(0xFFEBF3EF),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CommonScreen()),
            ),
          ),
          const SizedBox(height: 12),

          // 2. PDF (using https://examplefiles.org/files/documents/pdf-sample-50-pages.pdf)
          CustomCard(
            key: const Key('home_pdf_tile'),
            badge: 'PDF',
            // rating: '★ 4.9 (50 pgs)   ',
            title: 'PDF Sample Document',
            subtitle: 'random pdf • from examplefiles.org',
            icon: Icons.picture_as_pdf_rounded,
            iconColor: const Color(0xFFB03A2E),
            iconBg: const Color(0xFFFBECEB),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const PdfScreen())),
          ),
          const SizedBox(height: 12),

          // 3. CUSTOM WIDGETS
          CustomCard(
            key: const Key('home_custom_tile'),
            badge: 'WIDGETS',
            title: 'Custom Widgets',
            subtitle: 'Interactive UI • 3D Mesh Curl',
            icon: Icons.dashboard_customize_rounded,
            iconColor: const Color(0xFF2563EB),
            iconBg: const Color(0xFFEFF5FF),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CustomScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
