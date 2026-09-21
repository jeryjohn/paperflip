import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'package:flip_book/src/flip_corner.dart';

/// Geometry of a single corner-anchored page fold.
///
/// Given the page [size], the dragged [corner] and a [progress] in `[0, 1]`,
/// this computes the fold crease line and the polygon of the lifted flap. It is
/// shared by [FlipBookWidget] (to clip the live page widgets) and
/// [PageFlipPainter] (to shade the curl), so the painted curl and the clipped
/// content always agree.
///
/// The model: the dragged corner travels in a straight line toward the opposite
/// horizontal edge. The fold crease is the perpendicular bisector of the segment
/// between the corner's original position and its dragged position — exactly how
/// a sheet of paper folds when you pull one corner across it.
class PageFoldGeometry {
  PageFoldGeometry({
    required this.size,
    required this.corner,
    required double progress,
  }) : progress = progress.clamp(0.0, 1.0) {
    _compute();
  }

  final Size size;
  final FlipCorner corner;
  final double progress;

  /// The corner's resting position.
  late final Offset cornerOrigin;

  /// The corner's current (dragged) position.
  late final Offset draggedCorner;

  /// The two points where the fold crease meets the page's top & bottom edges
  /// (for left/right corners) — the crease line endpoints.
  late final Offset creaseTop;
  late final Offset creaseBottom;

  /// Polygon (in page coordinates) covering the lifted flap — i.e. the part of
  /// the current page that has been turned over.
  late final Path flapPath;

  /// Polygon covering the part of the current page still flat on the book.
  late final Path stationaryPath;

  bool get isLeftCorner =>
      corner == FlipCorner.bottomLeft || corner == FlipCorner.topLeft;
  bool get isTopCorner =>
      corner == FlipCorner.topLeft || corner == FlipCorner.topRight;

  void _compute() {
    final w = size.width;
    final h = size.height;

    cornerOrigin = switch (corner) {
      FlipCorner.bottomRight => Offset(w, h),
      FlipCorner.bottomLeft => Offset(0, h),
      FlipCorner.topRight => Offset(w, 0),
      FlipCorner.topLeft => Offset.zero,
    };

    // The corner is dragged horizontally toward the opposite vertical edge.
    // A full progress drags it slightly past the far edge so the last sliver
    // can lie flat. Vertical position eases toward the page's vertical centre
    // to give the lift a natural diagonal arc.
    final targetX = isLeftCorner ? w : 0.0;
    final dragX = ui.lerpDouble(cornerOrigin.dx, targetX, progress)!;

    // Pull the corner inward vertically as it lifts (peak around mid-flip),
    // which makes the crease tilt diagonally instead of staying vertical.
    final arc = math.sin(progress * math.pi) * h * 0.18;
    final dragY = isTopCorner
        ? cornerOrigin.dy + arc
        : cornerOrigin.dy - arc;
    draggedCorner = Offset(dragX, dragY);

    // Crease = perpendicular bisector of (cornerOrigin → draggedCorner).
    final mid = Offset(
      (cornerOrigin.dx + draggedCorner.dx) / 2,
      (cornerOrigin.dy + draggedCorner.dy) / 2,
    );
    final dir = draggedCorner - cornerOrigin;
    final perp = Offset(-dir.dy, dir.dx);

    // 1. Find crease endpoints exactly on the page bounding box
    final ints = <Offset>[];
    if (perp.dy.abs() > 1e-6) {
      final tTop = (0 - mid.dy) / perp.dy;
      final xTop = mid.dx + perp.dx * tTop;
      if (xTop >= -1e-3 && xTop <= w + 1e-3) ints.add(Offset(xTop.clamp(0.0, w), 0));
      
      final tBottom = (h - mid.dy) / perp.dy;
      final xBottom = mid.dx + perp.dx * tBottom;
      if (xBottom >= -1e-3 && xBottom <= w + 1e-3) ints.add(Offset(xBottom.clamp(0.0, w), h));
    }
    if (perp.dx.abs() > 1e-6) {
      final tLeft = (0 - mid.dx) / perp.dx;
      final yLeft = mid.dy + perp.dy * tLeft;
      if (yLeft >= -1e-3 && yLeft <= h + 1e-3) ints.add(Offset(0, yLeft.clamp(0.0, h)));
      
      final tRight = (w - mid.dx) / perp.dx;
      final yRight = mid.dy + perp.dy * tRight;
      if (yRight >= -1e-3 && yRight <= h + 1e-3) ints.add(Offset(w, yRight.clamp(0.0, h)));
    }
    
    final uniqueInts = <Offset>[];
    for (final p in ints) {
      if (!uniqueInts.any((e) => (e - p).distance < 1e-3)) {
        uniqueInts.add(p);
      }
    }
    
    if (uniqueInts.length >= 2) {
      uniqueInts.sort((a, b) {
        if ((a.dy - b.dy).abs() > 1e-3) return a.dy.compareTo(b.dy);
        return a.dx.compareTo(b.dx);
      });
      creaseTop = uniqueInts.first;
      creaseBottom = uniqueInts.last;
    } else {
      creaseTop = mid;
      creaseBottom = mid;
    }

    _buildPaths(mid, dir);
  }

