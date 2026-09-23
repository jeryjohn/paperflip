import 'package:flip_book/flip_book.dart';
import 'package:flutter/material.dart';

/// The Custom pages showcase class.
///
/// Demonstrates arbitrary Flutter widgets rendered as realistic curling pages
/// using [MeshFlipBook].
class CustomScreen extends StatefulWidget {
  const CustomScreen({super.key});

  @override
  State<CustomScreen> createState() => _CustomScreenState();
}

class _CustomScreenState extends State<CustomScreen> {
  final FlipBookController _controller = FlipBookController();
  bool _curlEnabled = true;
  bool _useVolumeKeys = true;
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
                ? 'Volume keys enabled (Vol Up: Next, Vol Down: Prev)'
                : 'Volume keys disabled',
            icon: Icon(
              _useVolumeKeys ? Icons.volume_up : Icons.volume_off,
              color: _useVolumeKeys ? const Color(0xFF2E658C) : Colors.grey,
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
            key: const Key('custom_toggle_curl'),
            tooltip: _curlEnabled ? 'Disable 3D Curl' : 'Enable 3D Curl',
            icon: Icon(
              _curlEnabled ? Icons.layers : Icons.layers_clear,
              color: _curlEnabled ? const Color(0xFF355C4B) : Colors.grey,
            ),
            onPressed: () {
              setState(() {
                _curlEnabled = !_curlEnabled;
              });
            },
          ),

          IconButton(
            key: const Key('custom_prev_button'),
            tooltip: 'Previous Page',
            icon: const Icon(Icons.chevron_left),
            onPressed: _controller.flipPrev,
          ),
          IconButton(
            key: const Key('custom_next_button'),
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
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.14),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: MeshFlipBook(
                        key: ValueKey('mesh_book_$_curlEnabled'),
                        pageCount: _pageCount,
                        controller: _controller,
                        flip: FlipSettings(
                          enabled: _curlEnabled,
                          duration: const Duration(milliseconds: 400),
                        ),
                        useVolumeKeys: _useVolumeKeys,
                        pageBuilder: (context, index, constraints) {
                          return _buildPageCard(index);
                        },
                      ),
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
                    'Page ${_currentPage + 1} of $_pageCount',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF333333),
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _controller.goToPage(0),
                    icon: const Icon(Icons.first_page, size: 18),
                    label: const Text('Start'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _controller.goToPage(_pageCount - 1),
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

  Widget _buildPageCard(int index) {
    switch (index) {
      case 0:
        return const _CoverPage();
      case 1:
        return const _StatsPage();
      case 2:
        return const _QuotePage();
      case 3:
        return const _FeaturesPage();
      case 4:
        return const _InteractiveWidgetPage();
      case 5:
        return const _TypographyShowcasePage();
      case 6:
        return const _ArtworkPage();
      case 7:
      default:
        return const _FinalPage();
    }
  }
}

