import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/utils/native_bridge.dart';
import '../models/task_model.dart';
import 'note_exchange.dart';
import 'notes_pdf_service.dart';

/// Builds a PDF of the given notes and saves it in Downloads/EduPDF.
Future<void> saveTasksAsPdf(BuildContext context, List<TaskModel> tasks) async {
  if (tasks.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);

  final progress = ValueNotifier<double>(0);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Saving PDF…'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, __) =>
              LinearProgressIndicator(value: v == 0 ? null : v),
        ),
      ),
    ),
  );

  String? where;
  try {
    final heading =
        tasks.length == 1 ? tasks.first.displayTitle : 'Notes & Checklists';
    final File file = await NotesPdfService.build(
      heading: heading,
      tasks: tasks,
      onProgress: (v) => progress.value = v,
    );
    where = await NativeBridge.saveToDownloads(
      file.path,
      '${NoteExchange.safeName(heading)}.pdf',
      'application/pdf',
    );
  } catch (_) {
    where = null;
  }

  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          where == null ? 'Could not save the PDF.' : 'Saved to $where',
        ),
      ),
    );
}
