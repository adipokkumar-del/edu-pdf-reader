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

  // Note: SystemUiMode.edgeToEdge is ignored on Android 9 and older, so bars
  // that were hidden would never come back. Manual mode works on every version.
  static void _showBars() => SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );

  static void init() {
    _showBars();
    SystemChrome.setSystemUIOverlayStyle(style());
  }

  static void set(bool hide) {
    if (hidden.value == hide) return;
    hidden.value = hide;
    if (hide) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      _showBars();
    }
    if (!hide) SystemChrome.setSystemUIOverlayStyle(style());
  }

  static void toggle() => set(!hidden.value);
}
