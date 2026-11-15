import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/file_helper.dart';
import '../core/utils/permission_helper.dart';
import '../data/models/pdf_document_model.dart';

enum LibraryStatus { loading, needsPermission, ready, error }

enum SortOption {
  fileName('Name'),
  dateModified('Date'),
  fileSize('Size');

  const SortOption(this.label);
  final String label;
}

class LibraryProvider extends ChangeNotifier {
  LibraryProvider(this._prefs);

  static const _sortKey = 'library_sort_option';
  static const _ascendingKey = 'library_sort_ascending';

  final SharedPreferences _prefs;

  List<PdfDocumentModel> _all = const [];
  List<PdfDocumentModel> _visible = const [];
  LibraryStatus _status = LibraryStatus.loading;
  SortOption _sort = SortOption.fileName;
  bool _ascending = true;
  String _query = '';

  LibraryStatus get status => _status;
  List<PdfDocumentModel> get documents => _visible;
  SortOption get sort => _sort;
  bool get ascending => _ascending;

  Future<void> init() async {
    final saved = _prefs.getString(_sortKey);
    _sort = SortOption.values.firstWhere(
      (o) => o.name == saved,
      orElse: () => SortOption.fileName,
    );
    _ascending = _prefs.getBool(_ascendingKey) ?? true;
    await loadLibrary();
  }

  Future<void> loadLibrary({bool silent = false}) async {
    if (!silent) {
      _status = LibraryStatus.loading;
      notifyListeners();
    }

    if (!await PermissionHelper.hasAccess()) {
      _status = LibraryStatus.needsPermission;
      notifyListeners();
      return;
    }
    await _scan();
  }

  Future<void> requestPermissionAndLoad() async {
    final granted = await PermissionHelper.request();
    if (!granted) {
      _status = LibraryStatus.needsPermission;
      notifyListeners();
      return;
    }
    _status = LibraryStatus.loading;
    notifyListeners();
    await _scan();
  }

  Future<void> _scan() async {
    try {
      _all = await PdfScanner.scan();
      _status = LibraryStatus.ready;
    } catch (_) {
      _status = LibraryStatus.error;
    }
    _apply();
    notifyListeners();
  }

  void setSort(SortOption option) {
    if (option == _sort) {
      _ascending = !_ascending;
    } else {
      _sort = option;
      _ascending = option == SortOption.fileName;
    }
    _prefs.setString(_sortKey, _sort.name);
    _prefs.setBool(_ascendingKey, _ascending);
    _apply();
    notifyListeners();
  }

  void setQuery(String query) {
    _query = query;
    _apply();
    notifyListeners();
  }

  void _apply() {
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? List<PdfDocumentModel>.of(_all)
        : _all.where((d) => d.name.toLowerCase().contains(q)).toList();

    list.sort((a, b) {
      final c = switch (_sort) {
        SortOption.fileName =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        SortOption.dateModified => a.modified.compareTo(b.modified),
        SortOption.fileSize => a.sizeBytes.compareTo(b.sizeBytes),
      };
      return _ascending ? c : -c;
    });
    _visible = list;
  }
}
