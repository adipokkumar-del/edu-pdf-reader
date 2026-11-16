import 'dart:ui';

import '../../data/models/annotation_model.dart';

/// Draws one stroke. Shared by the on-screen layer and the PDF export.
void paintStroke(Canvas canvas, Size size, Stroke stroke) {
  if (stroke.points.isEmpty) return;

  final pts = [
    for (final o in stroke.points)
      Offset(o.dx * size.width, o.dy * size.height),
  ];
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

  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = stroke.width * size.width
      ..color = stroke.color.withValues(alpha: stroke.opacity),
  );
}
