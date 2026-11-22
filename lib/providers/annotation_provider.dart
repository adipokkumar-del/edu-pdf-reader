import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/annotation_model.dart';

enum AnnotTool { pen, marker, brush, highlighter, eraser }

class BrushSpec {
  const BrushSpec(this.width, this.opacity);

  /// Fraction of page width.
  final double width;
  final double opacity;
}

/// The stroke being drawn right now. Painters listen to it directly,
/// so drawing never rebuilds the rest of the UI.
class LiveStroke extends ChangeNotifier {
  int page = -1;
  final List<Offset> points = [];

  void start(int pageIndex, Offset p) {
    page = pageIndex;
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
    page = -1;
    notifyListeners();
  }
}

class AnnotationProvider extends ChangeNotifier {
  AnnotationProvider(this._prefs, this.path) {
    _load();
    _loadInk();
  }

  static const brushes = <AnnotTool, BrushSpec>{
    AnnotTool.pen: BrushSpec(0.0032, 1.0),
    AnnotTool.marker: BrushSpec(0.0095, 0.85),
    AnnotTool.brush: BrushSpec(0.0070, 1.0),
    AnnotTool.highlighter: BrushSpec(0.024, 0.6),
  };

  /// Bright colours for the highlighter (dark colours would hide the text).
  static const highlightPalette = <Color>[
    Color(0xFFFFEB3B),
    Color(0xFF76FF03),
    Color(0xFFFF80AB),
    Color(0xFF40C4FF),
    Color(0xFFFFAB40),
    Color(0xFFB388FF),
    Color(0xFF69F0AE),
  ];

  static const defaultPalette = <Color>[
    Color(0xFF3E2723),
    Color(0xFF212121),
    Color(0xFFC62828),
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFFEF6C00),
    Color(0xFFF9A825),
  ];

  final SharedPreferences _prefs;
  final String path;
  final LiveStroke live = LiveStroke();

  final Map<int, List<Stroke>> _pages = {};
  final List<(int, List<Stroke>)> _undo = [];
  bool _erasing = false;

  bool drawing = false;

  /// While true, one-finger gestures scroll/zoom the PDF instead of drawing.
  bool hand = false;

  AnnotTool tool = AnnotTool.pen;
  List<Color> palette = List.of(defaultPalette);
  List<Color> hlPalette = List.of(highlightPalette);
  int colorIndex = 0;
  int hlIndex = 0;
  double sizeScale = 1.0;

  String get _key => 'annotations:$path';

  bool get _hl => tool == AnnotTool.highlighter;
  List<Color> get activePalette => _hl ? hlPalette : palette;
  int get activeIndex => _hl ? hlIndex : colorIndex;
  Color get color => activePalette[activeIndex];
  int get currentKind => switch (tool) {
        AnnotTool.marker => StrokeKind.marker,
        AnnotTool.brush => StrokeKind.brush,
        AnnotTool.highlighter => StrokeKind.highlighter,
        _ => StrokeKind.pen,
      };
  double get currentWidth => (brushes[tool]?.width ?? 0.004) * sizeScale;
  double get currentOpacity => brushes[tool]?.opacity ?? 1.0;

  List<Stroke> strokesFor(int page) => _pages[page] ?? const [];
  bool get canUndo => _undo.isNotEmpty;

  /// Every page that has at least one stroke (0-based page index).
  Map<int, List<Stroke>> get allStrokes => {
        for (final e in _pages.entries)
          if (e.value.isNotEmpty) e.key: List.unmodifiable(e.value),
      };

  // ---- Mode / tool --------------------------------------------------------

  void setDrawing(bool value) {
    drawing = value;
    if (!value) {
      hand = false;
      live.clear();
    }
    notifyListeners();
  }

  void setHand(bool value) {
    hand = value;
    notifyListeners();
  }

  void setTool(AnnotTool value) {
    tool = value;
    hand = false;
    notifyListeners();
  }

  void setColorIndex(int index) {
    if (_hl) {
      hlIndex = index;
      _prefs.setInt('hl_color_index', index);
    } else {
      colorIndex = index;
      _prefs.setInt('ink_color_index', index);
    }
    notifyListeners();
  }

  void editPaletteColor(int index, Color value) {
    if (_hl) {
      hlPalette = List.of(hlPalette)..[index] = value;
      _prefs.setStringList(
        'hl_palette',
        [for (final c in hlPalette) '${c.toARGB32()}'],
      );
    } else {
      palette = List.of(palette)..[index] = value;
      _prefs.setStringList(
        'ink_palette',
        [for (final c in palette) '${c.toARGB32()}'],
      );
    }
    notifyListeners();
  }

  void setSize(double value) {
    sizeScale = value;
    _prefs.setDouble('ink_size', value);
    notifyListeners();
  }

  // ---- Strokes ------------------------------------------------------------

  void addStroke(int page, Stroke stroke) {
    _snapshot(page);
    _pages[page] = [...strokesFor(page), stroke];
    _save();
    notifyListeners();
  }

  /// [at] is normalized (0..1); [aspect] is page height / page width.
  bool eraseAt(int page, Offset at, double aspect, {double radius = 0.03}) {
    final current = strokesFor(page);
    final kept =
        current.where((s) => !s.isNear(at, aspect, radius)).toList();
    if (kept.length == current.length) return false;
    if (!_erasing) {
      _snapshot(page);
      _erasing = true;
    }
    _pages[page] = kept;
    notifyListeners();
    return true;
  }

  void endErase() {
    if (_erasing) _save();
    _erasing = false;
  }

  void undo() {
    if (_undo.isEmpty) return;
    final (page, strokes) = _undo.removeLast();
    _pages[page] = strokes;
    _save();
    notifyListeners();
  }

  void _snapshot(int page) {
    _undo.add((page, List.of(strokesFor(page))));
    if (_undo.length > 50) _undo.removeAt(0);
  }

  // ---- Persistence --------------------------------------------------------

  void _loadInk() {
    final saved = _prefs.getStringList('ink_palette');
    if (saved != null && saved.length == defaultPalette.length) {
      final parsed = [for (final s in saved) int.tryParse(s)];
      if (!parsed.contains(null)) {
        palette = [for (final v in parsed) Color(v!)];
      }
    }
    final hlSaved = _prefs.getStringList('hl_palette');
    if (hlSaved != null && hlSaved.length == highlightPalette.length) {
      final parsed = [for (final s in hlSaved) int.tryParse(s)];
      if (!parsed.contains(null)) {
        hlPalette = [for (final v in parsed) Color(v!)];
      }
    }
    hlIndex = (_prefs.getInt('hl_color_index') ?? 0)
        .clamp(0, highlightPalette.length - 1);
    colorIndex = (_prefs.getInt('ink_color_index') ?? 0)
        .clamp(0, defaultPalette.length - 1);
    sizeScale = (_prefs.getDouble('ink_size') ?? 1.0).clamp(0.5, 2.5);
  }

  void _load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      data.forEach((page, list) {
        _pages[int.parse(page)] = [
          for (final s in list as List)
            Stroke.fromJson(s as Map<String, dynamic>),
        ];
      });
    } catch (_) {
      _pages.clear();
    }
  }

  void _save() {
    final data = {
      for (final e in _pages.entries)
        if (e.value.isNotEmpty)
          '${e.key}': [for (final s in e.value) s.toJson()],
    };
    _prefs.setString(_key, jsonEncode(data));
  }

  @override
  void dispose() {
    live.dispose();
    super.dispose();
  }
}
