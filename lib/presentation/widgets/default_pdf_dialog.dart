import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/native_bridge.dart';

/// Helps you make EduPDF Reader the app that opens PDF files.
/// Android decides the default itself: we can only open its chooser.
abstract final class DefaultPdfDialog {
  static Future<void> _chooseNow() async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(build: (_) => pw.Center(child: pw.Text('EduPDF Reader'))),
    );
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/edupdf-sample.pdf');
    await file.writeAsBytes(await doc.save());
    await NativeBridge.chooseDefaultPdf(file.path);
  }

  static Future<void> show(BuildContext context) async {
    final state = await NativeBridge.defaultPdfState();
    if (!context.mounted) return;

    final message = switch (state) {
      'self' => 'EduPDF Reader already opens your PDF files by default.',
      'other' => 'Another app opens PDFs by default right now.\n\n'
          'To switch: open Settings, then Apps, then that app, then '
          '"Open by default", and tap "Clear defaults". After that, tap '
          '"Choose now", pick EduPDF Reader and tap "Always".',
      _ => 'No default PDF app is set.\n\n'
          'Tap "Choose now", pick EduPDF Reader and then tap "Always".',
    };

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Default PDF app'),
        content: Text(message),
        actions: [
          if (state == 'other')
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                NativeBridge.openDefaultAppsSettings();
              },
              child: const Text('Settings'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          if (state != 'self')
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _chooseNow();
              },
              child: const Text('Choose now'),
            ),
        ],
      ),
    );
  }

  /// Asks once, the very first time the app is opened.
  static Future<void> promptOnce(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('default_prompt_done') ?? false) return;
    await prefs.setBool('default_prompt_done', true);

    final state = await NativeBridge.defaultPdfState();
    if (state == 'self' || !context.mounted) return;

    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Open PDFs with EduPDF?'),
        content: const Text(
          'You can make EduPDF Reader the app that opens all PDF files on '
          'this phone. You can change this later from the ⋮ menu in the Library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Set up'),
          ),
        ],
      ),
    );
    if (go == true && context.mounted) await _chooseNow();
  }
}
