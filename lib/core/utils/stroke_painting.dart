import 'dart:math' as math;
import 'dart:ui';

import '../../data/models/annotation_model.dart';

/// Draws one stroke. Shared by the on-screen layer and the PDF export.
void paintStroke(Canvas canvas, Size size, Stroke stroke) {
  if (stroke.points.isEmpty) return;

  final pts = [
    for (final o in stroke.points)
      Offset(o.dx * size.width, o.dy * size.height),
  ];
  final width = stroke.width * size.width;

  if (stroke.kind == StrokeKind.brush) {
    _paintBrush(canvas, pts, stroke, width);
    return;
  }

  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  if (pts.length == 1) {
    path.lineTo(pts.first.dx + 0.01, pts.first.dy);
  } else {
    for (var i = 1; i < pts.length - 1; i++) {
      final mid = (pts[i] + pts[i + 1]) / 2;
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
  }

  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = width
    ..color = stroke.color.withValues(alpha: stroke.opacity);

  switch (stroke.kind) {
    case StrokeKind.marker:
      // Flat felt tip: square ends, ink darkens where it overlaps the page.
      paint
        ..strokeCap = StrokeCap.square
        ..blendMode = BlendMode.multiply;
    case StrokeKind.highlighter:
      // Multiply keeps the dark text readable and only tints the background.
      paint
        ..strokeCap = StrokeCap.butt
        ..strokeJoin = StrokeJoin.bevel
        ..blendMode = BlendMode.multiply;
    default:
      paint.strokeCap = StrokeCap.round;
  }
  canvas.drawPath(path, paint);
}

/// Brush: thicker when the hand moves slowly, thinner when fast,
/// with tapered start and end like a real ink brush.
void _paintBrush(Canvas canvas, List<Offset> pts, Stroke stroke, double base) {
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = stroke.color.withValues(alpha: stroke.opacity);

  if (pts.length == 1) {
    canvas.drawCircle(
      pts.first,
      base * 0.6,
      Paint()..color = paint.color,
    );
    return;
  }

  final n = pts.length;
  var w = base;
  for (var i = 1; i < n; i++) {
    final d = (pts[i] - pts[i - 1]).distance;
    final target = base * (1.5 - (d / (base * 2.2)).clamp(0.0, 1.0) * 0.95);
    w = w * 0.75 + target * 0.25;
    final edge = math.min(i, n - i) / 6.0;
    final taper = edge >= 1 ? 1.0 : 0.3 + 0.7 * edge;
    paint.strokeWidth = math.max(w * taper, base * 0.2);
    canvas.drawLine(pts[i - 1], pts[i], paint);
  }
}
