
import 'dart:io';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../../core/utils/stroke_painting.dart';
import '../models/annotation_model.dart';

abstract final class ExportService {
  static String _safeName(String title) =>
      title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

  /// Creates a PDF that holds only the pages you drew on, with the drawings
  /// baked in. Pages are saved as images, so the text is not selectable.
  static Future<File> annotatedPdf({
    required PdfDocument document,
    required Map<int, List<Stroke>> strokes,
    required String title,
    void Function(double progress)? onProgress,
  }) async {
    final out = pw.Document();
    final indexes = strokes.keys.toList()..sort();
    var added = 0;

    for (var n = 0; n < indexes.length; n++) {
      final i = indexes[n];
      if (i < 0 || i >= document.pages.length) continue;

      final page = document.pages[i];
      const targetWidth = 1400.0;
      final w = targetWidth.round();
      final h = (targetWidth * page.height / page.width).round();

      final rendered = await page.render(
        width: w,
        height: h,
        fullWidth: w.toDouble(),
        fullHeight: h.toDouble(),
        backgroundColor: 0xFFFFFFFF,
      );
      if (rendered == null) continue;

      ui.Image base;
      try {
        base = await rendered.createImage();
      } finally {
        rendered.dispose();
      }

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImage(base, ui.Offset.zero, ui.Paint());
      final size = ui.Size(w.toDouble(), h.toDouble());
      for (final s in strokes[i]!) {
        paintStroke(canvas, size, s);
      }
      final composed = await recorder.endRecording().toImage(w, h);
      final data = await composed.toByteData(format: ui.ImageByteFormat.png);
      base.dispose();
      composed.dispose();
      if (data == null) continue;

      final png = data.buffer.asUint8List();
      out.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(page.width, page.height),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.SizedBox(
            width: page.width,
            height: page.height,
            child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill),
          ),
        ),
      );
      added++;
      onProgress?.call((n + 1) / indexes.length);
    }

    if (added == 0) throw StateError('No pages could be exported');

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_safeName(title)}-annotated.pdf');
    await file.writeAsBytes(await out.save());
    return file;
  }

  /// Notes and bookmarks as a UTF-8 text file (Bangla is fine).
  static Future<File> notesFile({
    required String title,
    required String notes,
    required List<int> bookmarks,
  }) async {
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final buffer = StringBuffer()
      ..writeln(title)
      ..writeln('Exported: ${d.year}-${two(d.month)}-${two(d.day)}')
      ..writeln();

    if (bookmarks.isNotEmpty) {
      buffer
        ..writeln('Bookmarked pages: ${bookmarks.join(', ')}')
        ..writeln();
    }
    if (notes.trim().isNotEmpty) {
      buffer
        ..writeln('--- Notes ---')
        ..writeln(notes.trim());
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_safeName(title)}-notes.txt');
    await file.writeAsString(buffer.toString());
    return file;
  }
}
