import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Edge-to-edge screen with transparent system bars that can be hidden.
abstract final class SystemUi {
  /// True while the status bar and navigation bar are hidden.
  static final ValueNotifier<bool> hidden = ValueNotifier<bool>(false);

  static SystemUiOverlayStyle style({bool lightIcons = false}) {
    final icons = lightIcons ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: const Color(0x00000000),
      statusBarIconBrightness: icons,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarColor: const Color(0x00000000),
      systemNavigationBarDividerColor: const Color(0x00000000),
      systemNavigationBarIconBrightness: icons,
      systemNavigationBarContrastEnforced: false,
    );
  }

  static void init() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(style());
  }

  static void set(bool hide) {
    if (hidden.value == hide) return;
    hidden.value = hide;
    SystemChrome.setEnabledSystemUIMode(
      hide ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    if (!hide) SystemChrome.setSystemUIOverlayStyle(style());
  }

  static void toggle() => set(!hidden.value);
}
