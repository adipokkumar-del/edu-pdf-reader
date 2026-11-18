import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/services/reading_store.dart';

class RecentEntry {
  const RecentEntry(this.path, this.openedAt);

  final String path;
  final int openedAt;

  String get name => p.basenameWithoutExtension(path);
}

/// The last PDFs you opened, newest first.
class RecentProvider extends ChangeNotifier {
  RecentProvider(this._prefs) {
    _load();
  }

  static const _key = 'recent_files_v1';
  static const maxItems = 12;

  final SharedPreferences _prefs;
  List<RecentEntry> entries = const [];

  void _load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      entries = [
        for (final e in list)
          RecentEntry(
            (e as Map<String, dynamic>)['p'] as String,
            e['t'] as int,
          ),
      ];
    } catch (_) {
      entries = const [];
    }
  }

  void _save() {
    _prefs.setString(
      _key,
      jsonEncode([
        for (final e in entries) {'p': e.path, 't': e.openedAt},
      ]),
    );
  }

  void touch(String path) {
    final now = DateTime.now().millisecondsSinceEpoch;
    entries = [
      RecentEntry(path, now),
      ...entries.where((e) => e.path != path),
    ].take(maxItems).toList();
    _save();
    notifyListeners();
  }

  void remove(String path) {
    entries = entries.where((e) => e.path != path).toList();
    _save();
    notifyListeners();
  }

  void clear() {
    entries = const [];
    _save();
    notifyListeners();
  }

  int? lastPage(String path) => ReadingStore(_prefs, path).loadPosition()?.page;
}
