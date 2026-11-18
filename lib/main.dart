import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/utils/system_ui.dart';
import 'providers/focus_mode.dart';
import 'providers/library_provider.dart';
import 'providers/reading_settings.dart';
import 'providers/recent_provider.dart';
import 'providers/study_timer.dart';
import 'providers/tasks_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  SystemUi.init();

  final prefs = await SharedPreferences.getInstance();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LibraryProvider(prefs)..init()),
        ChangeNotifierProvider(create: (_) => ReadingSettings(prefs)),
        ChangeNotifierProvider(create: (_) => StudyTimer(prefs)),
        ChangeNotifierProvider(create: (_) => FocusMode(prefs)),
        ChangeNotifierProvider(create: (_) => RecentProvider(prefs)),
        ChangeNotifierProvider(create: (_) => TasksProvider(prefs)),
      ],
      child: const EduPdfApp(),
    ),
  );
}
