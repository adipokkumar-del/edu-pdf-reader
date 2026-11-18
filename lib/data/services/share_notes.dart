import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/native_bridge.dart';
import '../../providers/tasks_provider.dart';
import '../models/task_model.dart';
import 'export_service.dart';
import 'note_exchange.dart';
import 'notes_pdf_service.dart';

enum ShareFormat { pdf, app, text }

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<ShareFormat?> chooseShareFormat(
  BuildContext context, {
  bool allowText = false,
}) {
  return showModalBottomSheet<ShareFormat>(
    context: context,
    backgroundColor: Colors.white,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Share as',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined,
                color: AppColors.brown),
            title: const Text('PDF'),
            subtitle: const Text('Easy to read and print anywhere'),
            onTap: () => Navigator.pop(ctx, ShareFormat.pdf),
          ),
          ListTile(
            leading:
                const Icon(Icons.inventory_2_outlined, color: AppColors.brown),
            title: const Text('App file (.edunote)'),
            subtitle: const Text('Opens in EduPDF Reader, checklists intact'),
            onTap: () => Navigator.pop(ctx, ShareFormat.app),
          ),
          if (allowText)
            ListTile(
              leading: const Icon(Icons.text_snippet_outlined,
                  color: AppColors.brown),
              title: const Text('Plain text (.txt)'),
              onTap: () => Navigator.pop(ctx, ShareFormat.text),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Runs [job] behind a small progress dialog. Returns null if it failed.
Future<T?> _withProgress<T>(
  BuildContext context,
  String title,
  Future<T> Function(ValueNotifier<double> progress) job,
) async {
  final progress = ValueNotifier<double>(0);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: Colors.white,
        title: Text(title),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, __) =>
              LinearProgressIndicator(value: v == 0 ? null : v),
        ),
      ),
    ),
  );

  T? result;
  try {
    result = await job(progress);
  } catch (_) {
    result = null;
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  return result;
}

/// Shares notes and checklists from the Notes tab.
Future<void> shareTasks(
  BuildContext context,
  List<TaskModel> tasks,
  ShareFormat format,
) async {
  if (tasks.isEmpty) return;
  const heading = 'Notes & Checklists';

  File? file;
  String mime;
  switch (format) {
    case ShareFormat.pdf:
      file = await _withProgress<File>(
        context,
        'Preparing PDF…',
        (progress) => NotesPdfService.build(
          heading: heading,
          tasks: tasks,
          onProgress: (v) => progress.value = v,
        ),
      );
      mime = 'application/pdf';
    case ShareFormat.app:
    case ShareFormat.text:
      final name = tasks.length == 1 ? tasks.first.displayTitle : 'EduPDF notes';
      file = await NoteExchange.writeFile(tasks, name);
      mime = NoteExchange.mimeType;
  }

  if (file == null) {
    if (context.mounted) {
      _snack(context, 'Could not create the file. Please try again.');
    }
    return;
  }
  await Share.shareXFiles(
    [XFile(file.path, mimeType: mime)],
    subject: heading,
  );
}

/// Shares the notepad (and bookmarks) of one PDF.
Future<void> shareDocumentNotes(
  BuildContext context, {
  required String title,
  required String notes,
  required List<int> bookmarks,
}) async {
  if (notes.trim().isEmpty && bookmarks.isEmpty) {
    _snack(context, 'No notes or bookmarks to export yet.');
    return;
  }

  final format = await chooseShareFormat(context, allowText: true);
  if (format == null || !context.mounted) return;

  File? file;
  String mime;
  switch (format) {
    case ShareFormat.text:
      file = await ExportService.notesFile(
        title: title,
        notes: notes,
        bookmarks: bookmarks,
      );
      mime = 'text/plain';
    case ShareFormat.pdf:
      final blocks = [
        if (notes.trim().isNotEmpty)
          TaskModel(id: 0, title: 'Notes', body: notes.trim()),
        if (bookmarks.isNotEmpty)
          TaskModel(
            id: 1,
            title: 'Bookmarked pages',
            body: bookmarks.join(', '),
          ),
      ];
      file = await _withProgress<File>(
        context,
        'Preparing PDF…',
        (progress) => NotesPdfService.build(
          heading: title,
          tasks: blocks,
          onProgress: (v) => progress.value = v,
        ),
      );
      mime = 'application/pdf';
    case ShareFormat.app:
      final body = [
        if (notes.trim().isNotEmpty) notes.trim(),
        if (bookmarks.isNotEmpty) 'Bookmarked pages: ${bookmarks.join(', ')}',
      ].join('\n\n');
      file = await NoteExchange.writeFile(
        [TaskModel(id: 0, title: 'Notes: $title', body: body)],
        title,
      );
      mime = NoteExchange.mimeType;
  }

  if (file == null) {
    if (context.mounted) {
      _snack(context, 'Could not create the file. Please try again.');
    }
    return;
  }
  await Share.shareXFiles(
    [XFile(file.path, mimeType: mime)],
    subject: '$title (notes)',
  );
}

/// Opens the system file picker and imports the chosen .edunote file.
Future<void> importNotesFromPicker(BuildContext context) async {
  final path = await NativeBridge.pickFile();
  if (path == null || !context.mounted) return;
  await importNotesFromPath(context, path);
}

Future<void> importNotesFromPath(BuildContext context, String path) async {
  List<TaskModel>? notes;
  try {
    notes = NoteExchange.decode(await File(path).readAsString());
  } catch (_) {
    notes = null;
  }
  if (!context.mounted) return;

  if (notes == null || notes.isEmpty) {
    _snack(context, 'This file is not an EduPDF notes file.');
    return;
  }
  context.read<TasksProvider>().importAll(notes);
  _snack(
    context,
    'Imported ${notes.length} note${notes.length == 1 ? '' : 's'}. '
    'Open the Notes tab to see them.',
  );
}