  void _buildPaths(Offset mid, Offset dir) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    
    // dir points from cornerOrigin to draggedCorner (into the stationary half-plane)
    stationaryPath = _clipRectByHalfPlane(rect, mid, dir);
    
    final liftedPath = _clipRectByHalfPlane(rect, mid, -dir);
    flapPath = liftedPath.transform(flapReflection.storage);
  }

  Path _clipRectByHalfPlane(Rect rect, Offset p, Offset normal) {
    final points = [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ];
    
    final out = <Offset>[];
    for (int i = 0; i < 4; i++) {
      final current = points[i];
      final next = points[(i + 1) % 4];
      
      final d1 = (current.dx - p.dx) * normal.dx + (current.dy - p.dy) * normal.dy;
      final d2 = (next.dx - p.dx) * normal.dx + (next.dy - p.dy) * normal.dy;
      
      if (d1 >= -1e-6) {
        out.add(current);
      }
      
      if ((d1 >= -1e-6) != (d2 >= -1e-6)) {
        final t = d1 / (d1 - d2);
        out.add(Offset(
          current.dx + t * (next.dx - current.dx),
          current.dy + t * (next.dy - current.dy),
        ));
      }
    }
    
    final path = Path();
    if (out.isEmpty) return path;
    
    path.moveTo(out[0].dx, out[0].dy);
    for (int i = 1; i < out.length; i++) {
      path.lineTo(out[i].dx, out[i].dy);
    }
    path.close();
    return path;
  }

  /// Matrix that maps the resting current-page content onto the lifted flap,
  /// i.e. a reflection across the crease line. Used to draw the *front* of the
  /// turning page in the correct (mirrored) position as it curls.
  Matrix4 get flapReflection {
    // Reflection across a line through `mid` with unit normal `n`:
    //   x' = x - 2 (x·n - d) n
    final dir = (draggedCorner - cornerOrigin);
    final len = dir.distance;
    if (len < 1e-6) return Matrix4.identity();
    final n = Offset(dir.dx / len, dir.dy / len); // crease normal == drag dir
    final mid = Offset(
      (cornerOrigin.dx + draggedCorner.dx) / 2,
      (cornerOrigin.dy + draggedCorner.dy) / 2,
    );
    final d = mid.dx * n.dx + mid.dy * n.dy;

    // 2D reflection matrix in homogeneous 4x4 form.
    final m = Matrix4.identity();
    m.setEntry(0, 0, 1 - 2 * n.dx * n.dx);
    m.setEntry(0, 1, -2 * n.dx * n.dy);
    m.setEntry(1, 0, -2 * n.dx * n.dy);
    m.setEntry(1, 1, 1 - 2 * n.dy * n.dy);
    m.setEntry(0, 3, 2 * d * n.dx);
    m.setEntry(1, 3, 2 * d * n.dy);
    return m;
  }
}

/// Paints the realistic shading of a page curl: the soft shadow the lifted flap
/// casts on the page beneath, the subtle gradient on the flap's back face, and
/// the bright crease highlight. The actual page *content* is drawn by the
/// widget (clipped/transformed via [PageFoldGeometry]); this painter only adds
/// the lighting that sells the curl.
class PageFlipPainter extends CustomPainter {
  const PageFlipPainter({
    required this.progress,
    required this.corner,
    required this.isForward,
    this.shadowColor = const Color(0x55000000),
    this.pageBackColor = const Color(0xFFEDEAE2),
    this.highlightColor = const Color(0x44FFFFFF),
    this.showShadow = true,
  });

