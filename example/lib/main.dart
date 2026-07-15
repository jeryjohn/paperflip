import 'package:flip_book/flip_book.dart';
import 'package:flutter/material.dart';

void main() => runApp(const FlipBookExampleApp());

class FlipBookExampleApp extends StatelessWidget {
  const FlipBookExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flip_book example',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown)),
      home: const FlipBookExamplePage(),
    );
  }
}

class FlipBookExamplePage extends StatefulWidget {
  const FlipBookExamplePage({super.key});

  @override
  State<FlipBookExamplePage> createState() => _FlipBookExamplePageState();
}

class _FlipBookExamplePageState extends State<FlipBookExamplePage> {
  final _controller = FlipBookController();

  static const _pageCount = 12;
  static const _pageColors = [
    Color(0xFFFFFDE7),
    Color(0xFFF3E5F5),
    Color(0xFFE8F5E9),
    Color(0xFFE3F2FD),
    Color(0xFFFCE4EC),
    Color(0xFFE0F2F1),
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
        title: const Text('flip_book demo'),
        actions: [
          IconButton(
            tooltip: 'Previous',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _controller.flipPrev(),
          ),
          IconButton(
            tooltip: 'Next',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _controller.flipNext(),
          ),
          IconButton(
            tooltip: 'Jump to page 7',
            icon: const Icon(Icons.bookmark),
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
              child: FlipBookWidget(
                pageCount: _pageCount,
                controller: _controller,
                pageBuilder: (context, index, constraints) {
                  return Container(
                    color: _pageColors[index % _pageColors.length],
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Page ${index + 1}',
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF333333),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Drag a corner to flip',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return BottomAppBar(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () => _controller.previousPage(),
                  child: const Text('previousPage()'),
                ),
                Text(
                  '${_controller.currentPage + 1} / $_pageCount',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () => _controller.nextPage(),
                  child: const Text('nextPage()'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
