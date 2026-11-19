import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_colors.dart';
import '../../providers/library_provider.dart';
import '../../providers/recent_provider.dart';
import '../models/pdf_document_model.dart';
import '../models/task_model.dart' show formatTime;
import 'reading_store.dart';

/// Rename, delete, details and share for a PDF in the library.
abstract final class FileActions {
  static const _keyPrefixes = ['position', 'bookmarks', 'notes', 'annotations'];
  static final _illegal = RegExp(r'[\\/:*?"<>|]');
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static Future<void> share(PdfDocumentModel doc) =>
      Share.shareXFiles([XFile(doc.path)], subject: doc.name);

  // ---- Rename -------------------------------------------------------------

  static Future<void> rename(BuildContext context, PdfDocumentModel doc) async {
    final ext = p.extension(doc.path);
    final dir = p.dirname(doc.path);
    final controller = TextEditingController(text: doc.name);
    controller.selection =
        TextSelection(baseOffset: 0, extentOffset: doc.name.length);
    String? error;

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          void submit() {
            final value = controller.text.trim();
            if (value.isEmpty) {
              setState(() => error = 'Enter a name');
            } else if (_illegal.hasMatch(value)) {
              setState(
                () => error = 'These characters are not allowed: \\ / : * ? " < > |',
              );
            } else if (value != doc.name &&
                File(p.join(dir, '$value$ext')).existsSync()) {
              setState(() => error = 'A file with this name already exists');
            } else {
              Navigator.pop(ctx, value);
            }
          }

          return AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('Rename PDF'),
            content: TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => submit(),
              decoration: InputDecoration(
                suffixText: ext,
                errorText: error,
                errorMaxLines: 2,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(onPressed: submit, child: const Text('Rename')),
            ],
          );
        },
      ),
    );

    if (newName == null || newName == doc.name || !context.mounted) return;

    final target = p.join(dir, '$newName$ext');
    try {
      await File(doc.path).rename(target);
    } catch (_) {
      if (context.mounted) _snack(context, 'Could not rename this file.');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await _moveKeys(prefs, doc.path, target);
    if (!context.mounted) return;

    context.read<RecentProvider>().rename(doc.path, target);
    context.read<LibraryProvider>().applyRename(
          doc.path,
          PdfDocumentModel(
            path: target,
            name: newName,
            sizeBytes: doc.sizeBytes,
            modified: doc.modified,
          ),
        );
    _snack(context, 'Renamed');
  }

  /// Notes, bookmarks, drawings and reading position follow the new name.
  static Future<void> _moveKeys(
    SharedPreferences prefs,
    String from,
    String to,
  ) async {
    for (final prefix in _keyPrefixes) {
      final value = prefs.get('$prefix:$from');
      if (value == null) continue;
      if (value is String) {
        await prefs.setString('$prefix:$to', value);
      } else if (value is List) {
        await prefs.setStringList('$prefix:$to', value.cast<String>());
      }
      await prefs.remove('$prefix:$from');
    }
  }

  // ---- Delete -------------------------------------------------------------

  static Future<void> delete(BuildContext context, PdfDocumentModel doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Delete this PDF?'),
        content: Text(
          '"${doc.name}" will be permanently removed from your phone, '
          'together with its notes, bookmarks and drawings in this app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await File(doc.path).delete();
    } catch (_) {
      if (context.mounted) _snack(context, 'Could not delete this file.');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    for (final prefix in _keyPrefixes) {
      await prefs.remove('$prefix:${doc.path}');
    }
    if (!context.mounted) return;

    context.read<RecentProvider>().remove(doc.path);
    context.read<LibraryProvider>().applyDelete(doc.path);
    _snack(context, 'Deleted');
  }

  // ---- Details ------------------------------------------------------------

  static Future<int?> _pageCount(String path) async {
    try {
      final document = await PdfDocument.openFile(path);
      final count = document.pages.length;
      await document.dispose();
      return count;
    } catch (_) {
      return null;
    }
  }

  static String _when(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}, ${formatTime(d)}';

  static Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> details(BuildContext context, PdfDocumentModel doc) async {
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;

    final store = ReadingStore(prefs, doc.path);
    final lastPage = store.loadPosition()?.page;
    final bookmarks = store.loadBookmarks().length;
    final hasNotes = store.loadNotes().trim().isNotEmpty;
    final pages = _pageCount(doc.path);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('Name', '${doc.name}${p.extension(doc.path)}'),
              _row('Folder', p.dirname(doc.path)),
              _row('Size', '${doc.formattedSize} (${doc.sizeBytes} bytes)'),
              _row('Modified', _when(doc.modified)),
              FutureBuilder<int?>(
                future: pages,
                builder: (_, snapshot) => _row(
                  'Pages',
                  snapshot.connectionState != ConnectionState.done
                      ? '…'
                      : (snapshot.data?.toString() ?? 'Unknown'),
                ),
              ),
              _row('Last read', lastPage == null ? 'Not opened yet' : 'Page $lastPage'),
              _row('Bookmarks', '$bookmarks'),
              _row('Notes', hasNotes ? 'Yes' : 'None'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
