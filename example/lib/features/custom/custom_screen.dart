import 'package:paperflip/paperflip.dart';
import 'package:flutter/material.dart';

class CustomScreen extends StatefulWidget {
  const CustomScreen({super.key});

  @override
  State<CustomScreen> createState() => _CustomScreenState();
}

class _CustomScreenState extends State<CustomScreen> {
  final PaperFlipController _controller = PaperFlipController();
  bool _curlEnabled = true;
  bool _useVolumeKeys = false;
  int _currentPage = 0;
  static const _pageCount = 8;

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
      key: const Key('custom_screen'),
      backgroundColor: const Color(0xFFF3F1EC),
      appBar: AppBar(
        title: const Text('Custom Widgets Demo'),
        actions: [
          IconButton(
            tooltip: _useVolumeKeys
                ? 'Volume keys enabled'
                : 'Volume keys disabled',
            icon: Icon(
              _useVolumeKeys ? Icons.volume_up : Icons.volume_off,
              color: _useVolumeKeys ? const Color(0xFF2E658C) : Colors.grey,
            ),
            onPressed: () => setState(() => _useVolumeKeys = !_useVolumeKeys),
          ),
          IconButton(
            key: const Key('custom_toggle_curl'),
            tooltip: _curlEnabled ? 'Disable 3D Curl' : 'Enable 3D Curl',
            icon: Icon(
              _curlEnabled ? Icons.layers_rounded : Icons.layers_clear_rounded,
              color: _curlEnabled ? const Color(0xFF2E658C) : Colors.grey,
            ),
            onPressed: () => setState(() => _curlEnabled = !_curlEnabled),
          ),
          IconButton(
            key: const Key('custom_prev_button'),
            tooltip: 'Previous page',
            icon: const Icon(Icons.chevron_left),
            onPressed: _controller.flipPrev,
          ),
          IconButton(
            key: const Key('custom_next_button'),
            tooltip: 'Next page',
            icon: const Icon(Icons.chevron_right),
            onPressed: _controller.flipNext,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: MeshPaperFlip(
                controller: _controller,
                pageCount: _pageCount,
                flip: FlipSettings(enabled: _curlEnabled),
                useVolumeKeys: _useVolumeKeys,
                pageBuilder: (context, index, constraints) {
                  return Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.widgets_rounded,
                            size: 48,
                            color: Color(0xFF2563EB + (index * 0x1234)),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Custom Page ${index + 1}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Curling interactive Flutter widget tree • Page ${index + 1} of $_pageCount',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.white,
              child: Row(
                children: [
                  Text(
                    'Page ${_currentPage + 1} of $_pageCount',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _controller.jumpToPage(0),
                    icon: const Icon(Icons.first_page, size: 18),
                    label: const Text('Start'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _controller.jumpToPage(_pageCount - 1),
                    icon: const Icon(Icons.last_page, size: 18),
                    label: const Text('End'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
