import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/annotation_model.dart';
import '../models/task_model.dart';

/// The ".edunote" app format: a small JSON file that EduPDF Reader can import.
abstract final class NoteExchange {
  static const extension = 'edunote';
  static const mimeType = 'application/x-edunote';
  static const _marker = 'edupdf-notes';

  static String safeName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\n\r]'), '_').trim();
    if (cleaned.isEmpty) return 'notes';
    return cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned;
  }

  /// Reminders are left out on purpose: another person's times mean nothing.
  static String encode(List<TaskModel> tasks) => jsonEncode({
        'format': _marker,
        'version': 2,
        'exported': DateTime.now().toIso8601String(),
        'notes': [
          for (final t in tasks)
            {
              'title': t.title,
              'body': t.body,
              'items': [
                for (final i in t.items) {'t': i.text, 'd': i.done},
              ],
              'sketch': [for (final s in t.sketch) s.toJson()],
              'completed': t.completed,
            },
        ],
      });

  /// Returns null when [text] is not an EduPDF notes file.
  static List<TaskModel>? decode(String text) {
    try {
      final data = jsonDecode(text);
      if (data is! Map || data['format'] != _marker) return null;
      final list = data['notes'];
      if (list is! List) return null;
      return [
        for (final n in list)
          if (n is Map)
            TaskModel(
              id: 0,
              title: (n['title'] as String?) ?? '',
              body: (n['body'] as String?) ?? '',
              items: [
                for (final i in (n['items'] as List? ?? const []))
                  if (i is Map)
                    CheckItem(
                      text: (i['t'] as String?) ?? '',
                      done: (i['d'] as bool?) ?? false,
                    ),
              ],
              sketch: [
                for (final s in (n['sketch'] as List? ?? const []))
                  if (s is Map<String, dynamic>) Stroke.fromJson(s),
              ],
              completed: (n['completed'] as bool?) ?? false,
            ),
      ];
    } catch (_) {
      return null;
    }
  }

  static Future<File> writeFile(List<TaskModel> tasks, String name) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${safeName(name)}.$extension');
    await file.writeAsString(encode(tasks));
    return file;
  }
}
