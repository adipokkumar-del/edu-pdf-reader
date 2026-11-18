import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;

import '../models/task_model.dart';
import 'note_exchange.dart';

const _pageW = 1240.0; // A4 at 150 dpi
const _pageH = 1754.0;
const _margin = 100.0;

const _ink = Color(0xFF3E2723);
const _muted = Color(0xFF8D6E63);
const _brown = Color(0xFF6D4C41);
const _rule = Color(0xFFD7CCC8);

const _brand = TextStyle(
  fontSize: 22,
  letterSpacing: 3,
  fontWeight: FontWeight.w700,
  color: _brown,
);
const _title = TextStyle(
  fontSize: 58,
  fontWeight: FontWeight.w800,
  color: _ink,
  height: 1.25,
);
const _h2 = TextStyle(
  fontSize: 38,
  fontWeight: FontWeight.w800,
  color: _ink,
  height: 1.35,
);
const _body = TextStyle(fontSize: 30, color: _ink, height: 1.55);
const _meta = TextStyle(fontSize: 24, color: _muted, height: 1.4);

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Builds a PDF of notes and checklists.
///
/// Text is drawn with Flutter's own text engine (so Bangla conjuncts come out
/// right) and each page is stored in the PDF as an image.
abstract final class NotesPdfService {
  static Future<File> build({
    required String heading,
    required List<TaskModel> tasks,
    void Function(double progress)? onProgress,
  }) async {
    final c = _Composer();

    final now = DateTime.now();
    c.text('EDUPDF READER', _brand);
    c.gap(8);
    c.text(heading, _title);
    c.gap(4);
    c.text('Exported ${now.day} ${_months[now.month - 1]} ${now.year}', _meta);
    c.gap(22);
    c.rule();
    c.gap(26);

    for (var i = 0; i < tasks.length; i++) {
      final t = tasks[i];
      final title = t.title.trim();
      if (title.isNotEmpty) {
        c.text(title, _h2);
        c.gap(8);
      }
      if (t.body.trim().isNotEmpty) {
        c.text(t.body.trim(), _body);
        c.gap(10);
      }
      for (final item in t.items) {
        c.checkItem(item.text, item.done);
      }
      final at = t.remindAt;
      if (at != null) {
        c.gap(4);
        c.text('Reminder: ${formatWhen(at, daily: t.repeatDaily)}', _meta);
      }
      if (t.completed) c.text('Marked as done', _meta);

      c.gap(18);
      if (i < tasks.length - 1) {
        c.rule();
        c.gap(24);
      }
    }
    c.finish();

    final format = PdfPageFormat.a4;
    final doc = pw.Document();
    final total = c.pages.length;
    for (var i = 0; i < total; i++) {
      final picture = c.pages[i];
      final image = await picture.toImage(_pageW.round(), _pageH.round());
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      if (data == null) continue;

      final png = data.buffer.asUint8List();
      doc.addPage(
        pw.Page(
          pageFormat: format,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.SizedBox(
            width: format.width,
            height: format.height,
            child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill),
          ),
        ),
      );
      onProgress?.call((i + 1) / total);
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${NoteExchange.safeName(heading)}.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }
}

/// Lays text and checklist rows onto A4 pages, starting a new page as needed.
class _Composer {
  final List<ui.Picture> pages = [];

  ui.PictureRecorder? _recorder;
  Canvas? _canvas;
  double _y = 0;

  static const double _contentWidth = _pageW - _margin * 2;
  static const double _bottom = _pageH - _margin;

  bool get _fresh => _canvas != null && _y <= _margin + 0.5;

  void _start() {
    _finishPage();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _pageW, _pageH),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    _recorder = recorder;
    _canvas = canvas;
    _y = _margin;
  }

  void _finishPage() {
    final recorder = _recorder;
    final canvas = _canvas;
    if (recorder == null || canvas == null) return;

    final number = TextPainter(
      text: TextSpan(
        text: '${pages.length + 1}',
        style: const TextStyle(fontSize: 22, color: _muted),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    number.paint(
      canvas,
      Offset((_pageW - number.width) / 2, _pageH - _margin / 2 - number.height / 2),
    );

    pages.add(recorder.endRecording());
    _recorder = null;
    _canvas = null;
  }

  void finish() => _finishPage();

  void gap(double h) => _y += h;

  /// Makes room for an unbreakable block of height [h].
  Canvas _reserve(double h) {
    if (_canvas == null || (_y + h > _bottom && !_fresh)) _start();
    return _canvas!;
  }

  void rule() {
    final canvas = _reserve(3);
    canvas.drawLine(
      Offset(_margin, _y),
      Offset(_pageW - _margin, _y),
      Paint()
        ..color = _rule
        ..strokeWidth = 2,
    );
    _y += 3;
  }

  /// A paragraph that may continue on the next page, split between lines.
  void text(String value, TextStyle style) {
    if (value.trim().isEmpty) return;

    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _contentWidth);
    final lines = painter.computeLineMetrics();

    var index = 0;
    var consumed = 0.0;
    while (index < lines.length) {
      if (_canvas == null) _start();

      final available = _bottom - _y;
      var take = 0;
      var chunk = 0.0;
      while (index + take < lines.length &&
          chunk + lines[index + take].height <= available + 0.5) {
        chunk += lines[index + take].height;
        take++;
      }
      if (take == 0) {
        if (_fresh) {
          take = 1;
          chunk = lines[index].height;
        } else {
          _start();
          continue;
        }
      }

      final canvas = _canvas!;
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(_margin, _y, _contentWidth, chunk));
      painter.paint(canvas, Offset(_margin, _y - consumed));
      canvas.restore();

      _y += chunk;
      consumed += chunk;
      index += take;
      if (index < lines.length) _start();
    }
  }

  void checkItem(String value, bool done) {
    const box = 28.0;
    const gap = 18.0;

    final style = done
        ? _body.copyWith(
            color: _muted,
            decoration: TextDecoration.lineThrough,
            decorationColor: _muted,
          )
        : _body;
    final painter = TextPainter(
      text: TextSpan(text: value.isEmpty ? ' ' : value, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _contentWidth - box - gap);

    final rowHeight = math.max(painter.height, box);
    final canvas = _reserve(rowHeight);
    final top = _y;

    final firstLine = painter.computeLineMetrics().first.height;
    final boxTop = top + (firstLine - box) / 2;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(_margin, boxTop, box, box),
      const Radius.circular(7),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _brown,
    );
    if (done) {
      canvas.drawRRect(rect, Paint()..color = _brown.withValues(alpha: 0.15));
      final tick = Path()
        ..moveTo(_margin + 6, boxTop + 15)
        ..lineTo(_margin + 12, boxTop + 21)
        ..lineTo(_margin + 23, boxTop + 8);
      canvas.drawPath(
        tick,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = _brown,
      );
    }

    painter.paint(canvas, Offset(_margin + box + gap, top));
    _y += rowHeight + 10;
  }
}
