import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/stroke_painting.dart';
import '../../data/models/annotation_model.dart';

enum SketchTool { pen, marker, brush, highlighter, eraser }

class _Brush {
  const _Brush(this.width, this.opacity, this.kind);

  /// Fraction of the sheet width.
  final double width;
  final double opacity;
  final int kind;
}

const _brushes = <SketchTool, _Brush>{
  SketchTool.pen: _Brush(0.0055, 1.0, StrokeKind.pen),
  SketchTool.marker: _Brush(0.016, 0.85, StrokeKind.marker),
  SketchTool.brush: _Brush(0.012, 1.0, StrokeKind.brush),
  SketchTool.highlighter: _Brush(0.045, 0.6, StrokeKind.highlighter),
};

/// Width divided by height of the drawing sheet.
const double sketchAspect = 0.8;

const _palette = <Color>[
  Color(0xFF3E2723),
  Color(0xFF212121),
  Color(0xFFC62828),
  Color(0xFF1565C0),
  Color(0xFF2E7D32),
  Color(0xFFF9A825),
];

class _Live extends ChangeNotifier {
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

class _SketchPainter extends CustomPainter {
  _SketchPainter({
    required this.strokes,
    this.live,
    this.liveColor = const Color(0xFF000000),
    this.liveWidth = 0,
    this.liveOpacity = 1,
    this.liveKind = StrokeKind.pen,
  }) : super(repaint: live);

  final List<Stroke> strokes;
  final _Live? live;
  final Color liveColor;
  final double liveWidth;
  final double liveOpacity;
  final int liveKind;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      paintStroke(canvas, size, s);
    }
    final l = live;
    if (l != null && l.points.isNotEmpty) {
      paintStroke(
        canvas,
        size,
        Stroke(
          points: l.points,
          colorValue: liveColor.toARGB32(),
          width: liveWidth,
          opacity: liveOpacity,
          kind: liveKind,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_SketchPainter old) =>
      old.strokes != strokes ||
      old.liveColor != liveColor ||
      old.liveWidth != liveWidth ||
      old.liveOpacity != liveOpacity ||
      old.liveKind != liveKind;
}

/// Small read-only view of a drawing (used on note cards and in the editor).
class SketchPreview extends StatelessWidget {
  const SketchPreview({super.key, required this.strokes, this.height = 120});

  final List<Stroke> strokes;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: height * sketchAspect,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: CustomPaint(painter: _SketchPainter(strokes: strokes)),
    );
  }
}

/// Full-screen drawing sheet. Returns the strokes when closed.
class SketchScreen extends StatefulWidget {
  const SketchScreen({super.key, required this.initial});

  final List<Stroke> initial;

  @override
  State<SketchScreen> createState() => _SketchScreenState();
}

class _SketchScreenState extends State<SketchScreen> {
  late List<Stroke> _strokes = List.of(widget.initial);
  final List<List<Stroke>> _undo = [];
  final _live = _Live();

  SketchTool _tool = SketchTool.pen;
  int _color = 0;
  double _size = 1.0;
  bool _erasing = false;
  int? _pointer;
  Size _box = Size.zero;

  @override
  void dispose() {
    _live.dispose();
    super.dispose();
  }

  void _remember() {
    _undo.add(List.of(_strokes));
    if (_undo.length > 40) _undo.removeAt(0);
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    setState(() => _strokes = _undo.removeLast());
  }

  void _clear() {
    _remember();
    setState(() => _strokes = []);
  }

  Offset _norm(Offset local) => Offset(
        (local.dx / _box.width).clamp(0.0, 1.0),
        (local.dy / _box.height).clamp(0.0, 1.0),
      );

