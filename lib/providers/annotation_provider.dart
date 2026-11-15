import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/annotation_model.dart';

enum AnnotTool { pen, highlighter, eraser }

class AnnotationProvider extends ChangeNotifier {
  AnnotationProvider(this._prefs, this.path) {
    _load();
  }

  static const palette = [
    Color(0xFF6D4C41),
    Color(0xFFC62828),
    Color(0xFF1565C0),
    Color(0xFFF9A825),
  ];

  final SharedPreferences _prefs;
  final String path;

  final Map<int, List<Stroke>> _pages = {};
  final List<(int, List<Stroke>)> _undo = [];
  bool _erasing = false;

  bool drawing = false;
  AnnotTool tool = AnnotTool.pen;
  Color color = palette.first;

  String get _key => 'annotations:$path';

  List<Stroke> strokesFor(int page) => _pages[page] ?? const [];
  bool get canUndo => _undo.isNotEmpty;

  void setDrawing(bool value) {
    drawing = value;
    notifyListeners();
  }

  void setTool(AnnotTool value) {
    tool = value;
    notifyListeners();
  }

  void setColor(Color value) {
    color = value;
    notifyListeners();
  }

  void addStroke(int page, Stroke stroke) {
    _snapshot(page);
    _pages[page] = [...strokesFor(page), stroke];
    _save();
    notifyListeners();
  }

  /// Removes strokes near [at] (normalized). Returns true if anything changed.
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
}
