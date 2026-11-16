import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import '../../core/utils/stroke_painting.dart';
import '../../data/models/annotation_model.dart';
import '../../providers/annotation_provider.dart';

/// Paints saved and in-progress strokes of one page. Never handles touches.
class PageStrokesLayer extends StatelessWidget {
  const PageStrokesLayer({super.key, required this.pageIndex});

  final int pageIndex;

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AnnotationProvider>();
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _StrokePainter(
          strokes: a.strokesFor(pageIndex),
          live: a.live,
          pageIndex: pageIndex,
          liveColor: a.color,
          liveWidth: a.currentWidth,
          liveOpacity: a.currentOpacity,
        ),
      ),
    );
  }
}

/// Full-screen touch layer used while annotating. It converts each touch
/// into page-relative coordinates, so strokes stay put at any zoom level.
class InkInputLayer extends StatefulWidget {
  const InkInputLayer({super.key, required this.controller});

  final PdfViewerController controller;

  @override
  State<InkInputLayer> createState() => _InkInputLayerState();
}

class _InkInputLayerState extends State<InkInputLayer> {
  int? _pointer;
  int _page = -1;
  Rect _rect = Rect.zero;

  Offset _toDoc(Offset local) => widget.controller.localToDocument(local);

  Offset _norm(Offset doc) => Offset(
        ((doc.dx - _rect.left) / _rect.width).clamp(0.0, 1.0),
        ((doc.dy - _rect.top) / _rect.height).clamp(0.0, 1.0),
      );

  void _erase(Offset doc) {
    context.read<AnnotationProvider>().eraseAt(
          _page,
          _norm(doc),
          _rect.height / _rect.width,
        );
  }

  void _down(PointerDownEvent e) {
    final c = widget.controller;
    if (_pointer != null || !c.isReady) return;

    final doc = _toDoc(e.localPosition);
    final rects = c.layout.pageLayouts;
    final index = rects.indexWhere((r) => r.inflate(6).contains(doc));
    if (index < 0) return;

    _pointer = e.pointer;
    _page = index;
    _rect = rects[index];

    final a = context.read<AnnotationProvider>();
    if (a.tool == AnnotTool.eraser) {
      _erase(doc);
    } else {
      a.live.start(index, _norm(doc));
    }
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final a = context.read<AnnotationProvider>();
    final doc = _toDoc(e.localPosition);

    if (a.tool == AnnotTool.eraser) {
      _erase(doc);
      return;
    }
    final n = _norm(doc);
    final stepPx = (n - a.live.points.last).distance *
        _rect.width *
        widget.controller.currentZoom;
    if (stepPx < 1.5) return;
    a.live.add(n);
  }

  void _end(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;

    final a = context.read<AnnotationProvider>();
    if (a.tool == AnnotTool.eraser) {
      a.endErase();
      return;
    }
    if (a.live.points.isNotEmpty) {
      a.addStroke(
        _page,
        Stroke(
          points: List.of(a.live.points),
          colorValue: a.color.toARGB32(),
          width: a.currentWidth,
          opacity: a.currentOpacity,
        ),
      );
    }
    a.live.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _end,
      onPointerCancel: _end,
      child: const SizedBox.expand(),
    );
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter({
    required this.strokes,
    required this.live,
    required this.pageIndex,
    required this.liveColor,
    required this.liveWidth,
    required this.liveOpacity,
  }) : super(repaint: live);

  final List<Stroke> strokes;
  final LiveStroke live;
  final int pageIndex;
  final Color liveColor;
  final double liveWidth;
  final double liveOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      paintStroke(canvas, size, s);
    }
    if (live.page == pageIndex && live.points.isNotEmpty) {
      paintStroke(
        canvas,
        size,
        Stroke(
          points: live.points,
          colorValue: liveColor.toARGB32(),
          width: liveWidth,
          opacity: liveOpacity,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_StrokePainter old) =>
      old.strokes != strokes ||
      old.pageIndex != pageIndex ||
      old.liveColor != liveColor ||
      old.liveWidth != liveWidth ||
      old.liveOpacity != liveOpacity;
}
