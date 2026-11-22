import 'dart:math' as math;

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
          liveKind: a.currentKind,
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
  bool _busy = false;
  final Map<int, List<Rect>> _textRects = {};

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
    if (_pointer != null || _busy || !c.isReady) return;

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
      _commit(a, _page, _rect, List.of(a.live.points));
    } else {
      a.live.clear();
    }
  }

  Future<void> _commit(
    AnnotationProvider a,
    int page,
    Rect rect,
    List<Offset> points,
  ) async {
    var width = a.currentWidth;
    final kind = a.currentKind;
    final colorValue = a.color.toARGB32();
    final opacity = a.currentOpacity;

    if (kind == StrokeKind.highlighter) {
      _busy = true;
      try {
        final snapped = await _snapToTextLine(page, rect, points, width);
        if (snapped != null) {
          points = snapped.$1;
          width = snapped.$2;
        }
      } catch (_) {
        // Keep the hand-drawn stroke if the text could not be read.
      }
      _busy = false;
    }

    if (!mounted) return;
    a.addStroke(
      page,
      Stroke(
        points: points,
        colorValue: colorValue,
        width: width,
        opacity: opacity,
        kind: kind,
      ),
    );
    a.live.clear();
  }

  /// Text boxes of a page, normalized to 0..1 (top-left origin).
  Future<List<Rect>> _rectsFor(int pageIndex) async {
    final cached = _textRects[pageIndex];
    if (cached != null) return cached;
    final out = <Rect>[];
    try {
      final page = widget.controller.document.pages[pageIndex];
      final pw = page.width;
      final ph = page.height;
      final dynamic text = await page.loadText();
      final dynamic fragments = text?.fragments;
      if (fragments != null) {
        for (final dynamic f in fragments) {
          final dynamic b = f.bounds;
          final l = (b.left as num).toDouble();
          final r = (b.right as num).toDouble();
          final t = (b.top as num).toDouble();
          final bt = (b.bottom as num).toDouble();
          final top = (ph - math.max(t, bt)) / ph;
          final bottom = (ph - math.min(t, bt)) / ph;
          if (bottom > top) {
            out.add(Rect.fromLTRB(math.min(l, r) / pw, top, math.max(l, r) / pw, bottom));
          }
        }
      }
    } catch (_) {}
    _textRects[pageIndex] = out;
    return out;
  }

  /// Turns a rough highlighter swipe into a clean bar over the text line.
  /// Returns null (keeps the free stroke) for scanned pages or multi-line swipes.
  Future<(List<Offset>, double)?> _snapToTextLine(
    int page,
    Rect rect,
    List<Offset> pts,
    double fallbackWidth,
  ) async {
    final rects = await _rectsFor(page);
    if (rects.isEmpty) return null;

    var minX = 1.0, maxX = 0.0, minY = 1.0, maxY = 0.0, sumY = 0.0;
    for (final p in pts) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
      sumY += p.dy;
    }
    final y = sumY / pts.length;

    // The text box closest to the swipe's vertical centre.
    Rect? best;
    var bestGap = 0.02;
    for (final r in rects) {
      final gap = y < r.top ? r.top - y : (y > r.bottom ? y - r.bottom : 0.0);
      if (gap < bestGap) {
        bestGap = gap;
        best = r;
      }
    }
    if (best == null) return null;

    // Join every text box that sits on the same line.
    final mid = (best.top + best.bottom) / 2;
    final half = (best.bottom - best.top) / 2;
    var top = best.top, bottom = best.bottom;
    var left = best.left, right = best.right;
    for (final r in rects) {
      final rm = (r.top + r.bottom) / 2;
      if ((rm - mid).abs() <= half * 0.6) {
        top = math.min(top, r.top);
        bottom = math.max(bottom, r.bottom);
        left = math.min(left, r.left);
        right = math.max(right, r.right);
      }
    }

    final lineH = bottom - top;
    if (maxY - minY > lineH * 1.5) return null;

    var xa = minX, xb = maxX;
    if (xb - xa < 0.01) {
      xa = left; // a tap highlights the whole line
      xb = right;
    }
    xa = xa.clamp(left, right);
    xb = xb.clamp(left, right);
    if (xb - xa < 0.005) return null;

    final aspect = rect.height / rect.width;
    final widthFraction = lineH * aspect * 1.1;
    final yMid = (top + bottom) / 2;
    return ([Offset(xa, yMid), Offset(xb, yMid)], widthFraction);
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
    required this.liveKind,
  }) : super(repaint: live);

  final List<Stroke> strokes;
  final LiveStroke live;
  final int pageIndex;
  final Color liveColor;
  final double liveWidth;
  final double liveOpacity;
  final int liveKind;

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
          kind: liveKind,
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
      old.liveOpacity != liveOpacity ||
      old.liveKind != liveKind;
}
