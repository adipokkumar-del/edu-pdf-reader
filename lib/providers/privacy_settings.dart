import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/native_bridge.dart';

/// "Privacy screen": hides the app in the recent-apps list and blocks screenshots.
class PrivacySettings extends ChangeNotifier {
  PrivacySettings(this._prefs) {
    secure = _prefs.getBool('privacy_secure') ?? false;
    if (secure) NativeBridge.setSecure(true);
  }

  final SharedPreferences _prefs;
  bool secure = false;

  Future<void> setSecure(bool value) async {
    secure = value;
    await _prefs.setBool('privacy_secure', value);
    await NativeBridge.setSecure(value);
    notifyListeners();
  }
}
