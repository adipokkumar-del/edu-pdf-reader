import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

class _Job {
  _Job(this.path, this.key);

  final String path;
  final String key;
  final Completer<Uint8List?> done = Completer<Uint8List?>();
  bool cancelled = false;
}

class ThumbnailHandle {
  ThumbnailHandle._(this._job);

  final _Job _job;

  Future<Uint8List?> get future => _job.done.future;

  void cancel() => _job.cancelled = true;
}

/// Renders first-page thumbnails one at a time, newest request first
/// (so what is on screen wins), and keeps them on disk.
class ThumbnailService {
  ThumbnailService._();

  static final ThumbnailService instance = ThumbnailService._();

  static const _width = 180;
  static const _memoryLimit = 60;

  final _memory = LinkedHashMap<String, Uint8List>();
  final _stack = <_Job>[];
  bool _busy = false;
  Directory? _dir;

  ThumbnailHandle request(String path, int size, DateTime modified) {
    final key = Object.hash(path, size, modified.millisecondsSinceEpoch)
        .toRadixString(16);
    final job = _Job(path, key);

    final hit = _memory.remove(key);
    if (hit != null) {
      _memory[key] = hit;
      job.done.complete(hit);
    } else {
      _stack.add(job);
      _pump();
    }
    return ThumbnailHandle._(job);
  }

  Future<void> _pump() async {
    if (_busy) return;
    _busy = true;
    try {
      while (_stack.isNotEmpty) {
        final job = _stack.removeLast();
        if (job.cancelled) {
          job.done.complete(null);
          continue;
        }
        Uint8List? bytes;
        try {
          bytes = await _load(job);
        } catch (_) {
          bytes = null;
        }
        if (bytes != null) {
          _memory[job.key] = bytes;
          while (_memory.length > _memoryLimit) {
            _memory.remove(_memory.keys.first);
          }
        }
        job.done.complete(bytes);
      }
    } finally {
      _busy = false;
    }
  }

  Future<Directory> _cacheDir() async {
    final existing = _dir;
    if (existing != null) return existing;
    final base = await getTemporaryDirectory();
    final dir = await Directory('${base.path}/thumbs').create(recursive: true);
    _dir = dir;
    return dir;
  }

  Future<Uint8List?> _load(_Job job) async {
    final dir = await _cacheDir();
    final file = File('${dir.path}/${job.key}.png');
    if (await file.exists()) return file.readAsBytes();

    final doc = await PdfDocument.openFile(job.path);
    try {
      if (doc.pages.isEmpty) return null;
      final page = doc.pages.first;
      final h = (_width * page.height / page.width).round();

      final rendered = await page.render(
        width: _width,
        height: h,
        fullWidth: _width.toDouble(),
        fullHeight: h.toDouble(),
        backgroundColor: const ui.Color(0xFFFFFFFF),
      );
      if (rendered == null) return null;

      ui.Image image;
      try {
        image = await rendered.createImage();
      } finally {
        rendered.dispose();
      }
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return null;

      final bytes = data.buffer.asUint8List();
      await file.writeAsBytes(bytes);
      return bytes;
    } finally {
      await doc.dispose();
    }
  }
}
