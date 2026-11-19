import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Removes shared exports and other leftovers from the temporary folder.
abstract final class TempCleaner {
  /// At startup: files older than a day (exported PDFs, notes, samples).
  static Future<void> cleanOld() async {
    try {
      final dir = await getTemporaryDirectory();
      final cutoff = DateTime.now().subtract(const Duration(days: 1));
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) await entity.delete();
      }
    } catch (_) {}
  }

  /// On request: every temporary file plus the thumbnail cache.
  /// Copies of PDFs opened from other apps are kept, so reading position and
  /// notes for them are not lost.
  static Future<int> clearAll() async {
    var count = 0;
    try {
      final dir = await getTemporaryDirectory();
      await for (final entity in dir.list(followLinks: false)) {
        try {
          if (entity is File) {
            await entity.delete();
            count++;
          } else if (entity is Directory && p.basename(entity.path) == 'thumbs') {
            await for (final child in entity.list(followLinks: false)) {
              if (child is File) {
                await child.delete();
                count++;
              }
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
    return count;
  }
}
