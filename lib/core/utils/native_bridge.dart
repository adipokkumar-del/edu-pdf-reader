import 'dart:io';

import 'package:flutter/services.dart';

/// Talks to MainActivity.kt (incoming PDFs, Do Not Disturb, reminders).
abstract final class NativeBridge {
  static const _channel = MethodChannel('edu_pdf/native');

  /// Called when another app opens a PDF with us while we are running.
  static void Function(String path)? onOpenPdf;

  static void listen() {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openPdf') {
        final path = call.arguments as String?;
        if (path != null) onOpenPdf?.call(path);
      }
      return null;
    });
  }

  static Future<String?> initialPdf() => _call<String>('getInitialPdf');

  // Do Not Disturb
  static Future<bool> hasDndAccess() async =>
      await _call<bool>('hasDndAccess') ?? false;

  static Future<void> openDndSettings() => _call<void>('openDndSettings');

  static Future<bool> setMute(bool enabled) async =>
      await _call<bool>('setMute', {'enabled': enabled}) ?? false;

  // Reminders and alarms
  static Future<void> syncReminders(String json) async {
    await _call<bool>('syncReminders', {'json': json});
  }

  static Future<bool> canExactAlarms() async =>
      await _call<bool>('canExactAlarms') ?? true;

  static Future<void> openExactAlarmSettings() =>
      _call<void>('openExactAlarmSettings');

  /// Opens the system file picker and returns a readable file path, or null.
  static Future<String?> pickFile() => _call<String>('pickFile');

  /// Saves a file into Downloads/EduPDF. Returns where it went, or null.
  static Future<String?> saveToDownloads(
          String path, String name, String mime) =>
      _call<String>(
          'saveToDownloads', {'path': path, 'name': name, 'mime': mime});

  /// 'self' (we are the default), 'other', or 'none'.
  static Future<String> defaultPdfState() async =>
      await _call<String>('defaultPdfState') ?? 'none';

  static Future<bool> chooseDefaultPdf(String path) async =>
      await _call<bool>('chooseDefaultPdf', {'path': path}) ?? false;

  static Future<void> openDefaultAppsSettings() =>
      _call<void>('openDefaultAppsSettings');

  static Future<void> setSecure(bool enabled) =>
      _call<void>('setSecure', {'enabled': enabled});

  static Future<T?> _call<T>(String method, [Object? args]) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } catch (_) {
      return null;
    }
  }
}
