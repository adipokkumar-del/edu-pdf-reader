import 'package:flutter/material.dart';

import '../../data/models/annotation_model.dart';
import '../../providers/annotation_provider.dart';

class DrawingCanvas extends StatefulWidget {
  const DrawingCanvas({
    super.key,
    required this.strokes,
    required this.enabled,
    required this.tool,
    required this.color,
    required this.onStroke,
    required this.onErase,
    required this.onEraseEnd,
  });

  final List<Stroke> strokes;
  final bool enabled;
  final AnnotTool tool;
  final Color color;
  final ValueChanged<Stroke> onStroke;
  final void Function(Offset normalized, double aspect) onErase;
  final VoidCallback onEraseEnd;

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  static const _penWidth = 0.005;
  static const _highlighterWidth = 0.03;

  final _live = _LiveStroke();
  int? _pointer;

  bool get _isHighlighter => widget.tool == AnnotTool.highlighter;
  double get _width => _isHighlighter ? _highlighterWidth : _penWidth;

  @override
  void dispose() {
    _live.dispose();
    super.dispose();
  }

  Offset _norm(Offset local) {
    final s = context.size!;
    return Offset(
      (local.dx / s.width).clamp(0.0, 1.0),
      (local.dy / s.height).clamp(0.0, 1.0),
    );
  }

  void _erase(Offset local) {
    final s = context.size!;
    widget.onErase(_norm(local), s.height / s.width);
  }

  void _down(PointerDownEvent e) {
    if (!widget.enabled || _pointer != null) return;
    _pointer = e.pointer;
    if (widget.tool == AnnotTool.eraser) {
      _erase(e.localPosition);
    } else {
      _live.start(_norm(e.localPosition));
    }
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    if (widget.tool == AnnotTool.eraser) {
      _erase(e.localPosition);
      return;
    }
    final n = _norm(e.localPosition);
    final distancePx = (n - _live.points.last).distance * context.size!.width;
    if (distancePx < 1.5) return;
    _live.add(n);
  }

  void _end(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (widget.tool == AnnotTool.eraser) {
      widget.onEraseEnd();
      return;
    }
    if (_live.points.isNotEmpty) {
      widget.onStroke(Stroke(
        points: List.of(_live.points),
        colorValue: widget.color.toARGB32(),
        width: _width,
        highlighter: _isHighlighter,
      ));
    }
    _live.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _end,
      onPointerCancel: _end,
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _StrokePainter(
            strokes: widget.strokes,
            live: _live,
            liveColor: widget.color,
            liveWidth: _width,
            liveHighlighter: _isHighlighter,
          ),
        ),
      ),
    );
  }
}

class _LiveStroke extends ChangeNotifier {
  final List<Offset> points = [];

  void start(Offset p) {
    points
      ..clear()
      ..add(p);
    notifyListeners();
  }

  void add(Offset p) {
    points.add(p);
    notifyListeners();
  }

  void clear() {
    points.clear();
    notifyListeners();
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter({
    required this.strokes,
    required this.live,
    required this.liveColor,
    required this.liveWidth,
    required this.liveHighlighter,
  }) : super(repaint: live);

  final List<Stroke> strokes;
  final _LiveStroke live;
  final Color liveColor;
  final double liveWidth;
  final bool liveHighlighter;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      _draw(canvas, size, s.points, s.color, s.width, s.highlighter);
    }
    if (live.points.isNotEmpty) {
      _draw(canvas, size, live.points, liveColor, liveWidth, liveHighlighter);
    }
  }

  void _draw(Canvas canvas, Size size, List<Offset> normalized, Color color,
      double width, bool highlighter) {
    final pts = [
      for (final o in normalized) Offset(o.dx * size.width, o.dy * size.height),
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
        ..strokeWidth = width * size.width
        ..color = highlighter ? color.withValues(alpha: 0.35) : color,
    );
  }

  @override
  bool shouldRepaint(_StrokePainter old) =>
      old.strokes != strokes ||
      old.liveColor != liveColor ||
      old.liveWidth != liveWidth ||
      old.liveHighlighter != liveHighlighter;
}
