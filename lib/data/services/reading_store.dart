import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Where you stopped: a page, how far down that page, and the zoom.
/// Positions are relative to the page, so they stay correct even while the
/// viewer is still measuring the other pages.
class ReadingPosition {
  const ReadingPosition({
    required this.page,
    required this.fx,
    required this.fy,
    required this.zoom,
  });

  final int page;
  final double fx;
  final double fy;
  final double zoom;
}

/// Per-document reading position, bookmarks and notes.
class ReadingStore {
  ReadingStore(this._prefs, this.path);

  final SharedPreferences _prefs;
  final String path;

  String get _positionKey => 'position:$path';
  String get _bookmarksKey => 'bookmarks:$path';
  String get _notesKey => 'notes:$path';

  ReadingPosition? loadPosition() {
    final raw = _prefs.getString(_positionKey);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return ReadingPosition(
        page: m['p'] as int,
        fx: (m['fx'] as num?)?.toDouble() ?? 0,
        fy: (m['fy'] as num?)?.toDouble() ?? 0,
        zoom: (m['z'] as num?)?.toDouble() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  void savePosition(ReadingPosition p) {
    _prefs.setString(
      _positionKey,
      jsonEncode({'p': p.page, 'fx': p.fx, 'fy': p.fy, 'z': p.zoom}),
    );
  }

  List<int> loadBookmarks() {
    final list = _prefs.getStringList(_bookmarksKey) ?? const <String>[];
    return [
      for (final s in list)
        if (int.tryParse(s) != null) int.parse(s),
    ]..sort();
  }

  void saveBookmarks(Iterable<int> pages) {
    _prefs.setStringList(_bookmarksKey, [for (final p in pages) '$p']);
  }

  String loadNotes() => _prefs.getString(_notesKey) ?? '';

  void saveNotes(String text) {
    if (text.isEmpty) {
      _prefs.remove(_notesKey);
    } else {
      _prefs.setString(_notesKey, text);
    }
  }
}
