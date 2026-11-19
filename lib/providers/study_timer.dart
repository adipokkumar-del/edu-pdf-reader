import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TimerPhase { focus, rest }

/// Minimal Pomodoro timer. Lives for the whole app, so it keeps running
/// when you go back to the library.
class StudyTimer extends ChangeNotifier {
  StudyTimer(this._prefs) {
    _focusMinutes = _prefs.getInt('timer_focus_minutes') ?? 25;
    _remaining = _focusMinutes * 60;
    _loadToday();
  }

  static const restMinutes = 5;
  static const focusOptions = [15, 25, 45, 60];

  final SharedPreferences _prefs;
  Timer? _ticker;

  /// Called when a focus session or a break ends.
  void Function(TimerPhase next)? onPhaseFinished;

  TimerPhase phase = TimerPhase.focus;
  int _focusMinutes = 25;
  int _remaining = 25 * 60;
  int studiedSeconds = 0;
  int sessions = 0;

  bool get running => _ticker != null;
  int get remaining => _remaining;
  int get focusMinutes => _focusMinutes;

  String get _dayKey {
    final d = DateTime.now();
    return 'study_${d.year}_${d.month}_${d.day}';
  }

  void _loadToday() {
    final raw = _prefs.getString(_dayKey);
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      studiedSeconds = m['s'] as int;
      sessions = m['n'] as int;
    } catch (_) {}
  }

  void _saveToday() {
    _prefs.setString(_dayKey, jsonEncode({'s': studiedSeconds, 'n': sessions}));
  }

  void setFocusMinutes(int minutes) {
    if (running) return;
    _focusMinutes = minutes;
    _prefs.setInt('timer_focus_minutes', minutes);
    if (phase == TimerPhase.focus) _remaining = minutes * 60;
    notifyListeners();
  }

  void start() {
    if (running) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    notifyListeners();
  }

  void pause() {
    _ticker?.cancel();
    _ticker = null;
    _saveToday();
    notifyListeners();
  }

  void reset() {
    _ticker?.cancel();
    _ticker = null;
    _remaining =
        (phase == TimerPhase.focus ? _focusMinutes : restMinutes) * 60;
    _saveToday();
    notifyListeners();
  }

  /// Jump to the other phase (focus <-> break).
  void skip() {
    _ticker?.cancel();
    _ticker = null;
    phase = phase == TimerPhase.focus ? TimerPhase.rest : TimerPhase.focus;
    _remaining =
        (phase == TimerPhase.focus ? _focusMinutes : restMinutes) * 60;
    notifyListeners();
  }

  void _tick() {
    _remaining--;
    if (phase == TimerPhase.focus) {
      studiedSeconds++;
      if (studiedSeconds % 30 == 0) _saveToday();
    }
    if (_remaining <= 0) _finish();
    notifyListeners();
  }

  void _finish() {
    _ticker?.cancel();
    _ticker = null;
    if (phase == TimerPhase.focus) {
      sessions++;
      phase = TimerPhase.rest;
      _remaining = restMinutes * 60;
    } else {
      phase = TimerPhase.focus;
      _remaining = _focusMinutes * 60;
    }
    _saveToday();
    HapticFeedback.heavyImpact();
    onPhaseFinished?.call(phase);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
