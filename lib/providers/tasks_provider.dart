import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/native_bridge.dart';
import '../data/models/task_model.dart';

class TasksProvider extends ChangeNotifier {
  TasksProvider(this._prefs) {
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncNative());
  }

  static const _key = 'tasks_v1';

  final SharedPreferences _prefs;
  List<TaskModel> tasks = [];

  int get pending => tasks.where((t) => !t.completed).length;

  /// Open items first (soonest reminder on top), finished ones last.
  List<TaskModel> get ordered {
    final list = List<TaskModel>.of(tasks);
    list.sort((a, b) {
      final byDone = (a.completed ? 1 : 0).compareTo(b.completed ? 1 : 0);
      if (byDone != 0) return byDone;
      final x = a.remindAt;
      final y = b.remindAt;
      if (x != null && y != null) return x.compareTo(y);
      if (x != null) return -1;
      if (y != null) return 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  void upsert(TaskModel task) {
    final i = tasks.indexWhere((t) => t.id == task.id);
    if (i >= 0) {
      tasks[i] = task;
    } else {
      tasks.insert(0, task);
    }
    _commit();
  }

  void delete(int id) {
    tasks.removeWhere((t) => t.id == id);
    _commit();
  }

  void toggleItem(TaskModel task, int index) {
    task.items[index].done = !task.items[index].done;
    _commit();
  }

  void toggleCompleted(TaskModel task) {
    task.completed = !task.completed;
    _commit();
  }

  void _commit() {
    _save();
    notifyListeners();
    _syncNative();
  }

  void _load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    try {
      tasks = [
        for (final t in jsonDecode(raw) as List)
          TaskModel.fromJson(t as Map<String, dynamic>),
      ];
    } catch (_) {
      tasks = [];
    }
  }

  void _save() {
    _prefs.setString(_key, jsonEncode([for (final t in tasks) t.toJson()]));
  }

  /// Tells Android which reminders should be scheduled right now.
  Future<void> _syncNative() async {
    final now = DateTime.now();
    final list = [
      for (final t in tasks)
        if (!t.completed &&
            t.remindAt != null &&
            (t.repeatDaily || t.remindAt!.isAfter(now)))
          {
            'id': t.id,
            'at': t.remindAt!.millisecondsSinceEpoch,
            'title': t.displayTitle,
            'text': t.reminderText,
            'alarm': t.alarm,
            'repeat': t.repeatDaily,
          },
    ];
    await NativeBridge.syncReminders(jsonEncode(list));
  }
}