  final double progress;
  final FlipCorner corner;
  final bool isForward;
  final Color shadowColor;
  final Color pageBackColor;
  final Color highlightColor;

  /// Whether to draw the crease shadow and highlight.
  ///
  /// The back face is always painted: it is what fills the lifted flap, so
  /// skipping it would leave a transparent hole showing the page beneath.
  final bool showShadow;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.001 || progress >= 0.999) return;

    final geo = PageFoldGeometry(
      size: size,
      corner: corner,
      progress: progress,
    );

    if (showShadow) _paintCreaseShadow(canvas, size, geo);
    _paintBackFace(canvas, geo);
    if (showShadow) _paintCreaseHighlight(canvas, geo);
  }

  /// Soft shadow cast just past the crease onto the stationary page.
  void _paintCreaseShadow(Canvas canvas, Size size, PageFoldGeometry geo) {
    // Shadow strength peaks mid-flip and fades at the ends.
    final intensity = math.sin(progress * math.pi);
    final color = shadowColor.withAlpha(
      (shadowColor.a * intensity).round().clamp(0, 255),
    );

    // Normal pointing away from the flap (toward the stationary side).
    final dir = geo.draggedCorner - geo.cornerOrigin;
    final len = dir.distance;
    if (len < 1e-6) return;
    final nu = dir / len;

    final depth = 26.0 * intensity;
    final p0 = geo.creaseTop;
    final p1 = geo.creaseTop + nu * depth;

    final shader = ui.Gradient.linear(
      p0,
      p1,
      [color, color.withAlpha(0)],
    );
    final paint = Paint()..shader = shader;

    final shadowPath = Path()
      ..moveTo(geo.creaseTop.dx, geo.creaseTop.dy)
      ..lineTo(geo.creaseBottom.dx, geo.creaseBottom.dy)
      ..lineTo(geo.creaseBottom.dx + nu.dx * depth,
          geo.creaseBottom.dy + nu.dy * depth)
      ..lineTo(geo.creaseTop.dx + nu.dx * depth,
          geo.creaseTop.dy + nu.dy * depth)
      ..close();

    canvas.save();
    canvas.clipPath(geo.stationaryPath);
    canvas.drawPath(shadowPath, paint);
    canvas.restore();
  }

  /// The back of the curling page: a paper-coloured fill with a gradient that
  /// darkens toward the crease, simulating the cylinder of the curl.
  void _paintBackFace(Canvas canvas, PageFoldGeometry geo) {
    final creaseMid = Offset(
      (geo.creaseTop.dx + geo.creaseBottom.dx) / 2,
      (geo.creaseTop.dy + geo.creaseBottom.dy) / 2,
    );

    final shader = ui.Gradient.linear(
      creaseMid,
      geo.draggedCorner,
      [
        _darken(pageBackColor, 0.12),
        pageBackColor,
      ],
    );
    final paint = Paint()..shader = shader;
    canvas.drawPath(geo.flapPath, paint);

    // A faint outline gives the flap a crisp turning edge.
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = _darken(pageBackColor, 0.25).withAlpha(120);
    canvas.drawPath(geo.flapPath, edge);
  }

  /// Bright specular line along the crease where the page bends.
  void _paintCreaseHighlight(Canvas canvas, PageFoldGeometry geo) {
    final intensity = math.sin(progress * math.pi);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = highlightColor.withAlpha(
        (highlightColor.a * intensity).round().clamp(0, 255),
      )
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 1.5);
    canvas.drawLine(geo.creaseTop, geo.creaseBottom, paint);
  }

  Color _darken(Color c, double amount) {
    return Color.fromARGB(
      c.a.round() == 0 ? 255 : (c.a * 255).round().clamp(0, 255),
      (c.r * 255 * (1 - amount)).round().clamp(0, 255),
      (c.g * 255 * (1 - amount)).round().clamp(0, 255),
      (c.b * 255 * (1 - amount)).round().clamp(0, 255),
    );
  }

  @override
  bool shouldRepaint(covariant PageFlipPainter old) =>
      old.progress != progress ||
      old.corner != corner ||
      old.isForward != isForward ||
      old.showShadow != showShadow ||
      old.shadowColor != shadowColor ||
      old.pageBackColor != pageBackColor ||
      old.highlightColor != highlightColor;
}
