import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../data/models/pdf_document_model.dart';

abstract final class PdfScanner {
  static const _root = '/storage/emulated/0';

  /// Scans device storage for PDF files on a background isolate.
  static Future<List<PdfDocumentModel>> scan() => compute(_scan, _root);
}

List<PdfDocumentModel> _scan(String root) {
  final results = <PdfDocumentModel>[];
  final pending = <Directory>[Directory(root)];

  while (pending.isNotEmpty) {
    final dir = pending.removeLast();

    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } catch (_) {
      continue; // Unreadable directory: skip it.
    }

    for (final entity in entries) {
      final name = p.basename(entity.path);

      if (entity is Directory) {
        if (name.startsWith('.')) continue;
        if (entity.path.contains('/Android/data') ||
            entity.path.contains('/Android/obb')) {
          continue;
        }
        pending.add(entity);
      } else if (entity is File && name.toLowerCase().endsWith('.pdf')) {
        try {
          final stat = entity.statSync();
          if (stat.size <= 0) continue;
          results.add(PdfDocumentModel(
            path: entity.path,
            name: p.basenameWithoutExtension(entity.path),
            sizeBytes: stat.size,
            modified: stat.modified,
          ));
        } catch (_) {
          continue;
        }
      }
    }
  }
  return results;
}
