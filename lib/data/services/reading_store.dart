import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ReadingPosition {
  const ReadingPosition({
    required this.page,
    required this.x,
    required this.y,
    required this.zoom,
  });

  final int page;
  final double x;
  final double y;
  final double zoom;
}

/// Per-document reading position and bookmarks.
class ReadingStore {
  ReadingStore(this._prefs, this.path);

  final SharedPreferences _prefs;
  final String path;

  String get _positionKey => 'position:$path';
  String get _bookmarksKey => 'bookmarks:$path';

  ReadingPosition? loadPosition() {
    final raw = _prefs.getString(_positionKey);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return ReadingPosition(
        page: m['p'] as int,
        x: (m['x'] as num).toDouble(),
        y: (m['y'] as num).toDouble(),
        zoom: (m['z'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  void savePosition(ReadingPosition p) {
    _prefs.setString(
      _positionKey,
      jsonEncode({'p': p.page, 'x': p.x, 'y': p.y, 'z': p.zoom}),
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
}