class _CoverPage extends StatelessWidget {
  const _CoverPage();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF243B30),
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.12),
            ),
            child: const Icon(Icons.auto_stories, size: 48, color: Color(0xFFE2EEDF)),
          ),
          const SizedBox(height: 24),
          const Text(
            'Custom Pages',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Render any Flutter Widget Tree into realistic 3D turning sheets',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.8),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Swipe to turn →',
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsPage extends StatelessWidget {
  const _StatsPage();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFAF9F6),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Performance Metrics',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF222222)),
          ),
          const SizedBox(height: 16),
          _metricRow('Frame Rate', '60 / 120 FPS', Icons.speed),
          _metricRow('Mesh Grid', '32 × 32 vertices', Icons.grid_3x3),
          _metricRow('Curl Math', 'Zero heap garbage', Icons.memory),
          _metricRow('Texture Format', 'RGBA 2x supersampled', Icons.image),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2ED),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Each page is captured through WidgetPageRasterizer and mapped onto a deformed 3D mesh.',
              style: TextStyle(fontSize: 12, color: Color(0xFF2F5041), height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricRow(String title, String val, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF436B58)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Color(0xFF555555), fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            val,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF222222),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuotePage extends StatelessWidget {
  const _QuotePage();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF3ECE1),
      padding: const EdgeInsets.all(28),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.format_quote, size: 40, color: Color(0xFFB0987A)),
            SizedBox(height: 16),
            Text(
              '"Books are a uniquely portable magic."',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontStyle: FontStyle.italic,
                fontSize: 18,
                color: Color(0xFF4A3E31),
                height: 1.5,
              ),
            ),
            SizedBox(height: 12),
            Text(
              '— Stephen King',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF7A6B5B),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturesPage extends StatelessWidget {
  const _FeaturesPage();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEEF3F7),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Core Features',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1B2E3D)),
          ),
          const SizedBox(height: 14),
          _featureItem(Icons.touch_app, 'Fluid Dragging', 'Realistic corner grabbing and peel.'),
          _featureItem(Icons.auto_stories, 'Multi-Format', 'EPUB, PDF, and Flutter widgets.'),
          _featureItem(Icons.style, 'Shadow & Lighting', 'Accurate ambient occlusion on curls.'),
          _featureItem(Icons.devices, 'Cross Platform', 'iOS, Android, macOS, Web, Desktop.'),
        ],
      ),
    );
  }

  Widget _featureItem(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFD6E4EE),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: const Color(0xFF264962)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text(subtitle, style: const TextStyle(color: Color(0xFF6B7F8D), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InteractiveWidgetPage extends StatefulWidget {
  const _InteractiveWidgetPage();

  @override
  State<_InteractiveWidgetPage> createState() => _InteractiveWidgetPageState();
}

class _InteractiveWidgetPageState extends State<_InteractiveWidgetPage> {
  int _counter = 0;
  bool _switchVal = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF7F0F7),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Interactive Subtree',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF4C274C)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Active Flutter state lives on the settled page',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF755175)),
          ),
          const SizedBox(height: 24),
          Text('Taps: $_counter', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => setState(() => _counter++),
            icon: const Icon(Icons.add),
            label: const Text('Increment'),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Toggle State', style: TextStyle(fontSize: 14)),
            value: _switchVal,
            onChanged: (v) => setState(() => _switchVal = v),
          ),
        ],
      ),
    );
  }
}

class _TypographyShowcasePage extends StatelessWidget {
  const _TypographyShowcasePage();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFAF7F2),
      padding: const EdgeInsets.all(24),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Typography Precision',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2C241D)),
          ),
          SizedBox(height: 12),
          Text(
            'Text clarity is preserved during texture capture through native resolution rasterization. Supersampling avoids blurriness even during oblique curl viewing.',
            style: TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF5A4C40)),
          ),
          SizedBox(height: 16),
          Text('Heading 1 — 24pt Bold', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text('Heading 2 — 18pt SemiBold', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          Text('Body text — 14pt Regular', style: TextStyle(fontSize: 13)),
          Text('Caption — 11pt Light', style: TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _ArtworkPage extends StatelessWidget {
  const _ArtworkPage();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF2C2638),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                gradient: const RadialGradient(
                  colors: [Color(0xFFE2B0FF), Color(0xFF7042A8)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.purple.withValues(alpha: 0.3),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: const Icon(Icons.palette, size: 52, color: Colors.white),
            ),
            const SizedBox(height: 20),
            const Text(
              'Gradients & Vectors',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Rich shadows, gradients, and custom painters composite effortlessly into the mesh atlas.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinalPage extends StatelessWidget {
  const _FinalPage();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF2E4036),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline, size: 48, color: Color(0xFFBCE3CB)),
            const SizedBox(height: 16),
            const Text(
              'End of Preview',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Flip back to the start or explore EPUB & PDF readers.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.8)),
            ),
          ],
        ),
      ),
    );
  }
}
