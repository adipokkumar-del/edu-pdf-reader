import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/native_bridge.dart';

/// Mutes notifications (Do Not Disturb) while a PDF is open.
class FocusMode extends ChangeNotifier with WidgetsBindingObserver {
  FocusMode(this._prefs) {
    muteEnabled = _prefs.getBool('mute_enabled') ?? false;
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  final SharedPreferences _prefs;

  bool muteEnabled = false;
  bool hasAccess = false;
  int _readers = 0;

  Future<void> _init() async {
    // Undo anything a previous run left behind (e.g. the app was killed).
    await NativeBridge.setMute(false);
    await _refresh();
  }

  Future<void> setMuteEnabled(bool value) async {
    muteEnabled = value;
    _prefs.setBool('mute_enabled', value);
    hasAccess = await NativeBridge.hasDndAccess();
    notifyListeners();
    if (value && !hasAccess) {
      await NativeBridge.openDndSettings();
      return;
    }
    await _apply();
  }

  Future<void> openAccessSettings() => NativeBridge.openDndSettings();

  Future<void> enterReader() {
    _readers++;
    return _apply();
  }

  Future<void> leaveReader() {
    if (_readers > 0) _readers--;
    return _apply();
  }

  Future<void> _refresh() async {
    hasAccess = await NativeBridge.hasDndAccess();
    notifyListeners();
    await _apply();
  }

  Future<void> _apply() async {
    final shouldMute = _readers > 0 && muteEnabled && hasAccess;
    await NativeBridge.setMute(shouldMute);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    } else if (state == AppLifecycleState.paused) {
      // Leaving the app means you are not reading any more.
      NativeBridge.setMute(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
