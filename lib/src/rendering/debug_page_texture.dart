import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// Draws the diagnostic page used by the curl test harness.
///
/// Every element is chosen because a specific class of geometry bug makes it
/// obviously wrong, which is far more useful during development than a
/// photograph:
///
/// | Element            | Reveals                                        |
/// | ------------------ | ---------------------------------------------- |
/// | border             | camera / projection error (page stops filling)  |
/// | horizontal rules   | stretching and compression along the curl       |
/// | vertical rules     | arc-length error across the fold                |
/// | diagonal           | orientation / UV transposition                  |
/// | circle             | non-uniform scale (a circle must stay a circle  |
/// |                    | at rest and only bend with the paper)           |
/// | page number + text | front/back face mapping, mirroring              |
/// | corner markers     | which corner is which after a reflection        |
///
/// This is internal: it exists to be rasterised into a `ui.Image` and mapped
/// onto the mesh, and to be shown directly for an A/B comparison against the
/// undeformed page.
@internal
class DebugPagePainter extends CustomPainter {
  const DebugPagePainter({
    required this.pageNumber,
    this.isBackFace = false,
    this.paperColor = const Color(0xFFFBF8F0),
    this.inkColor = const Color(0xFF2B2622),
    this.accentColor = const Color(0xFFC2452D),
  });

  /// One-based page number rendered large in the centre.
  final int pageNumber;

  /// Tints the sheet and flips the label so a mirrored back face is obvious.
  final bool isBackFace;

  final Color paperColor;
  final Color inkColor;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = isBackFace ? _shade(paperColor, 0.04) : paperColor,
    );

    // 1. Border, inset by 2% so a clipped edge is visible rather than
    //    disappearing into the page boundary.
    final inset = math.min(w, h) * 0.02;
    canvas.drawRect(
      Rect.fromLTWH(inset, inset, w - inset * 2, h - inset * 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, inset * 0.18)
        ..color = inkColor,
    );

    final rule = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.75, inset * 0.07)
      ..color = inkColor.withValues(alpha: 0.28);

    // 2. Horizontal rules: a straight line must curve smoothly, never kink.
    const rows = 24;
    for (var i = 1; i < rows; i++) {
      final y = h * i / rows;
      canvas.drawLine(Offset(inset, y), Offset(w - inset, y), rule);
    }

    // 3. Vertical rules: uneven spacing here means arc length is not preserved.
    const cols = 12;
    for (var i = 1; i < cols; i++) {
      final x = w * i / cols;
      canvas.drawLine(Offset(x, inset), Offset(x, h - inset), rule);
    }

    // 4. Diagonal, corner to corner. A transposed UV turns it the other way.
    canvas.drawLine(
      Offset(inset, inset),
      Offset(w - inset, h - inset),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, inset * 0.14)
        ..color = accentColor,
    );

    // 5. Circle, centred. Any non-uniform scale shows up as an ellipse.
    final radius = math.min(w, h) * 0.22;
    canvas.drawCircle(
      Offset(w / 2, h / 2),
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, inset * 0.14)
        ..color = accentColor,
    );

    // 6. Corner markers, each a different size, so a reflected or rotated
    //    page cannot masquerade as a correct one.
    const labels = ['TL', 'TR', 'BL', 'BR'];
    final corners = <Offset>[
      Offset(inset * 2.2, inset * 2.2),
      Offset(w - inset * 2.2, inset * 2.2),
      Offset(inset * 2.2, h - inset * 2.2),
      Offset(w - inset * 2.2, h - inset * 2.2),
    ];
    for (var i = 0; i < 4; i++) {
      _text(
        canvas,
        labels[i],
        corners[i],
        math.min(w, h) * 0.045,
        inkColor.withValues(alpha: 0.7),
      );
    }

    // 7. Page number, large. Front/back mapping errors are unmissable here.
    _text(
      canvas,
      '$pageNumber',
      Offset(w / 2, h / 2),
      math.min(w, h) * 0.3,
      inkColor,
      weight: FontWeight.w700,
    );

    // 8. Small text, to judge texture resolution during the flip.
    _text(
      canvas,
      isBackFace ? 'BACK FACE' : 'front face',
      Offset(w / 2, h / 2 + radius + math.min(w, h) * 0.06),
      math.min(w, h) * 0.035,
      accentColor,
    );
  }

  void _text(
    Canvas canvas,
    String value,
    Offset center,
    double fontSize,
    Color color, {
    FontWeight weight = FontWeight.w400,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: weight,
          // Deliberately no fontFamily: the harness must render identically in
          // a test environment, where only the fallback font is loaded.
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
  }

  Color _shade(Color c, double amount) => Color.from(
        alpha: c.a,
        red: c.r * (1 - amount),
        green: c.g * (1 - amount),
        blue: c.b * (1 - amount),
      );

  @override
  bool shouldRepaint(covariant DebugPagePainter old) =>
      old.pageNumber != pageNumber ||
      old.isBackFace != isBackFace ||
      old.paperColor != paperColor ||
      old.inkColor != inkColor ||
      old.accentColor != accentColor;
}

/// Rasterises [DebugPagePainter] straight to a [ui.Image] without going
/// through the widget tree.
///
/// Used by geometry tests and the harness so a texture is available before the
/// first frame, with no `RepaintBoundary` timing to coordinate.
@internal
Future<ui.Image> renderDebugPageImage({
  required int pageNumber,
  required Size logicalSize,
  double pixelRatio = 1.0,
  bool isBackFace = false,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(pixelRatio);
  DebugPagePainter(pageNumber: pageNumber, isBackFace: isBackFace)
      .paint(canvas, logicalSize);
  final picture = recorder.endRecording();
  try {
    return picture.toImage(
      (logicalSize.width * pixelRatio).round(),
      (logicalSize.height * pixelRatio).round(),
    );
  } finally {
    picture.dispose();
  }
}
