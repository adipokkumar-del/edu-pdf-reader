import 'dart:io';

import 'package:flutter/services.dart';

/// Talks to MainActivity.kt (incoming PDFs, Do Not Disturb).
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

  static Future<bool> hasDndAccess() async =>
      await _call<bool>('hasDndAccess') ?? false;

  static Future<void> openDndSettings() => _call<void>('openDndSettings');

  static Future<bool> setMute(bool enabled) async =>
      await _call<bool>('setMute', {'enabled': enabled}) ?? false;

  static Future<T?> _call<T>(String method, [Object? args]) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } catch (_) {
      return null;
    }
  }
}