  void _erase(Offset n) {
    final kept =
        _strokes.where((s) => !s.isNear(n, 1 / sketchAspect, 0.03)).toList();
    if (kept.length == _strokes.length) return;
    if (!_erasing) {
      _remember();
      _erasing = true;
    }
    setState(() => _strokes = kept);
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null || _box.isEmpty) return;
    _pointer = e.pointer;
    final n = _norm(e.localPosition);
    if (_tool == SketchTool.eraser) {
      _erasing = false;
      _erase(n);
    } else {
      _live.start(n);
    }
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final n = _norm(e.localPosition);
    if (_tool == SketchTool.eraser) {
      _erase(n);
      return;
    }
    if ((n - _live.points.last).distance * _box.width < 1.5) return;
    _live.add(n);
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;

    if (_tool == SketchTool.eraser) {
      _erasing = false;
      return;
    }
    if (_live.points.isNotEmpty) {
      final brush = _brushes[_tool]!;
      _remember();
      setState(() {
        _strokes = [
          ..._strokes,
          Stroke(
            points: List.of(_live.points),
            colorValue: _palette[_color].toARGB32(),
            width: brush.width * _size,
            opacity: brush.opacity,
            kind: brush.kind,
          ),
        ];
      });
    }
    _live.clear();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _strokes);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Drawing'),
          actions: [
            IconButton(
              tooltip: 'Clear all',
              icon: const Icon(Icons.layers_clear_rounded),
              onPressed: _strokes.isEmpty ? null : _clear,
            ),
            IconButton(
              tooltip: 'Done',
              icon: const Icon(Icons.check_rounded),
              onPressed: () => Navigator.pop(context, _strokes),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(builder: (context, c) => _sheet(c)),
        ),
        bottomNavigationBar: _toolbar(),
      ),
    );
  }

  Widget _sheet(BoxConstraints c) {
    var w = c.maxWidth;
    var h = w / sketchAspect;
    if (h > c.maxHeight) {
      h = c.maxHeight;
      w = h * sketchAspect;
    }
    _box = Size(w, h);

    final brush = _brushes[_tool];

    return Center(
      child: SizedBox(
        width: w,
        height: h,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.divider),
            boxShadow: [
              BoxShadow(
                color: AppColors.brownDark.withValues(alpha: 0.1),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRect(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
              onPointerCancel: _up,
              child: RepaintBoundary(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _SketchPainter(
                    strokes: _strokes,
                    live: _live,
                    liveColor: _palette[_color],
                    liveWidth: (brush?.width ?? 0.0065) * _size,
                    liveOpacity: brush?.opacity ?? 1,
                    liveKind: brush?.kind ?? StrokeKind.pen,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolbar() {
    const tools = [
      (SketchTool.pen, Icons.edit_rounded, 'Pen'),
      (SketchTool.marker, Icons.border_color_rounded, 'Marker'),
      (SketchTool.brush, Icons.brush_rounded, 'Brush'),
      (SketchTool.highlighter, Icons.highlight_rounded, 'Highlighter'),
      (SketchTool.eraser, Icons.auto_fix_normal_rounded, 'Eraser'),
    ];

    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  for (final (tool, icon, label) in tools)
                    IconButton(
                      tooltip: label,
                      onPressed: () => setState(() => _tool = tool),
                      icon: Icon(icon),
                      style: IconButton.styleFrom(
                        backgroundColor:
                            _tool == tool ? AppColors.brown : Colors.transparent,
                        foregroundColor:
                            _tool == tool ? Colors.white : AppColors.brownDark,
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Undo',
                    onPressed: _undo.isEmpty ? null : _undoLast,
                    icon: const Icon(Icons.undo_rounded),
                    color: AppColors.brownDark,
                  ),
                ],
              ),
              if (_tool == SketchTool.eraser)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Touch a stroke to remove it',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              else
                Row(
                  children: [
                    for (var i = 0; i < _palette.length; i++)
                      GestureDetector(
                        onTap: () => setState(() => _color = i),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: _palette[i],
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _color == i
                                    ? AppColors.brownDark
                                    : AppColors.brownLight,
                                width: _color == i ? 3 : 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Slider(
                        value: _size,
                        min: 0.6,
                        max: 2.2,
                        activeColor: AppColors.brown,
                        onChanged: (v) => setState(() => _size = v),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
