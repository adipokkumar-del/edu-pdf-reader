import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

abstract final class PermissionHelper {
  static Future<bool> hasAccess() async {
    if (!Platform.isAndroid) return true;
    return await Permission.manageExternalStorage.isGranted ||
        await Permission.storage.isGranted;
  }

  /// Android 10 and below: classic storage dialog.
  /// Android 11+: opens the "All files access" settings page.
  static Future<bool> request() async {
    if (!Platform.isAndroid) return true;
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();
    return hasAccess();
  }
}
